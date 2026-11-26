import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp, FieldValue } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {
  COIN_PACKAGES,
  TransactionDocument,
  VerifyPurchaseRequest,
  VerificationResponse,
} from "./types";
import { verifyProductPurchase, acknowledgeProductPurchase, GooglePlayPurchaseState } from "./google-play";
import { createRateLimiter } from "./rate-limiter";

const DEFAULT_PACKAGE_NAME = "com.badya.app";

// Per-instance rate limiter: 20 purchase verifications per 60 seconds per user
const purchaseLimiter = createRateLimiter(20, 60_000);

/**
 * Cloud Function: Verify a coin purchase from Google Play
 *
 * This function:
 * 1. Validates the request
 * 2. Rate-limits per user (20 req / 60s per instance)
 * 3. Checks idempotency (hasn't been processed before)
 * 4. Verifies the purchase with Google Play
 * 5. Credits coins atomically with transaction record
 * 6. Acknowledges the purchase with Google Play
 *
 * Task 2.2 & 2.3: Google Play receipt verification and coin purchase handler
 */
export const verifyPurchase = onCall<VerifyPurchaseRequest>(
  {
    cors: true,
    maxInstances: 10,
  },
  async (request): Promise<VerificationResponse> => {
    // Ensure user is authenticated
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be authenticated");
    }

    const userId = request.auth.uid;

    // Rate limiting check
    if (!purchaseLimiter.allow(userId)) {
      throw new HttpsError(
        "resource-exhausted",
        "Too many requests. Please try again later.",
      );
    }

    const { productId, purchaseToken, packageName } = request.data;

    // Validate request
    if (!productId || !purchaseToken) {
      throw new HttpsError("invalid-argument", "Missing productId or purchaseToken");
    }

    // Check if product is a valid coin package
    const coinsToAdd = COIN_PACKAGES[productId];
    if (!coinsToAdd) {
      throw new HttpsError("invalid-argument", `Invalid product ID: ${productId}`);
    }

    const db = getFirestore();
    const userRef = db.collection("users").doc(userId);
    const transactionsRef = userRef.collection("transactions");

    // Idempotency check: Check if this purchase token was already processed
    const existingTransaction = await transactionsRef
      .where("store_transaction_id", "==", purchaseToken)
      .limit(1)
      .get();

    if (!existingTransaction.empty) {
      logger.info(`Purchase already processed: ${purchaseToken}`);
      // Re-attempt acknowledgment if it failed on the first try.
      // This handles the crash-recovery scenario where coins were credited
      // but acknowledgeProductPurchase didn't complete.
      const reAcknowledged = await acknowledgeProductPurchase(
        packageName || DEFAULT_PACKAGE_NAME,
        productId,
        purchaseToken
      ).catch((err) => {
        logger.warn(`Idempotent ack attempt failed: ${err}`);
        return false;
      });
      return {
        success: true,
        message: "Purchase already processed",
        coinsAdded: 0,
        acknowledged: reAcknowledged,
      };
    }

    // Verify purchase with Google Play
    const verificationResult = await verifyProductPurchase(
      packageName || DEFAULT_PACKAGE_NAME,
      productId,
      purchaseToken
    );

    if (verificationResult.purchaseState === GooglePlayPurchaseState.PENDING) {
      logger.info(`Purchase is in pending state: ${purchaseToken}`);
      return {
        success: false,
        isPending: true,
        message: "Payment is pending approval by Google Play.",
        coinsAdded: 0,
        acknowledged: false,
      };
    }

    if (!verificationResult.valid) {
      logger.error(`Invalid purchase: ${verificationResult.errorMessage}`);
      throw new HttpsError(
        "failed-precondition",
        `Purchase verification failed: ${verificationResult.errorMessage || "Invalid purchase"}`
      );
    }

    if (verificationResult.purchaseState !== GooglePlayPurchaseState.PURCHASED) {
      throw new HttpsError(
        "failed-precondition",
        `Purchase not completed. State: ${verificationResult.purchaseState}`
      );
    }

    // Credit coins atomically using a transaction
    const now = Timestamp.now();
    let newBalance = 0;

    await db.runTransaction(async (transaction) => {
      const userDoc = await transaction.get(userRef);

      if (!userDoc.exists) {
        throw new HttpsError("not-found", "User document not found");
      }

      const userData = userDoc.data()!;
      const currentBalance = (userData.coin_balance as number) || 0;
      newBalance = currentBalance + coinsToAdd;

      // Update user's coin balance
      transaction.update(userRef, {
        coin_balance: newBalance,
        coins_earned_total: FieldValue.increment(coinsToAdd),
      });

      // Create transaction record
      const transactionDoc: TransactionDocument = {
        type: "purchase",
        amount: coinsToAdd,
        description: `Purchased ${coinsToAdd} coins`,
        reference_id: productId,
        created_at: now,
        product_id: productId,
        store_type: "google_play",
        store_transaction_id: purchaseToken,
        receipt_data: JSON.stringify({
          orderId: verificationResult.orderId,
          purchaseTime: verificationResult.purchaseTimeMillis,
        }),
        verified_at: now,
      };

      const newTransactionRef = transactionsRef.doc();
      transaction.set(newTransactionRef, transactionDoc);
    });

    // Acknowledge the purchase with Google Play
    // This is done outside the Firestore transaction to avoid timeouts
    const acknowledged = await acknowledgeProductPurchase(
      packageName || DEFAULT_PACKAGE_NAME,
      productId,
      purchaseToken
    );

    if (!acknowledged) {
      logger.warn(`Failed to acknowledge purchase: ${purchaseToken}`);
      // Note: We still return success because coins were credited
      // The purchase will eventually be refunded by Google if not acknowledged
    }

    logger.info(`Successfully credited ${coinsToAdd} coins to user ${userId}`);

    return {
      success: true,
      message: `Successfully added ${coinsToAdd} coins`,
      newBalance,
      coinsAdded: coinsToAdd,
      acknowledged,
    };
  }
);
