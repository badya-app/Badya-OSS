/**
 * Tests for the exportUserData Cloud Function helpers.
 *
 * The callable itself requires the Firestore/Storage emulator / Admin SDK to
 * exercise end-to-end, so these tests focus on the pure helpers that drive
 * the export logic (JSON sanitization, filename generation, payload
 * assembly).
 */

import { Timestamp, GeoPoint } from "firebase-admin/firestore";
import {
  sanitizeForJson,
  makeExportFilename,
  buildExportBundle,
  EXPORT_SCHEMA_VERSION,
} from "../src/export-user-data";

describe("exportUserData helpers", () => {
  describe("sanitizeForJson", () => {
    test("passes primitives through unchanged", () => {
      expect(sanitizeForJson("text")).toBe("text");
      expect(sanitizeForJson(42)).toBe(42);
      expect(sanitizeForJson(true)).toBe(true);
      expect(sanitizeForJson(null)).toBeNull();
      expect(sanitizeForJson(undefined)).toBeUndefined();
    });

    test("converts Firestore Timestamps to ISO strings", () => {
      const ts = Timestamp.fromDate(new Date("2026-08-12T10:00:00Z"));
      expect(sanitizeForJson(ts)).toBe("2026-08-12T10:00:00.000Z");
    });

    test("converts GeoPoints to {latitude, longitude}", () => {
      const gp = new GeoPoint(30.0444, 31.2357);
      expect(sanitizeForJson(gp)).toEqual({
        latitude: 30.0444,
        longitude: 31.2357,
      });
    });

    test("converts DocumentReference-shaped values to their path", () => {
      const fakeRef = {
        path: "users/u1",
        id: "u1",
        parent: {},
        firestore: {},
      };
      expect(sanitizeForJson(fakeRef)).toBe("users/u1");
    });

    test("converts Date objects to ISO strings", () => {
      expect(sanitizeForJson(new Date("2026-01-02T03:04:05Z"))).toBe(
        "2026-01-02T03:04:05.000Z",
      );
    });

    test("recursively converts nested structures", () => {
      const nested = {
        name: "test",
        createdAt: Timestamp.fromDate(new Date("2026-08-12T10:00:00Z")),
        tags: ["a", "b"],
        scores: { listening: 100 },
        location: new GeoPoint(1, 2),
        nullField: null,
      };
      expect(sanitizeForJson(nested)).toEqual({
        name: "test",
        createdAt: "2026-08-12T10:00:00.000Z",
        tags: ["a", "b"],
        scores: { listening: 100 },
        location: { latitude: 1, longitude: 2 },
        nullField: null,
      });
    });

    test("leaves plain objects untouched", () => {
      const plain = { a: { b: [1, 2, { c: "d" }] } };
      expect(sanitizeForJson(plain)).toEqual(plain);
    });
  });

  describe("makeExportFilename", () => {
    test("produces a deterministic UTC filename", () => {
      const date = new Date("2026-08-12T14:15:30Z");
      expect(makeExportFilename(date)).toBe("badya-export-20260812-141530.json");
    });

    test("zero-pads months, days, hours, minutes, seconds", () => {
      const date = new Date("2026-01-05T00:00:05Z");
      expect(makeExportFilename(date)).toBe("badya-export-20260105-000005.json");
    });
  });

  describe("buildExportBundle", () => {
    test("assembles the top-level export structure", () => {
      const bundle = buildExportBundle("u1", {
        userData: { display_name: "Test" },
        userSubcollections: {
          progress: [{ _id: "p1", data: { xp: 10 }, subcollections: {} }],
        },
        userContent: [{ _id: "c1", data: { title: "A" }, subcollections: {} }],
        forkEvents: [{ user_id: "u1" }],
        recommendationClicks: [],
        usernameEntries: [],
        userEmbeddings: null,
        userSimilarity: { u2: 0.5 },
        storageFiles: ["gs://bucket/profile_photos/a.jpg"],
      });

      expect(bundle.app).toBe("Badya");
      expect(bundle.schema_version).toBe(EXPORT_SCHEMA_VERSION);
      expect(bundle.user).toEqual({ uid: "u1", data: { display_name: "Test" } });
      expect(bundle.user_subcollections.progress).toHaveLength(1);
      expect(bundle.user_content).toHaveLength(1);
      expect(bundle.fork_events).toEqual([{ user_id: "u1" }]);
      expect(bundle.recommendation_clicks).toEqual([]);
      expect(bundle.usernames).toEqual([]);
      expect(bundle.user_embeddings).toBeNull();
      expect(bundle.user_similarity).toEqual({ u2: 0.5 });
      expect(bundle.storage_files).toEqual([
        "gs://bucket/profile_photos/a.jpg",
      ]);
      expect(typeof bundle.exported_at).toBe("string");
    });

    test("produces JSON-serializable output", () => {
      const bundle = buildExportBundle("u1", {
        userData: null,
        userSubcollections: {},
        userContent: [],
        forkEvents: [],
        recommendationClicks: [],
        usernameEntries: [],
        userEmbeddings: null,
        userSimilarity: null,
        storageFiles: [],
      });

      const json = JSON.stringify(bundle);
      expect(() => JSON.parse(json)).not.toThrow();
      expect(JSON.parse(json).user.uid).toBe("u1");
    });
  });
});
