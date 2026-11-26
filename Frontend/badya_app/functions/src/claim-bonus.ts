import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp, FieldValue } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import { TransactionDocument } from "./types";
import { createRateLimiter } from "./rate-limiter";

// Per-instance rate limiter: 10 claims per 60 seconds per user
const claimLimiter = createRateLimiter(10, 60_000);

/**
 * Cloud Function: Claim a bonus (starter/onboarding bonus)
 *
 * This function:
 * 1. Validates the user is authenticated
 * 2. Rate-limits per user (10 req / 60s per instance)
 * 3. Checks idempotency (bonus not already claimed)
 * 4. Awards 150 coins atomically with transaction record
 *
 * This replaces the previous client-side runTransaction approach
 * which was blocked by Firestore security rules.
 */
export const claimBonus = onCall<{ bonusType: string }>(
  {
    cors: true,
    maxInstances: 10,
  },
  async (request) => {
    // Ensure user is authenticated
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be authenticated");
    }

    const userId = request.auth.uid;

    // Rate limiting check
    if (!claimLimiter.allow(userId)) {
      throw new HttpsError(
        "resource-exhausted",
        "Too many requests. Please try again later.",
      );
    }

    const { bonusType } = request.data;

    // Validate bonus type
    if (!bonusType || bonusType !== "starter") {
      throw new HttpsError(
        "invalid-argument",
        `Invalid bonus type: ${bonusType}`,
      );
    }

    const db = getFirestore();
    const userRef = db.collection("users").doc(userId);

    let newBalance = 0;

    try {
      await db.runTransaction(async (transaction) => {
        const userDoc = await transaction.get(userRef);

        if (!userDoc.exists) {
          throw new HttpsError("not-found", "User document not found");
        }

        const userData = userDoc.data()!;

        // Idempotency check: bonus already claimed
        if (userData.starter_bonus_claimed === true) {
          throw new AlreadyClaimedError();
        }

        const bonusAmount = 150;
        const currentBalance = (userData.coin_balance as number) || 0;
        newBalance = currentBalance + bonusAmount;

        // Update user's coin balance and set claimed flag
        transaction.update(userRef, {
          coin_balance: newBalance,
          coins_earned_total: FieldValue.increment(bonusAmount),
          starter_bonus_claimed: true,
        });

        // Create bonus transaction record
        const transactionsRef = userRef.collection("transactions");
        const transactionDoc: TransactionDocument = {
          type: "bonus",
          amount: bonusAmount,
          description: "Greeting coins - Try all features!",
          reference_id: "greeting_bonus",
          created_at: Timestamp.now(),
        };
        transaction.set(transactionsRef.doc(), transactionDoc);
      });

      // `runTransaction` already retries on ABORTED internally (default 5 attempts)
      logger.info(`Awarded starter bonus (150 coins) to user ${userId}`);

      return {
        success: true,
        message: "Claimed 150 greeting coins! Try all features!",
        coinsAwarded: 150,
        newBalance,
      };
    } catch (err) {
      if (err instanceof AlreadyClaimedError) {
        return {
          success: false,
          message: "Starter bonus already claimed",
          coinsAwarded: 0,
        };
      }
      if (err instanceof HttpsError) throw err;
      throw new HttpsError(
        "internal",
        "Failed to claim bonus. Please try again.",
      );
    }
  },
);

/**
 * Internal error type for graceful idempotency handling.
 * Caught inside claimBonus to return a clean response instead of
 * throwing an HttpsError.
 */
class AlreadyClaimedError extends Error {
  constructor() {
    super("Starter bonus already claimed");
    this.name = "AlreadyClaimedError";
  }
}
