import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp, FieldValue } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {
  SUBSCRIPTION_PRODUCTS,
  TransactionDocument,
  UserSubscription,
  VerificationResponse,
} from "./types";
import {
  verifySubscriptionPurchase,
  GooglePlaySubscriptionState,
} from "./google-play";

const DEFAULT_PACKAGE_NAME = "com.badya.app";

/**
 * Cloud Function: Sync subscription status on app open
 *
 * This function:
 * 1. Reads the stored subscription info from user document
 * 2. Verifies current status with Google Play
 * 3. Handles renewals: reset credits, credit bonus coins, update period
 * 4. Handles expiry: update status to expired
 *
 * Task 2.5: Subscription sync endpoint
 */
export const syncSubscription = onCall<{ packageName?: string }>(
  { cors: true },
  async (request): Promise<VerificationResponse> => {
    // Ensure user is authenticated
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be authenticated");
    }

    const userId = request.auth.uid;
    const packageName = request.data?.packageName || DEFAULT_PACKAGE_NAME;

    const db = getFirestore();
    const userRef = db.collection("users").doc(userId);
    const transactionsRef = userRef.collection("transactions");

    // Get current user data
    const userDoc = await userRef.get();
    if (!userDoc.exists) {
      return {
        success: false,
        message: "User not found",
      };
    }

    const userData = userDoc.data()!;
    const subscription = userData.subscription as UserSubscription | undefined;

    // If no subscription or invalid tier, nothing to sync
    if (!subscription || !subscription.tier || (subscription.tier as string) === "free") {
      return {
        success: true,
        message: "No active subscription to sync",
      };
    }

    // If no store subscription ID, can't verify
    if (!subscription.store_subscription_id) {
      return {
        success: true,
        message: "No store subscription ID to verify",
      };
    }

    // Find the product ID for this subscription tier
    const productId = Object.keys(SUBSCRIPTION_PRODUCTS).find(
      (id) => SUBSCRIPTION_PRODUCTS[id].tier === subscription.tier
    );

    if (!productId) {
      return {
        success: false,
        message: "Unknown subscription tier",
      };
    }

    const subscriptionInfo = SUBSCRIPTION_PRODUCTS[productId];

    // Verify subscription with Google Play
    const verificationResult = await verifySubscriptionPurchase(
      packageName,
      productId,
      subscription.store_subscription_id
    );

    const now = Timestamp.now();
    let newBalance = (userData.coin_balance as number) || 0;
    let message = "";
    let bonusCoinsAdded = 0;
    // let creditsReset = false; // TODO: Implement credits reset logic

    // Determine the new state based on verification
    if (verificationResult.valid) {
      const expiryMillis = parseInt(verificationResult.expiryTimeMillis, 10);
      const newExpiryDate = new Date(expiryMillis);
      const newExpiryTimestamp = Timestamp.fromDate(newExpiryDate);

      // Check if this is a renewal (new expiry is later than stored)
      const storedExpiry = subscription.current_period_end?.toDate();
      const isRenewal = storedExpiry && newExpiryDate > storedExpiry;

      if (isRenewal) {
        // Handle renewal: reset credits and grant bonus coins
        await db.runTransaction(async (transaction) => {
          const freshUserDoc = await transaction.get(userRef);
          const freshUserData = freshUserDoc.data()!;
          const currentBalance = (freshUserData.coin_balance as number) || 0;
          const coinsToAdd = subscriptionInfo.monthlyCoins;
          newBalance = currentBalance + coinsToAdd;
          bonusCoinsAdded = coinsToAdd;

          // Update subscription with new period and grant coins
          const updatedSubscription: UserSubscription = {
            ...subscription,
            status: "active",
            current_period_end: newExpiryTimestamp,
          };

          transaction.update(userRef, {
            isSubscriber: true,
            subscriptionTier: subscriptionInfo.tier,
            subscriptionStatus: "active",
            periodEnd: newExpiryTimestamp,
            subscription: updatedSubscription,
            coin_balance: newBalance,
            coins_earned_total: FieldValue.increment(coinsToAdd),
          });

          // Create renewal transaction
          const renewalTransaction: TransactionDocument = {
            type: "subscription",
            amount: coinsToAdd,
            description: `${subscriptionInfo.tier} coins/month subscription renewed`,
            reference_id: productId,
            created_at: now,
          };
          transaction.set(transactionsRef.doc(), renewalTransaction);
        });

        // TODO: Implement credits reset logic when needed
        message = "Subscription renewed successfully";
        logger.info(`Subscription renewed for user ${userId}`);
      } else {
        // Just update status to active if it was something else
        if (subscription.status !== "active") {
          const updatedSubscription: UserSubscription = {
            ...subscription,
            status: "active",
            current_period_end: newExpiryTimestamp,
          };

          await userRef.update({
            subscription: updatedSubscription,
          });
          message = "Subscription status updated to active";
        } else {
          message = "Subscription is active and up to date";
        }
      }
    } else {
      // Subscription is no longer valid - check if expired or cancelled
      const isExpired =
        verificationResult.subscriptionState ===
        GooglePlaySubscriptionState.SUBSCRIPTION_STATE_EXPIRED ||
        verificationResult.subscriptionState ===
        GooglePlaySubscriptionState.SUBSCRIPTION_STATE_CANCELED;

      if (isExpired) {
        // Update status to expired but keep coins until period end
        const updatedSubscription: UserSubscription = {
          ...subscription,
          status: "expired",
        };

        await userRef.update({
          isSubscriber: false,
          subscriptionStatus: "expired",
          subscription: updatedSubscription,
        });

        message = "Subscription has expired";
        logger.info(`Subscription expired for user ${userId}`);
      } else {
        message = `Subscription state: ${verificationResult.subscriptionState}`;
      }
    }

    return {
      success: true,
      message,
      newBalance,
      bonusCoins: bonusCoinsAdded,
    };
  }
);




