import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp, FieldValue } from "firebase-admin/firestore";
import {
  SUBSCRIPTION_PRODUCTS,
  TransactionDocument,
  UserSubscription,
  VerifySubscriptionRequest,
  VerificationResponse,
} from "./types";
import {
  verifySubscriptionPurchase,
  acknowledgeSubscriptionPurchase,
  GooglePlaySubscriptionState,
} from "./google-play";

const DEFAULT_PACKAGE_NAME = "com.badya.app";

/**
 * Cloud Function: Verify and activate a subscription from Google Play
 *
 * This function:
 * 1. Validates the request
 * 2. Checks idempotency (same subscription not processed twice in same period)
 * 3. Verifies the subscription with Google Play
 * 4. Activates subscription with credits and bonus coins
 * 5. Creates transaction records
 *
 * Task 2.4: Subscription activation handler
 */
export const verifySubscription = onCall<VerifySubscriptionRequest>(
  { cors: true },
  async (request): Promise<VerificationResponse> => {
    // Ensure user is authenticated
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be authenticated");
    }

    const userId = request.auth.uid;
    const { productId, purchaseToken, packageName } = request.data;

    // Validate request
    if (!productId || !purchaseToken) {
      throw new HttpsError("invalid-argument", "Missing productId or purchaseToken");
    }

    // Check if product is a valid subscription
    const subscriptionInfo = SUBSCRIPTION_PRODUCTS[productId];
    if (!subscriptionInfo) {
      throw new HttpsError("invalid-argument", `Invalid subscription product ID: ${productId}`);
    }

    const db = getFirestore();
    const userRef = db.collection("users").doc(userId);
    const transactionsRef = userRef.collection("transactions");

    // Idempotency check: Check if this exact purchase token was already processed
    const existingTransaction = await transactionsRef
      .where("store_transaction_id", "==", purchaseToken)
      .where("type", "==", "subscription")
      .limit(1)
      .get();

    if (!existingTransaction.empty) {
      console.log(`Subscription already processed: ${purchaseToken}`);
      return {
        success: true,
        message: "Subscription already processed",
        bonusCoins: 0,
      };
    }

    // Verify subscription with Google Play
    const verificationResult = await verifySubscriptionPurchase(
      packageName || DEFAULT_PACKAGE_NAME,
      productId,
      purchaseToken
    );

    if (
      verificationResult.subscriptionState ===
      GooglePlaySubscriptionState.SUBSCRIPTION_STATE_PENDING
    ) {
      return {
        success: false,
        isPending: true,
        message: "Subscription payment is pending approval by Google Play.",
        coinsAdded: 0,
        acknowledged: false,
      };
    }

    if (!verificationResult.valid) {
      console.error(`Invalid subscription: ${verificationResult.errorMessage}`);
      throw new HttpsError(
        "failed-precondition",
        `Subscription verification failed: ${verificationResult.errorMessage || "Invalid subscription"}`
      );
    }

    // Check subscription state
    const validStates = [
      GooglePlaySubscriptionState.SUBSCRIPTION_STATE_ACTIVE,
      GooglePlaySubscriptionState.SUBSCRIPTION_STATE_IN_GRACE_PERIOD,
    ];

    if (!validStates.includes(verificationResult.subscriptionState)) {
      throw new HttpsError(
        "failed-precondition",
        `Subscription not active. State: ${verificationResult.subscriptionState}`
      );
    }

    // Calculate expiry date
    const expiryMillis = parseInt(verificationResult.expiryTimeMillis, 10);
    const expiryDate = new Date(expiryMillis);
    const expiryTimestamp = Timestamp.fromDate(expiryDate);
    const now = Timestamp.now();

    // Activate subscription atomically
    let newBalance = 0;

    await db.runTransaction(async (transaction) => {
      const userDoc = await transaction.get(userRef);

      if (!userDoc.exists) {
        throw new HttpsError("not-found", "User document not found");
      }

      const userData = userDoc.data()!;
      const currentBalance = (userData.coin_balance as number) || 0;
      const coinsToAdd = subscriptionInfo.monthlyCoins;
      newBalance = currentBalance + coinsToAdd;

      // Build subscription map for backwards compatibility
      const subscriptionMap: UserSubscription = {
        tier: subscriptionInfo.tier,
        status: "active",
        current_period_end: expiryTimestamp,
        store_subscription_id: purchaseToken,
        store_type: "google_play",
      };

      // Update user document with subscription fields (both root schema and nested subscription map)
      transaction.update(userRef, {
        isSubscriber: true,
        subscriptionTier: subscriptionInfo.tier,
        subscriptionStatus: "active",
        periodEnd: expiryTimestamp,
        purchaseToken: purchaseToken,
        autoRenewing: verificationResult.autoRenewing,
        subscription: subscriptionMap,
        coin_balance: newBalance,
        coins_earned_total: FieldValue.increment(coinsToAdd),
      });

      // Create subscription transaction record
      const subscriptionTransaction: TransactionDocument = {
        type: "subscription",
        amount: coinsToAdd,
        description: `Subscribed to ${subscriptionInfo.tier} coins/month plan`,
        reference_id: productId,
        created_at: now,
        product_id: productId,
        store_type: "google_play",
        store_transaction_id: purchaseToken,
        receipt_data: JSON.stringify({
          orderId: verificationResult.orderId,
          startTime: verificationResult.startTimeMillis,
          expiryTime: verificationResult.expiryTimeMillis,
          autoRenewing: verificationResult.autoRenewing,
        }),
        verified_at: now,
      };

      const subTransactionRef = transactionsRef.doc();
      transaction.set(subTransactionRef, subscriptionTransaction);
    });

    // Acknowledge the subscription with Google Play
    const acknowledged = await acknowledgeSubscriptionPurchase(
      packageName || DEFAULT_PACKAGE_NAME,
      productId,
      purchaseToken
    );

    if (!acknowledged) {
      console.warn(`Failed to acknowledge subscription: ${purchaseToken}`);
    }

    console.log(
      `Successfully activated ${subscriptionInfo.tier} subscription for user ${userId}`
    );

    return {
      success: true,
      message: `Successfully activated ${subscriptionInfo.tier} subscription`,
      newBalance,
      coinsAdded: subscriptionInfo.monthlyCoins,
      acknowledged,
    };
  }
);




