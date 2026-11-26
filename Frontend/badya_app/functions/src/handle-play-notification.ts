import { onMessagePublished } from "firebase-functions/v2/pubsub";
import { getFirestore, Timestamp, FieldValue } from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {
  GooglePlayDeveloperNotification,
  PlaySubscriptionNotificationType,
  SUBSCRIPTION_PRODUCTS,
  TransactionDocument,
  UserSubscription,
} from "./types";
import {
  verifySubscriptionPurchase,
} from "./google-play";

const DEFAULT_PACKAGE_NAME = "com.badya.app";
const PUBSUB_TOPIC = "play-billing-notifications";

/**
 * Cloud Function: Pub/Sub Webhook Handler for Google Play Developer Notifications (RTDN)
 *
 * Listens to topic: play-billing-notifications
 * Handles events:
 * - SUBSCRIPTION_RENEWED (type 2): Add monthly coins, extend periodEnd, log transaction
 * - SUBSCRIPTION_CANCELED (type 3): Update autoRenewing = false, status = canceled (keeps access until periodEnd)
 * - SUBSCRIPTION_EXPIRED (type 13): Set isSubscriber = false, subscriptionStatus = expired
 * - SUBSCRIPTION_ON_HOLD (type 5): Update status = on_hold
 * - SUBSCRIPTION_RECOVERED (type 1): Update status = active
 */
export const handlePlayNotification = onMessagePublished(
  {
    topic: PUBSUB_TOPIC,
    region: "us-central1",
  },
  async (event) => {
    try {
      const messageData = event.data.message.data;
      if (!messageData) {
        logger.warn("Received Pub/Sub message with no data payload");
        return;
      }

      const decodedString = Buffer.from(messageData, "base64").toString("utf-8");
      const notification: GooglePlayDeveloperNotification = JSON.parse(decodedString);

      // Check if this is a test notification from Google Play Console
      if (notification.testNotification) {
        logger.info(
          `Received test notification from Google Play Console (version: ${notification.testNotification.version})`
        );
        return;
      }

      const subNotification = notification.subscriptionNotification;
      if (!subNotification) {
        logger.info("Notification received is not a subscription notification. Skipping.");
        return;
      }

      const { notificationType, purchaseToken, subscriptionId } = subNotification;
      const packageName = notification.packageName || DEFAULT_PACKAGE_NAME;

      logger.info(
        `Processing RTDN: type=${notificationType} (${PlaySubscriptionNotificationType[notificationType] || "UNKNOWN"}), subscriptionId=${subscriptionId}, token=${purchaseToken}`
      );

      const db = getFirestore();

      // 1. Find user by purchaseToken or obfuscatedExternalAccountId
      let userDocSnapshot: FirebaseFirestore.DocumentSnapshot | null = null;

      // Query by root field purchaseToken
      const queryByPurchaseToken = await db
        .collection("users")
        .where("purchaseToken", "==", purchaseToken)
        .limit(1)
        .get();

      if (!queryByPurchaseToken.empty) {
        userDocSnapshot = queryByPurchaseToken.docs[0];
      } else {
        // Fallback: check nested subscription.store_subscription_id
        const queryByStoreId = await db
          .collection("users")
          .where("subscription.store_subscription_id", "==", purchaseToken)
          .limit(1)
          .get();

        if (!queryByStoreId.empty) {
          userDocSnapshot = queryByStoreId.docs[0];
        }
      }

      // 2. If not found in Firestore, inspect subscription via Google Play API to get obfuscatedExternalAccountId (userId)
      if (!userDocSnapshot) {
        logger.info(
          "User not found directly by purchaseToken. Querying Google Play API for externalAccountId..."
        );
        const playResult = await verifySubscriptionPurchase(packageName, subscriptionId, purchaseToken);

        if (playResult.externalAccountId) {
          const directUserDoc = await db.collection("users").doc(playResult.externalAccountId).get();
          if (directUserDoc.exists) {
            userDocSnapshot = directUserDoc;
          }
        }
      }

      if (!userDocSnapshot || !userDocSnapshot.exists) {
        logger.warn(
          `Could not match notification to any user in Firestore. Token: ${purchaseToken}, SubId: ${subscriptionId}`
        );
        return;
      }

      const userId = userDocSnapshot.id;
      const userRef = userDocSnapshot.ref;
      const userData = userDocSnapshot.data() || {};
      const now = Timestamp.now();

      // Resolve subscription plan info
      const planInfo =
        SUBSCRIPTION_PRODUCTS[subscriptionId] ||
        Object.values(SUBSCRIPTION_PRODUCTS).find(
          (p) => p.tier === userData.subscriptionTier || (userData.subscription && p.tier === userData.subscription.tier)
        );

      switch (notificationType) {
        case PlaySubscriptionNotificationType.SUBSCRIPTION_RENEWED: {
          // Verify with Google Play to obtain current expiry timestamp & orderId
          const verification = await verifySubscriptionPurchase(packageName, subscriptionId, purchaseToken);
          const renewalDocId = `renewal_${verification.orderId || purchaseToken}_${verification.expiryTimeMillis}`;
          const expiryMillis = parseInt(verification.expiryTimeMillis, 10);
          const periodEnd = isNaN(expiryMillis) || expiryMillis <= 0
            ? Timestamp.fromDate(new Date(Date.now() + 30 * 24 * 60 * 60 * 1000))
            : Timestamp.fromDate(new Date(expiryMillis));

          const monthlyCoins = planInfo?.monthlyCoins ?? 0;
          const tier = planInfo?.tier ?? userData.subscriptionTier ?? "200";

          await db.runTransaction(async (transaction) => {
            const freshDoc = await transaction.get(userRef);

            // Idempotency: check if this renewal was already processed
            const existingTxDoc = await transaction.get(userRef.collection("transactions").doc(renewalDocId));
            if (existingTxDoc.exists) {
              logger.info(`Renewal already processed for user ${userId} (orderId: ${verification.orderId}). Skipping duplicate.`);
              return;
            }

            const freshData = freshDoc.data() || {};
            const currentBalance = (freshData.coin_balance as number) || 0;
            const newBalance = currentBalance + monthlyCoins;

            const existingSubscription = (freshData.subscription as UserSubscription) || {};
            const updatedSubscription: UserSubscription = {
              ...existingSubscription,
              tier: tier,
              status: "active",
              current_period_end: periodEnd,
              store_subscription_id: purchaseToken,
              store_type: "google_play",
            };

            transaction.update(userRef, {
              isSubscriber: true,
              subscriptionTier: tier,
              subscriptionStatus: "active",
              periodEnd: periodEnd,
              purchaseToken: purchaseToken,
              autoRenewing: true,
              subscription: updatedSubscription,
              coin_balance: newBalance,
              coins_earned_total: FieldValue.increment(monthlyCoins),
            });

            // Log renewal transaction
            const renewalTransaction: TransactionDocument = {
              type: "subscription",
              amount: monthlyCoins,
              description: `Subscription renewed: ${tier} coins/month plan`,
              reference_id: subscriptionId,
              created_at: now,
              product_id: subscriptionId,
              store_type: "google_play",
              store_transaction_id: purchaseToken,
              receipt_data: JSON.stringify({
                orderId: verification.orderId,
                expiryTimeMillis: verification.expiryTimeMillis,
                renewedVia: "RTDN",
              }),
              verified_at: now,
            };

            const txRef = userRef.collection("transactions").doc(renewalDocId);
            transaction.set(txRef, renewalTransaction);
          });

          logger.info(`User ${userId} subscription renewed successfully (+${monthlyCoins} coins).`);
          break;
        }

        case PlaySubscriptionNotificationType.SUBSCRIPTION_CANCELED: {
          // User canceled subscription auto-renewal. Access remains until periodEnd.
          await userRef.update({
            autoRenewing: false,
            subscriptionStatus: "canceled",
            "subscription.status": "canceled",
          });

          logger.info(`User ${userId} subscription marked canceled (autoRenewing = false).`);
          break;
        }

        case PlaySubscriptionNotificationType.SUBSCRIPTION_EXPIRED: {
          // Subscription billing cycle ended without renewal. Revoke subscriber status.
          await userRef.update({
            isSubscriber: false,
            subscriptionStatus: "expired",
            autoRenewing: false,
            "subscription.status": "expired",
          });

          logger.info(`User ${userId} subscription expired. isSubscriber set to false.`);
          break;
        }

        case PlaySubscriptionNotificationType.SUBSCRIPTION_ON_HOLD: {
          // Payment issue (e.g., credit card declined)
          await userRef.update({
            subscriptionStatus: "on_hold",
            "subscription.status": "on_hold",
          });

          logger.info(`User ${userId} subscription placed on_hold.`);
          break;
        }

        case PlaySubscriptionNotificationType.SUBSCRIPTION_RECOVERED:
        case PlaySubscriptionNotificationType.SUBSCRIPTION_RESTARTED: {
          // Recovered from on_hold or restarted
          await userRef.update({
            isSubscriber: true,
            subscriptionStatus: "active",
            autoRenewing: true,
            "subscription.status": "active",
          });

          logger.info(`User ${userId} subscription recovered/restarted.`);
          break;
        }

        case PlaySubscriptionNotificationType.SUBSCRIPTION_PURCHASED: {
          // Initial purchase is handled client-side via verifySubscription.
          // Intentional no-op to avoid double-crediting.
          logger.info(`User ${userId}: SUBSCRIPTION_PURCHASED received via RTDN. Handled by client verifySubscription flow.`);
          break;
        }

        case PlaySubscriptionNotificationType.SUBSCRIPTION_IN_GRACE_PERIOD: {
          // User's payment failed but is in grace period — still has access.
          // Keep current status, could add a banner flag in the future.
          logger.info(`User ${userId} subscription is in grace period. No status change.`);
          break;
        }

        default:
          logger.info(
            `Unhandled notification type: ${notificationType} (${PlaySubscriptionNotificationType[notificationType]})`
          );
          break;
      }
    } catch (error) {
      logger.error("Error processing Google Play notification:", error);
      // Re-throw so Pub/Sub can retry if temporary error
      throw error;
    }
  }
);
