/**
 * Cloud Function: Permanently delete a user's account and ALL associated data.
 *
 * GDPR Article 17 (Right to Erasure) / CCPA requirement. Invoked from the
 * Flutter app after the user confirms account deletion (and reauthenticates).
 *
 * The Admin SDK bypasses client security rules, which is the only reliable way
 * to clean up collections that have no client-side delete rules
 * (`usernames`, `fork_events`, `recommendation_clicks`, `user_embeddings`,
 * `user_similarity`). The caller can only ever delete their OWN account — the
 * target uid is taken from the verified ID token, never from request data.
 *
 * Deletes:
 *  - users/{uid} document + every subcollection (progress, topics, weak_words,
 *    custom_topics, sections, analysis_history, import_sections, imports +
 *    nested lessons, issue_reports, preferences, fcmTokens, daily_activity,
 *    strange_words, transactions)
 *  - user_content docs owned by the user (+ source/segments/progress
 *    subcollections)
 *  - usernames registry entries, fork_events, recommendation_clicks
 *  - user_embeddings/{uid}, user_similarity/{uid} (recommendation system)
 *  - Firebase Storage objects referenced by the user's data (profile photo,
 *    content thumbnails, imported images)
 *  - The Firebase Auth user record (deleted LAST, via Admin SDK)
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import {
  getFirestore,
  Firestore,
  CollectionReference,
  DocumentReference,
  QueryDocumentSnapshot,
} from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { getAuth } from "firebase-admin/auth";
import * as logger from "firebase-functions/logger";

const DELETE_BATCH_SIZE = 500;

// ---------------------------------------------------------------------------
// Pure helpers (unit-testable)
// ---------------------------------------------------------------------------

/**
 * Extract the object path from a Firebase Storage download URL.
 *
 * Example:
 *   "https://firebasestorage.googleapis.com/v0/b/bucket/o/profile_photos%2Fabc.jpg?alt=media"
 *   -> "profile_photos/abc.jpg"
 *
 * Returns null for non-Storage URLs or malformed input.
 */
export function storagePathFromUrl(url: string): string | null {
  try {
    const parsed = new URL(url);
    if (parsed.hostname !== "firebasestorage.googleapis.com") return null;
    const match = parsed.pathname.match(/\/o\/(.+)/);
    if (!match) return null;
    return decodeURIComponent(match[1]);
  } catch {
    return null;
  }
}

/**
 * Find all Firebase Storage download URLs inside arbitrary text.
 * Used to locate images embedded in imported lesson content.
 */
export function extractStorageUrls(text: string): string[] {
  const regex = /https:\/\/firebasestorage\.googleapis\.com\/v0\/b\/[^)\s"'`]+/g;
  return text.match(regex) ?? [];
}

// ---------------------------------------------------------------------------
// Recursive Firestore deletion
// ---------------------------------------------------------------------------

/**
 * Delete a document AND all of its subcollections (any depth).
 * Firestore does not cascade subcollection deletes, so nested structures like
 * users/{uid}/imports/{id}/lessons/{id} must be walked manually.
 */
async function deleteDocumentAndSubcollections(
  db: Firestore,
  docRef: DocumentReference,
): Promise<void> {
  const subCollections = await docRef.listCollections();
  for (const sub of subCollections) {
    await deleteCollectionRecursively(db, sub);
  }
  await docRef.delete();
}

/**
 * Delete every document in a collection, recursing into each document's
 * subcollections first. Loops until the collection is empty.
 */
async function deleteCollectionRecursively(
  db: Firestore,
  collectionRef: CollectionReference,
): Promise<void> {
  const snapshot = await collectionRef.limit(DELETE_BATCH_SIZE).get();
  if (snapshot.empty) return;

  for (const doc of snapshot.docs) {
    await deleteDocumentAndSubcollections(db, doc.ref);
  }

  // More docs may remain (exceeded batch size) — keep draining.
  await deleteCollectionRecursively(db, collectionRef);
}

/**
 * Delete all documents in a collection matching a single-field equality
 * filter (e.g. fork_events where user_id == uid), recursing into each
 * document's subcollections first. Drains until the query is empty.
 */
async function deleteDocsWhereRecursively(
  db: Firestore,
  collectionPath: string,
  field: string,
  value: string,
): Promise<void> {
  const snapshot = await db
    .collection(collectionPath)
    .where(field, "==", value)
    .limit(DELETE_BATCH_SIZE)
    .get();
  if (snapshot.empty) return;

  for (const doc of snapshot.docs) {
    await deleteDocumentAndSubcollections(db, doc.ref);
  }

  await deleteDocsWhereRecursively(db, collectionPath, field, value);
}

// ---------------------------------------------------------------------------
// Storage deletion
// ---------------------------------------------------------------------------

/**
 * Best-effort deletion of storage objects by URL. Failures are logged and
 * never thrown — orphaned files are preferable to a failed account deletion.
 */
async function deleteStorageObjects(urls: string[]): Promise<void> {
  const bucket = getStorage().bucket();
  const objectPaths = new Set<string>();

  for (const url of urls) {
    const path = storagePathFromUrl(url);
    if (path) objectPaths.add(path);
  }

  for (const path of objectPaths) {
    try {
      await bucket.file(path).delete();
      logger.info(`Deleted storage object: ${path}`);
    } catch (e) {
      // Object may already be gone — not worth failing the whole deletion.
      logger.warn(`Failed to delete storage object ${path}: ${e}`);
    }
  }
}

// ---------------------------------------------------------------------------
// Callable function
// ---------------------------------------------------------------------------

export const deleteUserAccount = onCall(
  { cors: true, maxInstances: 32, timeoutSeconds: 300 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "You must be signed in to delete your account.",
      );
    }

    const uid = request.auth.uid;
    const db = getFirestore();
    const userRef = db.collection("users").doc(uid);

    logger.info(`Starting account deletion for user ${uid}`);

    // ── 1. Collect storage URLs BEFORE deleting any data ──────────────
    const storageUrls: string[] = [];
    let username: string | null = null;

    try {
      const userDoc = await userRef.get();
      if (userDoc.exists) {
        const data = userDoc.data() ?? {};
        if (typeof data.photo_url === "string") {
          storageUrls.push(data.photo_url);
        }
        if (typeof data.username === "string") {
          username = data.username;
        }
      }
    } catch (e) {
      logger.warn(`Could not read user doc ${uid}: ${e}`);
    }

    // Owned content → thumbnail URLs + images embedded in source text.
    // Drains ALL owned content in batches (not just the first batch) so no
    // storage files are orphaned for accounts with >500 content items.
    try {
      let lastDoc: QueryDocumentSnapshot | null = null;
      for (;;) {
        let query = db
          .collection("user_content")
          .where("user_id", "==", uid)
          .limit(DELETE_BATCH_SIZE);
        if (lastDoc) {
          query = query.startAfter(lastDoc);
        }
        const contentSnapshot = await query.get();
        if (contentSnapshot.empty) break;

        for (const doc of contentSnapshot.docs) {
          const data = doc.data();
          const thumbnail = data.metadata?.thumbnail_url;
          if (typeof thumbnail === "string") {
            storageUrls.push(thumbnail);
          }

          // Scan the content's source/raw doc for inline storage images.
          const sourceSnap = await doc.ref
            .collection("source")
            .doc("raw")
            .get();
          if (sourceSnap.exists) {
            const raw = sourceSnap.data() ?? {};
            const content = raw.content;
            if (typeof content === "string") {
              storageUrls.push(...extractStorageUrls(content));
            }
          }
        }

        lastDoc = contentSnapshot.docs[contentSnapshot.docs.length - 1];
      }
    } catch (e) {
      logger.warn(`Could not collect storage URLs for ${uid}: ${e}`);
    }

    // ── 2. Delete the user document + ALL subcollections ───────────────
    await deleteDocumentAndSubcollections(db, userRef);

    // ── 3. Delete owned user_content (+ subcollections) ────────────────
    // Note: owned public content that OTHER users forked (via
    // canonical_content_id) will break for them once deleted. GDPR requires
    // the deletion, so this is a deliberate tradeoff.
    await deleteDocsWhereRecursively(db, "user_content", "user_id", uid);

    // ── 4. Username registry, analytics, recommendation system ─────────
    if (username) {
      try {
        await db.collection("usernames").doc(username).delete();
      } catch (e) {
        logger.warn(`Could not delete usernames/${username}: ${e}`);
      }
    }
    try {
      await deleteDocsWhereRecursively(db, "usernames", "uid", uid);
      await deleteDocsWhereRecursively(db, "fork_events", "user_id", uid);
      await deleteDocsWhereRecursively(db, "recommendation_clicks", "user_id", uid);
    } catch (e) {
      logger.warn(`Could not delete analytics rows for ${uid}: ${e}`);
    }
    try {
      await db.collection("user_embeddings").doc(uid).delete();
      await db.collection("user_similarity").doc(uid).delete();
    } catch (e) {
      logger.warn(`Could not delete recommendation docs for ${uid}: ${e}`);
    }

    // ── 5. Storage files (best-effort) ─────────────────────────────────
    await deleteStorageObjects(storageUrls);

    // ── 6. Delete the Firebase Auth user LAST ──────────────────────────
    try {
      await getAuth().deleteUser(uid);
      logger.info(`Account deletion complete for user ${uid}`);
    } catch (e) {
      // Data is gone; surface a clear error if only the auth record failed.
      logger.error(`Failed to delete auth user ${uid}: ${e}`);
      throw new HttpsError(
        "internal",
        "Your data was deleted, but removing the authentication record failed. Please contact badyaapp@gmail.com for help.",
      );
    }

    return { success: true };
  },
);
