/**
 * Tests for the deleteUserAccount Cloud Function helpers.
 *
 * The callable itself requires the Firestore emulator / Admin SDK to exercise
 * end-to-end, so these tests focus on the pure helper functions that drive
 * the deletion logic (URL parsing and storage URL extraction).
 */

import {
  storagePathFromUrl,
  extractStorageUrls,
} from "../src/delete-user-account";

describe("deleteUserAccount helpers", () => {
  describe("storagePathFromUrl", () => {
    test("extracts a decoded object path from a standard download URL", () => {
      const url =
        "https://firebasestorage.googleapis.com/v0/b/badya-f1af2.appspot.com/o/profile_photos%2Fabc-123.jpg?alt=media&token=xyz";
      expect(storagePathFromUrl(url)).toBe("profile_photos/abc-123.jpg");
    });

    test("handles nested paths with multiple segments", () => {
      const url =
        "https://firebasestorage.googleapis.com/v0/b/bucket/o/users%2Fu1%2Fcontent%2Fthumb.jpg?alt=media";
      expect(storagePathFromUrl(url)).toBe("users/u1/content/thumb.jpg");
    });

    test("returns null for non-firebase storage hosts", () => {
      expect(storagePathFromUrl("https://example.com/o/file.jpg")).toBeNull();
    });

    test("returns null for malformed input", () => {
      expect(storagePathFromUrl("not-a-url")).toBeNull();
      expect(storagePathFromUrl("")).toBeNull();
      expect(storagePathFromUrl("https://firebasestorage.googleapis.com")).toBeNull();
    });
  });

  describe("extractStorageUrls", () => {
    test("finds all storage URLs embedded in text", () => {
      const text =
        "Lesson text with ![img1](https://firebasestorage.googleapis.com/v0/b/bucket/o/imports%2Fa.png?alt=media) " +
        "and ![img2](https://firebasestorage.googleapis.com/v0/b/bucket/o/imports%2Fb.png?alt=media&token=t) done.";
      const urls = extractStorageUrls(text);
      expect(urls).toHaveLength(2);
      expect(urls[0]).toContain("imports%2Fa.png");
      expect(urls[1]).toContain("imports%2Fb.png");
    });

    test("returns empty array when no storage URLs present", () => {
      expect(extractStorageUrls("plain text without images")).toEqual([]);
      expect(extractStorageUrls("")).toEqual([]);
    });

    test("ignores non-storage https URLs", () => {
      const text = "See https://example.com/image.png and https://other.org/x";
      expect(extractStorageUrls(text)).toEqual([]);
    });
  });
});
