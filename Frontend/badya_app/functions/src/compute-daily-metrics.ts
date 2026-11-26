// /**
//  * Cloud Function: Compute Daily Recommendation Metrics
//  *
//  * COMMENTED OUT: recommendation_logs pipeline decommissioned.
//  * See commit <INSERT_COMMIT_HASH> for the original implementation.
//  *
//  * Scheduled to run daily at 1:00 AM UTC.
//  * Queries recommendation_logs + recommendation_clicks for the previous day
//  * and writes aggregated metrics to recommendation_metrics/{date}.
//  *
//  * Metrics computed:
//  *   - CTR (Click-Through Rate): total clicks / total impressions
//  *   - Precision@K: matching clicks / (K × impression count)
//  *   - Coverage: unique content recommended / total public content pool
//  *   - Diversity: avg pairwise cosine distance among recommended embeddings
//  *   - Strategy breakdown: % of requests by strategy type
//  */
// 
// import { onSchedule } from "firebase-functions/v2/scheduler";
// import { getFirestore, Timestamp } from "firebase-admin/firestore";
// import * as logger from "firebase-functions/logger";
// 
// // Default number of recommendations per request
// const K = 20;
// 
// /**
//  * Compute cosine similarity between two embedding vectors.
//  */
// function cosineSimilarity(a: number[], b: number[]): number {
//   if (a.length !== b.length || a.length === 0) return 0;
//   let dot = 0, normA = 0, normB = 0;
//   for (let i = 0; i < a.length; i++) {
//     dot += a[i] * b[i];
//     normA += a[i] * a[i];
//     normB += b[i] * b[i];
//   }
//   if (normA === 0 || normB === 0) return 0;
//   return dot / (Math.sqrt(normA) * Math.sqrt(normB));
// }
// 
// /**
//  * Compute the Diversity metric: average pairwise cosine distance
//  * (1 - cosine_similarity) among a set of embedding vectors.
//  * Returns 0 if fewer than 2 embeddings are provided.
//  */
// function computeDiversity(embeddings: number[][]): number {
//   if (embeddings.length < 2) return 0;
//   let totalDistance = 0;
//   let pairCount = 0;
//   for (let i = 0; i < embeddings.length; i++) {
//     for (let j = i + 1; j < embeddings.length; j++) {
//       totalDistance += 1 - cosineSimilarity(embeddings[i], embeddings[j]);
//       pairCount++;
//     }
//   }
//   return pairCount > 0 ? totalDistance / pairCount : 0;
// }
// 
// export const computeDailyMetrics = onSchedule(
//   {
//     schedule: "every day 01:00",
//     timeZone: "UTC",
//     region: "us-central1",
//   },
//   async () => {
//     const db = getFirestore();
// 
//     // Compute date range for the previous day (UTC)
//     const now = new Date();
//     const yesterdayStart = new Date(Date.UTC(
//       now.getUTCFullYear(),
//       now.getUTCMonth(),
//       now.getUTCDate() - 1,
//       0, 0, 0, 0,
//     ));
//     const yesterdayEnd = new Date(Date.UTC(
//       now.getUTCFullYear(),
//       now.getUTCMonth(),
//       now.getUTCDate(),
//       0, 0, 0, 0,
//     ));
//     const dateStr = yesterdayStart.toISOString().slice(0, 10); // "YYYY-MM-DD"
// 
//     logger.info(`Computing daily metrics for ${dateStr}`);
// 
//     // ── 1. Load impressions from recommendation_logs ──────────────
//     const impressionsSnapshot = await db
//       .collection("recommendation_logs")
//       .where("date", ">=", yesterdayStart)
//       .where("date", "<", yesterdayEnd)
//       .get();
// 
//     const impressionLogs: Array<{
//       user_id: string;
//       recommended_ids: string[];
//       strategy: string;
//     }> = [];
// 
//     impressionsSnapshot.forEach((doc) => {
//       const data = doc.data();
//       impressionLogs.push({
//         user_id: data.user_id ?? "",
//         recommended_ids: data.recommended_ids ?? [],
//         strategy: data.strategy ?? "unknown",
//       });
//     });
// 
//     const impressionCount = impressionLogs.length;
// 
//     if (impressionCount === 0) {
//       logger.info("No impressions found for yesterday. Writing zero metrics.");
//       await db.collection("recommendation_metrics").doc(dateStr).set({
//         date: dateStr,
//         computed_at: Timestamp.now(),
//         impression_count: 0,
//         click_count: 0,
//         ctr: 0,
//         precision_at_k: 0,
//         coverage: 0,
//         diversity: 0,
//         strategy_breakdown: {},
//         total_public_content: 0,
//         has_data: false,
//       });
//       return;
//     }
// 
//     // ── 2. Load clicks from recommendation_clicks ─────────────────
//     // Load all clicks for the day
//     const clicksSnapshot = await db
//       .collection("recommendation_clicks")
//       .where("timestamp", ">=", yesterdayStart)
//       .where("timestamp", "<", yesterdayEnd)
//       .get();
// 
//     // Also load recommendation-specific clicks (source: "home_recommended")
//     // for accurate CTR computation (library clicks are from a different surface)
//     const recClicksSnapshot = await db
//       .collection("recommendation_clicks")
//       .where("source", "==", "home_recommended")
//       .where("timestamp", ">=", yesterdayStart)
//       .where("timestamp", "<", yesterdayEnd)
//       .get();
// 
//     // Build a set of clicked content IDs per user for matching
//     const clicksByUser = new Map<string, Set<string>>();
//     // Count recommendation-specific clicks for CTR
//     let recClickCount = 0;
//     recClicksSnapshot.forEach((doc) => {
//       recClickCount++;
//     });
// 
//     let totalClickCount = 0;
// 
//     clicksSnapshot.forEach((doc) => {
//       const data = doc.data();
//       const userId = data.user_id as string;
//       const contentId = data.content_id as string;
//       if (!userId || !contentId) return;
// 
//       totalClickCount++;
//       if (!clicksByUser.has(userId)) {
//         clicksByUser.set(userId, new Set());
//       }
//       clicksByUser.get(userId)!.add(contentId);
//     });
// 
//     // ── 3. Compute Precision@K ────────────────────────────────────
//     // For each impression log entry, check how many of the recommended
//     // items the user clicked within the day.
//     let matchingClicks = 0;
//     const allRecommendedIds = new Set<string>();
// 
//     for (const log of impressionLogs) {
//       const userClicks = clicksByUser.get(log.user_id);
//       if (userClicks) {
//         for (const recId of log.recommended_ids) {
//           allRecommendedIds.add(recId);
//           if (userClicks.has(recId)) {
//             matchingClicks++;
//           }
//         }
//       } else {
//         // Still count these as recommended for coverage
//         for (const recId of log.recommended_ids) {
//           allRecommendedIds.add(recId);
//         }
//       }
//     }
// 
//     // Compute total actual impressions (sum of recommended_ids lengths per impression)
//     // instead of assuming K per impression, because the backend may return
//     // fewer than K items (e.g., not enough public content).
//     let totalActualImpressions = 0;
//     for (const log of impressionLogs) {
//       totalActualImpressions += log.recommended_ids.length;
//     }
// 
//     const precisionAtK = impressionCount > 0
//       ? matchingClicks / (impressionCount * K)
//       : 0;
// 
//     // CTR uses only recommendation-surface clicks (source: "home_recommended")
//     // to avoid inflation from library/discovery page taps
//     const ctr = totalActualImpressions > 0
//       ? recClickCount / totalActualImpressions
//       : 0;
// 
//     // ── 4. Compute Coverage ───────────────────────────────────────
//     // Coverage = unique content recommended / total public content in language
//     // We estimate total public content pool across all languages.
//     const publicContentSnapshot = await db
//       .collection("user_content")
//       .where("is_public", "==", true)
//       .count()
//       .get();
// 
//     const totalPublicContent = publicContentSnapshot.data()?.count ?? 0;
//     const coverage = totalPublicContent > 0
//       ? allRecommendedIds.size / totalPublicContent
//       : 0;
// 
//     // ── 5. Compute Diversity ──────────────────────────────────────
//     // Fetch embeddings for a sample of recommended content to compute
//     // average pairwise cosine distance.
//     let diversity = 0;
//     const sampleIds = Array.from(allRecommendedIds).slice(0, 100);
//     if (sampleIds.length >= 2) {
//       const embeddings: number[][] = [];
//       // Fetch in batches of 30
//       const batchSize = 30;
//       for (let i = 0; i < sampleIds.length; i += batchSize) {
//         const batch = sampleIds.slice(i, i + batchSize);
//         const batchSnapshot = await db
//           .collection("user_content")
//           .where("__name__", "in", batch)
//           .get();
// 
//         batchSnapshot.forEach((doc) => {
//           const metadata = doc.data()?.metadata;
//           const embedding = metadata?.embedding as number[] | undefined;
//           if (embedding && embedding.length > 0) {
//             embeddings.push(embedding);
//           }
//         });
//       }
//       diversity = computeDiversity(embeddings);
//     }
// 
//     // ── 6. Strategy Breakdown ─────────────────────────────────────
//     const strategyCounts = new Map<string, number>();
//     for (const log of impressionLogs) {
//       strategyCounts.set(
//         log.strategy,
//         (strategyCounts.get(log.strategy) ?? 0) + 1,
//       );
//     }
// 
//     const strategyBreakdown: Record<string, number> = {};
//     for (const [strategy, count] of strategyCounts) {
//       strategyBreakdown[strategy] = count / impressionCount;
//     }
// 
//     // ── 7. Write to recommendation_metrics/{date} ─────────────────
//     const metricsDoc = {
//       date: dateStr,
//       computed_at: Timestamp.now(),
//       impression_count: impressionCount,
//       click_count: totalClickCount,
//       matching_click_count: matchingClicks,
//       ctr: Math.round(ctr * 10000) / 10000,
//       rec_click_count: recClickCount,
//       precision_at_k: Math.round(precisionAtK * 10000) / 10000,
//       coverage: Math.round(coverage * 10000) / 10000,
//       diversity: Math.round(diversity * 10000) / 10000,
//       strategy_breakdown: strategyBreakdown,
//       total_public_content: totalPublicContent,
//       unique_content_recommended: allRecommendedIds.size,
//       active_users: impressionLogs.length,
//       has_data: true,
//     };
// 
//     await db.collection("recommendation_metrics").doc(dateStr).set(metricsDoc);
// 
//     logger.info(`Daily metrics for ${dateStr}:`, metricsDoc);
//   },
// );
