/**
 * Cloud Function: Export the current user's data (GDPR Article 20 — right to
 * portability).
 *
 * Invoked from the Flutter app's Profile → Privacy & Security → "Export My
 * Data". Returns a short-lived signed download URL for a JSON file containing
 * EVERY server-side trace of the user, mirroring the data map used by
 * `deleteUserAccount` (right to erasure):
 *
 *  - users/{uid} document + all subcollections (progress, topics, weak_words,
 *    custom_topics, sections, analysis_history, import_sections, imports +
 *    nested lessons, issue_reports, preferences, fcmTokens, daily_activity,
 *    strange_words, transactions) — walked recursively, so nested data is
 *    never missed
 *  - user_content docs owned by the user (+ source/segments/progress
 *    subcollections)
 *  - usernames registry entries, fork_events, recommendation_clicks
 *    (filtered to rows that reference this uid)
 *  - user_embeddings/{uid}, user_similarity/{uid} (recommendation system)
 *  - A list of the user's Cloud Storage files (profile photo, content
 *    thumbnails, inline import images) referenced by their data
 *
 * The caller can only ever export their OWN data — the target uid is taken
 * from the verified ID token, never from request data.
 *
 * The Admin SDK bypasses client security rules, which is the only reliable
 * way to read collections with no client-side read rules (`usernames`,
 * `fork_events`, `recommendation_clicks`, `user_embeddings`,
 * `user_similarity`).
 *
 * Delivery: the JSON is written to `exports/{uid}/` in Cloud Storage and a
 * 15-minute signed download URL is returned. This keeps the callable
 * response tiny regardless of export size (callable payloads are size
 * limited) and gives the user a direct download link. Stale exports for the
 * same user are removed first so each user holds at most one export file.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import {
  getFirestore,
  Firestore,
  DocumentReference,
  CollectionReference,
  QueryDocumentSnapshot,
} from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { Bucket } from "@google-cloud/storage";
import * as logger from "firebase-functions/logger";
import { createRateLimiter } from "./rate-limiter";
import { extractStorageUrls } from "./delete-user-account";

/** Version of the export payload schema (bump on breaking structure changes). */
export const EXPORT_SCHEMA_VERSION = 1;

/** Storage folder prefix for exports: `exports/{uid}/{filename}`. */
export const EXPORT_STORAGE_DIR = "exports";

/** Signed download URLs expire after 15 minutes. */
export const SIGNED_URL_TTL_MS = 15 * 60 * 1000;

/** Page size for draining large collections. */
const EXPORT_BATCH_SIZE = 500;

/** Abuse control: at most 5 exports per user per 10 minutes (per instance). */
const exportRateLimiter = createRateLimiter(5, 10 * 60 * 1000);

/** One user document (or subcollection doc) with its nested subcollections. */
export interface RecursiveDoc {
  _id: string;
  data: Record<string, unknown>;
  subcollections: Record<string, RecursiveDoc[]>;
}

/** Top-level structure of the exported JSON payload. */
export interface ExportBundle {
  app: string;
  schema_version: number;
  exported_at: string;
  user: { uid: string; data: Record<string, unknown> | null };
  user_subcollections: Record<string, unknown[]>;
  user_content: unknown[];
  fork_events: unknown[];
  recommendation_clicks: unknown[];
  usernames: unknown[];
  user_embeddings: Record<string, unknown> | null;
  user_similarity: Record<string, unknown> | null;
  storage_files: string[];
}

/** The pieces `buildExportBundle` assembles (kept separate for testability). */
export interface ExportParts {
  userData: Record<string, unknown> | null;
  userSubcollections: Record<string, unknown[]>;
  userContent: unknown[];
  forkEvents: unknown[];
  recommendationClicks: unknown[];
  usernameEntries: unknown[];
  userEmbeddings: Record<string, unknown> | null;
  userSimilarity: Record<string, unknown> | null;
  storageFiles: string[];
}

// ---------------------------------------------------------------------------
// Pure helpers (unit-tested)
// ---------------------------------------------------------------------------

/**
 * Recursively convert Firestore values into JSON-safe primitives so the
 * export is a plain, human-readable JSON document:
 *  - Timestamp / Date  → ISO 8601 string
 *  - DocumentReference → its path (e.g. "users/u1")
 *  - GeoPoint          → { latitude, longitude }
 *  - arrays / objects  → converted recursively
 */
export function sanitizeForJson(value: unknown): unknown {
  if (value === null || value === undefined) return value;
  if (
    typeof value === "string" ||
    typeof value === "number" ||
    typeof value === "boolean"
  ) {
    return value;
  }
  if (value instanceof Date) return value.toISOString();

  const candidate = value as Record<string, unknown>;

  // Firestore Timestamp — duck-typed via toDate() so we stay decoupled from
  // the exact class coming from google-cloud/firestore.
  if (typeof candidate.toDate === "function") {
    const date = (candidate.toDate as () => Date)();
    if (date instanceof Date) return date.toISOString();
  }

  // Firestore GeoPoint → { latitude, longitude }
  if (
    typeof candidate.latitude === "number" &&
    typeof candidate.longitude === "number"
  ) {
    return { latitude: candidate.latitude, longitude: candidate.longitude };
  }

  // Firestore DocumentReference → its path (e.g. "users/u1")
  if (
    typeof candidate.path === "string" &&
    typeof candidate.id === "string" &&
    typeof candidate.parent === "object" &&
    typeof candidate.firestore === "object"
  ) {
    return candidate.path;
  }

  if (Array.isArray(value)) {
    return value.map((item) => sanitizeForJson(item));
  }

  if (typeof value === "object") {
    const out: Record<string, unknown> = {};
    for (const [key, item] of Object.entries(candidate)) {
      out[key] = sanitizeForJson(item);
    }
    return out;
  }

  return value;
}

/**
 * Deterministic export filename, e.g. `badya-export-20260812-141530.json`
 * (UTC). Used as the Storage object name and the download's filename.
 */
export function makeExportFilename(date: Date): string {
  const pad = (n: number) => String(n).padStart(2, "0");
  const y = date.getUTCFullYear();
  const mo = pad(date.getUTCMonth() + 1);
  const d = pad(date.getUTCDate());
  const h = pad(date.getUTCHours());
  const mi = pad(date.getUTCMinutes());
  const s = pad(date.getUTCSeconds());
  return `badya-export-${y}${mo}${d}-${h}${mi}${s}.json`;
}

/** Assemble the top-level export payload from the collected parts. */
export function buildExportBundle(uid: string, parts: ExportParts): ExportBundle {
  return {
    app: "Badya",
    schema_version: EXPORT_SCHEMA_VERSION,
    exported_at: new Date().toISOString(),
    user: { uid, data: parts.userData },
    user_subcollections: parts.userSubcollections,
    user_content: parts.userContent,
    fork_events: parts.forkEvents,
    recommendation_clicks: parts.recommendationClicks,
    usernames: parts.usernameEntries,
    user_embeddings: parts.userEmbeddings,
    user_similarity: parts.userSimilarity,
    storage_files: parts.storageFiles,
  };
}

// ---------------------------------------------------------------------------
// Firestore walkers
// ---------------------------------------------------------------------------

/**
 * Read a document and, recursively, every subcollection below it.
 * Returns null when the document doesn't exist.
 */
async function readDocRecursively(
  docRef: DocumentReference,
): Promise<Omit<RecursiveDoc, "_id"> | null> {
  const snap = await docRef.get();
  if (!snap.exists) return null;

  const data = sanitizeForJson(snap.data() ?? {}) as Record<string, unknown>;
  const subcollections: Record<string, RecursiveDoc[]> = {};
  const collections = await docRef.listCollections();
  for (const sub of collections) {
    subcollections[sub.id] = await readCollectionRecursively(sub);
  }
  return { data, subcollections };
}

/** Read every document in a collection, each with its nested subcollections. */
async function readCollectionRecursively(
  collectionRef: CollectionReference,
): Promise<RecursiveDoc[]> {
  const snapshot = await collectionRef.get();
  const out: RecursiveDoc[] = [];
  for (const doc of snapshot.docs) {
    const docData = await readDocRecursively(doc.ref);
    if (docData) {
      out.push({ _id: doc.id, ...docData });
    }
  }
  return out;
}

/**
 * Read all documents in a collection matching a single-field equality filter
 * (e.g. fork_events where user_id == uid). Drains paginated batches so
 * accounts with more than one batch of rows are fully exported.
 */
async function readDocsWhere(
  db: Firestore,
  collectionPath: string,
  field: string,
  value: string,
): Promise<unknown[]> {
  const out: unknown[] = [];
  let lastDoc: QueryDocumentSnapshot | null = null;
  for (;;) {
    let query = db
      .collection(collectionPath)
      .where(field, "==", value)
      .limit(EXPORT_BATCH_SIZE);
    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }
    const snapshot = await query.get();
    if (snapshot.empty) break;
    for (const doc of snapshot.docs) {
      out.push(sanitizeForJson(doc.data()));
    }
    lastDoc = snapshot.docs[snapshot.docs.length - 1];
  }
  return out;
}

// ---------------------------------------------------------------------------
// Storage helpers
// ---------------------------------------------------------------------------

/**
 * Delete every previous export for this user (keeps at most one export file
 * per user). Best-effort — failures are logged, never thrown.
 *
 * [keepPath] (the file just written) is skipped so a failed save never leaves
 * the user without their previous export.
 */
async function deleteStaleExports(
  bucket: Bucket,
  uid: string,
  keepPath?: string,
): Promise<void> {
  const [files] = await bucket.getFiles({
    prefix: `${EXPORT_STORAGE_DIR}/${uid}/`,
  });
  await Promise.all(
    files
      .filter((file) => file.name !== keepPath)
      .map((file) =>
        file.delete().catch((e: unknown) => {
          logger.warn(`Failed to delete stale export ${file.name}: ${e}`);
        }),
      ),
  );
}

// ---------------------------------------------------------------------------
// Data collection
// ---------------------------------------------------------------------------

/**
 * Collect every server-side trace of the user into an export bundle.
 * Mirrors the data map in `deleteUserAccount` (right to erasure) so both
 * GDPR flows stay in sync.
 */
export async function collectUserData(
  db: Firestore,
  uid: string,
): Promise<ExportBundle> {
  const userRef = db.collection("users").doc(uid);
  const storageUrls: string[] = [];

  // ── 1. User document + ALL subcollections ────────────────────────────
  const userDoc = await readDocRecursively(userRef);
  const userData = userDoc?.data ?? null;
  const userSubcollections = userDoc?.subcollections ?? {};

  if (typeof userData?.photo_url === "string") {
    storageUrls.push(userData.photo_url);
  }

  // ── 2. Owned user_content (+ source/segments/progress) ───────────────
  const userContent: unknown[] = [];
  let lastContentDoc: QueryDocumentSnapshot | null = null;
  for (;;) {
    let query = db
      .collection("user_content")
      .where("user_id", "==", uid)
      .limit(EXPORT_BATCH_SIZE);
    if (lastContentDoc) {
      query = query.startAfter(lastContentDoc);
    }
    const contentSnapshot = await query.get();
    if (contentSnapshot.empty) break;

    for (const doc of contentSnapshot.docs) {
      const entry = await readDocRecursively(doc.ref);
      if (!entry) continue;
      userContent.push({ _id: doc.id, ...entry });

      // Thumbnail URL from metadata.
      const metadata = entry.data.metadata;
      if (metadata !== null && typeof metadata === "object") {
        const thumbnail = (metadata as Record<string, unknown>).thumbnail_url;
        if (typeof thumbnail === "string") storageUrls.push(thumbnail);
      }

      // Inline storage images embedded in the raw source content.
      const rawEntry = entry.subcollections.source?.find(
        (sub) => sub._id === "raw",
      );
      const rawContent = rawEntry?.data.content;
      if (typeof rawContent === "string") {
        storageUrls.push(...extractStorageUrls(rawContent));
      }
    }
    lastContentDoc = contentSnapshot.docs[contentSnapshot.docs.length - 1];
  }

  // ── 3. Shared collections referencing this user ──────────────────────
  const forkEvents = await readDocsWhere(db, "fork_events", "user_id", uid);
  const recommendationClicks = await readDocsWhere(
    db,
    "recommendation_clicks",
    "user_id",
    uid,
  );
  const usernameEntries = await readDocsWhere(db, "usernames", "uid", uid);

  // ── 4. Recommendation system documents ───────────────────────────────
  const embeddingsSnap = await db.collection("user_embeddings").doc(uid).get();
  const userEmbeddings = embeddingsSnap.exists
    ? (sanitizeForJson(embeddingsSnap.data()) as Record<string, unknown>)
    : null;

  const similaritySnap = await db.collection("user_similarity").doc(uid).get();
  const userSimilarity = similaritySnap.exists
    ? (sanitizeForJson(similaritySnap.data()) as Record<string, unknown>)
    : null;

  return buildExportBundle(uid, {
    userData,
    userSubcollections,
    userContent,
    forkEvents,
    recommendationClicks,
    usernameEntries,
    userEmbeddings,
    userSimilarity,
    storageFiles: storageUrls,
  });
}

// ---------------------------------------------------------------------------
// Callable function
// ---------------------------------------------------------------------------

export const exportUserData = onCall(
  { cors: true, maxInstances: 32, timeoutSeconds: 300 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "You must be signed in to export your data.",
      );
    }

    const uid = request.auth.uid;
    if (!exportRateLimiter.allow(uid)) {
      throw new HttpsError(
        "resource-exhausted",
        "Too many export requests. Please wait a few minutes and try again.",
      );
    }

    const db = getFirestore();
    const bucket = getStorage().bucket();
    logger.info(`Generating GDPR data export for user ${uid}`);

    // ⚠️ Large accounts: the whole bundle is materialized in memory and
    // stringified here. Accounts with very heavy imports may need a higher
    // function memory limit; exports for typical users are a few MB at most.
    const bundle = await collectUserData(db, uid);
    const json = JSON.stringify(bundle, null, 2);
    const sizeBytes = Buffer.byteLength(json, "utf8");
    const filename = makeExportFilename(new Date());
    const filePath = `${EXPORT_STORAGE_DIR}/${uid}/${filename}`;

    // The export file has no public ACL; access is only via the short-lived
    // signed URL below. ⚠️ NOTE: while `storage.rules` keeps its permissive
    // catch-all (review issue #5 — any authenticated user may read ANY path),
    // this file — like profile photos and thumbnails — is readable by any
    // authenticated user who knows the uid and path (rules are OR'd, so a
    // scoped rule cannot help until the catch-all is fixed). Scope
    // `exports/{uid}/{allPaths=**}` to the owner as part of that fix.
    await bucket.file(filePath).save(json, {
      contentType: "application/json; charset=utf-8",
      metadata: {
        metadata: { uid, purpose: "gdpr-portability" },
      },
    });

    const [downloadUrl] = await bucket.file(filePath).getSignedUrl({
      action: "read",
      expires: Date.now() + SIGNED_URL_TTL_MS,
      responseDisposition: `attachment; filename="${filename}"`,
    });

    // Keep at most one export per user — clean up previous exports AFTER the
    // new one is saved and signed, so a failure above never destroys the
    // user's last export. Note: files persist until the next export; consider
    // a bucket lifecycle rule (e.g. 30-day expiry on exports/) if they should
    // self-expire.
    await deleteStaleExports(bucket, uid, filePath);

    logger.info(
      `Data export ready for user ${uid}: ${filename} (${sizeBytes} bytes)`,
    );

    return {
      downloadUrl,
      filename,
      sizeBytes,
      exportedAt: bundle.exported_at,
      expiresInSeconds: SIGNED_URL_TTL_MS / 1000,
    };
  },
);
