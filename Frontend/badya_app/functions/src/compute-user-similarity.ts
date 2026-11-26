/**
 * Cloud Function: Pre-Computed User Similarity Matrix
 *
 * Scheduled to run daily at 2:00 AM UTC.
 * Implements v2 embedding-based User-User Collaborative Filtering (see
 * docs/recommendation_system/02_SCORING_ALGORITHM.md §6).
 *
 * Algorithm:
 *   1. Fetch all user embeddings from `user_embeddings` collection
 *   2. For each user, find top-20 most similar users by cosine similarity
 *   3. For each similar user, fetch their forked canonical content (up to 20 items)
 *   4. Aggregate scores: for each piece of canonical content, sum the similarity
 *      scores of users who forked it
 *   5. Normalize to [0, 1] by dividing by the max score
 *   6. Store as `user_similarity/{user_id}` document
 *
 * Benefit: Reduces recommendation request CF computation from ~21 queries
 * to a single document read.
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import { onCall } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/** Number of top-similar users to consider per user. */
const TOP_SIMILAR_USERS = 20;

/** Max forked content items to fetch per similar user. */
const MAX_FORKS_PER_USER = 20;

/** Minimum number of users required to compute meaningful similarities. */
const MIN_USERS_FOR_SIMILARITY = 2;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Compute cosine similarity between two embedding vectors.
 * Returns a value in [0, 1] (normalized embeddings assumed).
 */
function cosineSimilarity(a: number[], b: number[]): number {
  if (a.length !== b.length || a.length === 0) return 0;
  let dot = 0;
  let normA = 0;
  let normB = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  if (normA === 0 || normB === 0) return 0;
  return dot / (Math.sqrt(normA) * Math.sqrt(normB));
}

/**
 * Round a number to 4 decimal places for storage.
 */
function round4(n: number): number {
  return Math.round(n * 10000) / 10000;
}

// ---------------------------------------------------------------------------
// Interfaces
// ---------------------------------------------------------------------------

interface UserEmbedding {
  userId: string;
  embedding: number[];
}

// ---------------------------------------------------------------------------
// Shared core: compute similarity for all users and write to Firestore
// ---------------------------------------------------------------------------

interface ComputeResult {
  processedCount: number;
  failedUsers: string[];
  totalUsers: number;
}

/**
 * Core logic for the user similarity matrix computation.
 * Shared between the scheduled function and the on-demand callable.
 *
 * Fetches all user embeddings, computes embedding-based user-user CF,
 * and writes results to user_similarity/{user_id} for each user.
 */
async function computeSimilarityMatrix(db: FirebaseFirestore.Firestore): Promise<ComputeResult> {
  // 1. Fetch ALL user embeddings
  const embeddingsSnapshot = await db.collection("user_embeddings").get();
  const userEmbeddings: UserEmbedding[] = [];

  embeddingsSnapshot.forEach((doc) => {
    const data = doc.data();
    const embedding = data.embedding as number[] | undefined;
    if (embedding && embedding.length > 0) {
      userEmbeddings.push({ userId: doc.id, embedding });
    }
  });

  const totalUsers = userEmbeddings.length;
  logger.info(`Found ${totalUsers} users with embeddings`);

  if (totalUsers < MIN_USERS_FOR_SIMILARITY) {
    return { processedCount: 0, failedUsers: [], totalUsers };
  }

  // 2. For each user, compute top-N similar users + aggregate CF scores
  let processedCount = 0;
  const failedUsers: string[] = [];

  for (const user of userEmbeddings) {
    try {
      // 2a. Compute similarity against all other users
      const similarities: Array<{ userId: string; similarity: number }> = [];

      for (const other of userEmbeddings) {
        if (other.userId === user.userId) continue;
        const sim = cosineSimilarity(user.embedding, other.embedding);
        if (sim > 0) {
          similarities.push({ userId: other.userId, similarity: sim });
        }
      }

      // 2b. Sort descending, keep top-N
      similarities.sort((a, b) => b.similarity - a.similarity);
      const topSimilarUsers = similarities.slice(0, TOP_SIMILAR_USERS);

      // 2c. For each similar user, fetch their forked canonical content
      const rawScores: Record<string, number> = {};

      for (const similar of topSimilarUsers) {
        const userContentSnapshot = await db
          .collection("user_content")
          .where("user_id", "==", similar.userId)
          .limit(MAX_FORKS_PER_USER)
          .get();

        userContentSnapshot.forEach((doc) => {
          const data = doc.data();
          const canonicalId = data.canonical_content_id as string | undefined;
          if (canonicalId) {
            rawScores[canonicalId] =
              (rawScores[canonicalId] ?? 0) + similar.similarity;
          }
        });
      }

      // 2d. Normalize scores to [0, 1]
      const maxScore = Math.max(...Object.values(rawScores), 0);
      const normalizedScores: Record<string, number> = {};
      if (maxScore > 0) {
        for (const [contentId, score] of Object.entries(rawScores)) {
          normalizedScores[contentId] = round4(score / maxScore);
        }
      }

      // 2e. Store pre-computed scores (one doc read = one query at rec request time)
      await db.collection("user_similarity").doc(user.userId).set({
        user_id: user.userId,
        computed_at: Timestamp.now(),
        similar_users: topSimilarUsers.map((u) => ({
          user_id: u.userId,
          similarity: round4(u.similarity),
        })),
        cf_scores: normalizedScores,
        num_users_compared: totalUsers,
        model_version: "embedding_user_cf_v2",
      });
    } catch (err) {
      logger.error(`Failed to compute similarity for user ${user.userId}:`, err);
      failedUsers.push(user.userId);
    }

    processedCount++;
    if (processedCount % 10 === 0) {
      logger.info(`Progress: ${processedCount}/${totalUsers} users processed`);
    }
  }

  return { processedCount, failedUsers, totalUsers };
}

// ---------------------------------------------------------------------------
// Cloud Function: computeUserSimilarity (scheduled, daily at 02:00 UTC)
// ---------------------------------------------------------------------------

export const computeUserSimilarity = onSchedule(
  {
    schedule: "every day 02:00",
    timeZone: "UTC",
    region: "us-central1",
    memory: "512MiB",
    timeoutSeconds: 540,
    maxInstances: 1,
  },
  async () => {
    const db = getFirestore();
    logger.info("Starting scheduled user similarity matrix computation...");

    const { processedCount, failedUsers, totalUsers } = await computeSimilarityMatrix(db);

    if (totalUsers < MIN_USERS_FOR_SIMILARITY) {
      logger.info(
        `Fewer than ${MIN_USERS_FOR_SIMILARITY} users with embeddings — nothing to compute.`,
      );
      return;
    }

    if (failedUsers.length > 0) {
      logger.warn(
        `Completed with ${failedUsers.length} failures. ` +
        `Failed users: ${failedUsers.join(", ")}`,
      );
    } else {
      logger.info(
        "User similarity matrix computation complete. " +
        `Processed ${processedCount}/${totalUsers} users successfully.`,
      );
    }
  },
);

// ---------------------------------------------------------------------------
// Callable Function: triggerUserSimilarity (on-demand via Flutter/curl)
// ---------------------------------------------------------------------------

/**
 * On-demand trigger for the similarity computation.
 * Useful for testing or manual re-computation without waiting for the
 * daily schedule. Requires Firebase Auth.
 */
export const triggerUserSimilarity = onCall(
  {
    region: "us-central1",
    memory: "512MiB",
    timeoutSeconds: 540,
    maxInstances: 1,
  },
  async (request) => {
    if (!request.auth) {
      throw new Error("Authentication required to trigger similarity computation.");
    }

    // Restrict to admin users only (expensive O(n²) operation)
    const db = getFirestore();
    const adminDoc = await db.collection("config").doc("admins").get();
    const adminUids: string[] = adminDoc.exists ? (adminDoc.data()?.uids ?? []) : [];
    if (!adminUids.includes(request.auth.uid)) {
      logger.warn(
        `Non-admin user ${request.auth.uid} attempted to trigger similarity computation.`,
      );
      throw new Error("Only admin users can trigger similarity computation.");
    }

    logger.info(
      `User similarity matrix triggered on-demand by admin ${request.auth.uid}`,
    );
    const { processedCount, failedUsers, totalUsers } = await computeSimilarityMatrix(db);

    if (totalUsers < MIN_USERS_FOR_SIMILARITY) {
      return {
        success: true,
        message: `Fewer than ${MIN_USERS_FOR_SIMILARITY} users — nothing to compute.`,
        users_processed: 0,
        total_users: totalUsers,
      };
    }

    return {
      success: failedUsers.length === 0,
      message:
        failedUsers.length === 0
          ? `Computed similarity for ${processedCount} users.`
          : `Processed ${processedCount} users with ${failedUsers.length} failures.`,
      users_processed: processedCount,
      users_failed: failedUsers.length,
      total_users: totalUsers,
    };
  },
);
