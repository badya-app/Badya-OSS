/**
 * Tests for the submitReport Cloud Function helpers.
 *
 * The callable itself requires the Firestore emulator / Admin SDK to exercise
 * end-to-end, so these tests focus on the pure helpers that drive its
 * enforcement logic (payload validation and the server-clock day boundary).
 */

import {
  validateReportPayload,
  startOfDayUtc,
  REPORT_REASONS,
  MAX_DAILY_REPORTS,
  MAX_DETAILS_LENGTH,
  MAX_REPORTED_UID_LENGTH,
} from "../src/submit-report";

describe("submitReport helpers", () => {
  describe("validateReportPayload", () => {
    test("accepts a valid payload", () => {
      const result = validateReportPayload(
        { reportedUid: "them", reason: "violence", details: "  bad content  " },
        "me",
      );
      expect(result.ok).toBe(true);
      if (!result.ok) return;
      expect(result.payload.reportedUid).toBe("them");
      expect(result.payload.reason).toBe("violence");
      expect(result.payload.details).toBe("bad content");
    });

    test("details is optional and defaults to empty string", () => {
      const result = validateReportPayload(
        { reportedUid: "them", reason: "spam" },
        "me",
      );
      expect(result.ok).toBe(true);
      if (!result.ok) return;
      expect(result.payload.details).toBe("");
    });

    test("rejects missing or non-string reportedUid", () => {
      expect(validateReportPayload({}, "me").ok).toBe(false);
      expect(validateReportPayload({ reportedUid: "" }, "me").ok).toBe(false);
      expect(validateReportPayload({ reportedUid: 42 }, "me").ok).toBe(false);
      expect(validateReportPayload({ reportedUid: "   " }, "me").ok).toBe(false);
    });

    test("rejects self-reports", () => {
      const result = validateReportPayload(
        { reportedUid: "me", reason: "spam" },
        "me",
      );
      expect(result.ok).toBe(false);
    });

    test("rejects whitespace-padded self-reports", () => {
      // The stored value is trimmed, so a padded self-report must not
      // slip past the guard.
      const result = validateReportPayload(
        { reportedUid: "  me ", reason: "spam" },
        "me",
      );
      expect(result.ok).toBe(false);
    });

    test("rejects an over-long reportedUid", () => {
      const tooLong = validateReportPayload(
        {
          reportedUid: "x".repeat(MAX_REPORTED_UID_LENGTH + 1),
          reason: "spam",
        },
        "me",
      );
      expect(tooLong.ok).toBe(false);

      const atCap = validateReportPayload(
        {
          reportedUid: "x".repeat(MAX_REPORTED_UID_LENGTH),
          reason: "spam",
        },
        "me",
      );
      expect(atCap.ok).toBe(true);
    });

    test("rejects a reason outside the allowlist", () => {
      const result = validateReportPayload(
        { reportedUid: "them", reason: "not-a-reason" },
        "me",
      );
      expect(result.ok).toBe(false);
    });

    test("rejects non-string details", () => {
      const result = validateReportPayload(
        { reportedUid: "them", reason: "spam", details: 123 },
        "me",
      );
      expect(result.ok).toBe(false);
    });

    test("rejects details over the length cap, accepts exactly at the cap", () => {
      const tooLong = validateReportPayload(
        {
          reportedUid: "them",
          reason: "spam",
          details: "x".repeat(MAX_DETAILS_LENGTH + 1),
        },
        "me",
      );
      expect(tooLong.ok).toBe(false);

      const atCap = validateReportPayload(
        {
          reportedUid: "them",
          reason: "spam",
          details: "x".repeat(MAX_DETAILS_LENGTH),
        },
        "me",
      );
      expect(atCap.ok).toBe(true);
    });
  });

  describe("startOfDayUtc", () => {
    test("returns UTC midnight of the same calendar day", () => {
      const day = startOfDayUtc(new Date("2026-08-17T15:30:00Z"));
      expect(day.toISOString()).toBe("2026-08-17T00:00:00.000Z");
    });

    test("handles the last instant of a day", () => {
      const day = startOfDayUtc(new Date("2026-08-17T23:59:59.999Z"));
      expect(day.toISOString()).toBe("2026-08-17T00:00:00.000Z");
    });

    test("handles a leap day", () => {
      const day = startOfDayUtc(new Date("2028-02-29T06:00:00Z"));
      expect(day.toISOString()).toBe("2028-02-29T00:00:00.000Z");
    });
  });

  describe("constants", () => {
    test("allowlist matches the client ReportReason values and the rule list", () => {
      expect(REPORT_REASONS).toEqual([
        "violence",
        "sexual_content",
        "hate_speech",
        "harassment",
        "spam",
        "impersonation",
        "other",
      ]);
    });

    test("daily cap matches the client-side guard", () => {
      expect(MAX_DAILY_REPORTS).toBe(5);
    });
  });
});
