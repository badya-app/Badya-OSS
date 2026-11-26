/**
 * Firebase Cloud Functions for Badya App
 *
 * This module exports all Cloud Functions for:
 * - Google Play IAP verification
 * - Coin purchase handling
 *
 * Task Group 2: Google Play IAP Integration & Receipt Verification
 */

import { initializeApp } from "firebase-admin/app";

// Initialize Firebase Admin SDK
initializeApp();

// Export IAP verification & subscription functions
export { verifyPurchase } from "./verify-purchase";
export { verifySubscription } from "./verify-subscription";
export { syncSubscription } from "./sync-subscription";
export { handlePlayNotification } from "./handle-play-notification";

// Export feedback email function
export { sendFeedbackEmail } from "./feedback-email";

// Export bonus claiming function (server-side to bypass security rules)
export { claimBonus } from "./claim-bonus";

// Export daily recommendation metrics computation (decommissioned — kept for reference)
// export { computeDailyMetrics } from "./compute-daily-metrics";

// Export user similarity matrix computation (v2 embedding-based CF)
export { computeUserSimilarity, triggerUserSimilarity } from "./compute-user-similarity";

// Export account deletion (GDPR right to erasure)
export { deleteUserAccount } from "./delete-user-account";

// Export user data (GDPR Article 20 right to portability)
export { exportUserData } from "./export-user-data";

// Export moderation report submission (server-side authority for limits)
export { submitReport } from "./submit-report";