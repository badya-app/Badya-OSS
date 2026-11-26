/**
 * Cloud Function: Submit a user moderation report.
 *
 * This is the SERVER-SIDE authority for the reporting feature. The Flutter
 * app keeps its own client-side guards (duplicate-pending, 5/day cap) as a
 * fast path for good UX, but a modified client can bypass those — so the
 * actual write happens here, where the Admin SDK re-checks everything:
 *
 *   1. Authentication (the reporter uid comes from the verified ID token,
 *      never from request data)
 *   2. Input shape (reason allowlist, details length, no self-reports)
 *   3. Duplicate pending report against the same user
 *   4. Daily report cap (5 per UTC day, server clock)
 *
 * Because the Admin SDK bypasses Firestore security rules, the client rules
 * now block ALL direct writes to `reports` (`allow create: if false`) — this
 * function is the only way a report document gets created.
 *
 * Query note: both pre-write checks need the composite indexes declared in
 * `firestore.indexes.json` for the `reports` collection:
 *   - reporter_uid (ASC) + reported_uid (ASC) + status (ASC)
 *   - reporter_uid (ASC) + created_at (ASC)
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import { createRateLimiter } from "./rate-limiter";

/** Reasons a report can carry — must match the client `ReportReason` allowlist. */
export const REPORT_REASONS: readonly string[] = [
  "violence",
  "sexual_content",
  "hate_speech",
  "harassment",
  "spam",
  "impersonation",
  "other",
];

/** Maximum reports a single user can submit per UTC calendar day. */
export const MAX_DAILY_REPORTS = 5;

/** Maximum length of the optional free-text `details` field. */
export const MAX_DETAILS_LENGTH = 500;

/**
 * Maximum length of a reported uid. Firebase Auth uids are at most 128
 * characters; bounding this keeps a modified client from storing an
 * arbitrarily large `reported_uid` in the report document.
 */
export const MAX_REPORTED_UID_LENGTH = 128;

/** Coarse anti-abuse guard: at most 10 submissions per 60s per instance. */
const reportLimiter = createRateLimiter(10, 60_000);

/** Normalized, validated report payload after [validateReportPayload]. */
export interface ValidatedReport {
  reportedUid: string;
  reason: string;
  details: string;
}

export type ReportValidationResult =
  | { ok: true; payload: ValidatedReport }
  | { ok: false; message: string };

/**
 * Validate + normalize a raw callable payload.
 *
 * Pure (no Firestore/network access) so it can be unit-tested directly.
 * [authUid] is the caller's uid from the verified ID token; the reported uid
 * is only ever compared against it (never trusted as an identity).
 */
export function validateReportPayload(
  data: unknown,
  authUid: string,
): ReportValidationResult {
  const input = (data ?? {}) as Record<string, unknown>;

  const reportedUid = input.reportedUid;
  if (typeof reportedUid !== "string" || reportedUid.trim().length === 0) {
    return { ok: false, message: "A user to report is required." };
  }
  if (reportedUid.trim().length > MAX_REPORTED_UID_LENGTH) {
    return { ok: false, message: "The reported user id is invalid." };
  }
  // Compare against the TRIMMED value (which is what gets stored) so a
  // whitespace-padded self-report like " me " can't slip past the guard.
  if (reportedUid.trim() === authUid) {
    return { ok: false, message: "You cannot report yourself." };
  }

  const reason = input.reason;
  if (typeof reason !== "string" || !REPORT_REASONS.includes(reason)) {
    return { ok: false, message: "Invalid report reason." };
  }

  let details = "";
  if (input.details !== undefined && input.details !== null) {
    if (typeof input.details !== "string") {
      return { ok: false, message: "Report details must be text." };
    }
    details = input.details.trim();
    if (details.length > MAX_DETAILS_LENGTH) {
      return {
        ok: false,
        message: `Report details must be ${MAX_DETAILS_LENGTH} characters or fewer.`,
      };
    }
  }

  return {
    ok: true,
    payload: {
      reportedUid: reportedUid.trim(),
      reason,
      details,
    },
  };
}

/**
 * UTC start of the calendar day containing [now].
 *
 * The daily cap is defined on the SERVER clock (UTC midnight), so changing
 * the device clock cannot reset it. Firestore timestamps are UTC-based, so
 * comparing `created_at >= startOfDayUtc(...)` is a clean day boundary.
 */
export function startOfDayUtc(now: Date): Date {
  return new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()),
  );
}

export const submitReport = onCall<{
  reportedUid: string;
  reason: string;
  details?: string;
}>(
  {
    cors: true,
    maxInstances: 10,
  },
  async (request) => {
    // The reporter is ALWAYS the authenticated caller — request data never
    // carries an identity.
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "You must be signed in to report a user.",
      );
    }
    const uid = request.auth.uid;

    if (!reportLimiter.allow(uid)) {
      throw new HttpsError(
        "resource-exhausted",
        "Too many requests. Please try again later.",
      );
    }

    const validation = validateReportPayload(request.data, uid);
    if (!validation.ok) {
      throw new HttpsError("invalid-argument", validation.message);
    }
    const { reportedUid, reason, details } = validation.payload;

    const db = getFirestore();
    const reportsRef = db.collection("reports");

    // ── Duplicate pending report vs. the same user ──────────────────────
    const existing = await reportsRef
      .where("reporter_uid", "==", uid)
      .where("reported_uid", "==", reportedUid)
      .where("status", "==", "pending")
      .limit(1)
      .get();
    if (!existing.empty) {
      throw new HttpsError(
        "already-exists",
        "You already reported this user. Our team will review it.",
      );
    }

    // ── Daily cap (5 per UTC day, server clock) ─────────────────────────
    const todayCount = await reportsRef
      .where("reporter_uid", "==", uid)
      .where("created_at", ">=", startOfDayUtc(new Date()))
      .get();
    if (todayCount.size >= MAX_DAILY_REPORTS) {
      throw new HttpsError(
        "resource-exhausted",
        "You've reached the daily report limit. Please try again tomorrow.",
      );
    }

    // ── Write (Admin SDK bypasses the client rules) ─────────────────────
    const docRef = await reportsRef.add({
      reporter_uid: uid,
      reported_uid: reportedUid,
      content_type: "user",
      content_id: reportedUid,
      reason,
      details,
      status: "pending",
      created_at: FieldValue.serverTimestamp(),
    });

    logger.info(
      `User ${uid} reported user ${reportedUid} (report ${docRef.id})`,
    );
    return { success: true, reportId: docRef.id };
  },
);
