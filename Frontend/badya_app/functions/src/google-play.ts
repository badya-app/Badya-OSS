import { google, Auth } from "googleapis";
import * as logger from "firebase-functions/logger";
import {
  GooglePlayPurchaseState,
  GooglePlaySubscriptionState,
} from "./types";

// Re-export the enums for convenience
export { GooglePlayPurchaseState, GooglePlaySubscriptionState };

// Initialize the Android Publisher API client
const androidPublisher = google.androidpublisher("v3");

/**
 * Get authenticated Google API client using service account
 * The service account must have access to Google Play Developer API
 */
async function getAuthClient(): Promise<Auth.OAuth2Client> {
  const auth = new google.auth.GoogleAuth({
    scopes: ["https://www.googleapis.com/auth/androidpublisher"],
  });
  return auth.getClient() as Promise<Auth.OAuth2Client>;
}

/**
 * Response from verifying a consumable product purchase
 */
export interface ProductPurchaseResult {
  valid: boolean;
  purchaseState: GooglePlayPurchaseState;
  orderId: string;
  purchaseTimeMillis: string;
  acknowledged: boolean;
  errorMessage?: string;
}

/**
 * Response from verifying a subscription purchase
 */
export interface SubscriptionPurchaseResult {
  valid: boolean;
  subscriptionState: GooglePlaySubscriptionState;
  orderId: string;
  startTimeMillis: string;
  expiryTimeMillis: string;
  autoRenewing: boolean;
  externalAccountId?: string;
  errorMessage?: string;
}

/**
 * Verify a consumable product purchase with Google Play
 * @param packageName The app's package name (e.g., com.badya.app)
 * @param productId The product ID (e.g., com.badya.coins_500)
 * @param purchaseToken The purchase token from the client
 */
export async function verifyProductPurchase(
  packageName: string,
  productId: string,
  purchaseToken: string
): Promise<ProductPurchaseResult> {
  try {
    const authClient = await getAuthClient();
    google.options({ auth: authClient });

    const response = await androidPublisher.purchases.products.get({
      packageName,
      productId,
      token: purchaseToken,
    });

    const purchase = response.data;

    // Check if purchase exists and is valid
    if (!purchase) {
      return {
        valid: false,
        purchaseState: GooglePlayPurchaseState.CANCELED,
        orderId: "",
        purchaseTimeMillis: "0",
        acknowledged: false,
        errorMessage: "Purchase not found",
      };
    }

    const purchaseState = purchase.purchaseState as GooglePlayPurchaseState;
    const isValid = purchaseState === GooglePlayPurchaseState.PURCHASED;

    return {
      valid: isValid,
      purchaseState,
      orderId: purchase.orderId || "",
      purchaseTimeMillis: purchase.purchaseTimeMillis || "0",
      acknowledged: purchase.acknowledgementState === 1,
    };
  } catch (error) {
    logger.error("Error verifying product purchase:", error);
    return {
      valid: false,
      purchaseState: GooglePlayPurchaseState.CANCELED,
      orderId: "",
      purchaseTimeMillis: "0",
      acknowledged: false,
      errorMessage: error instanceof Error ? error.message : "Unknown error",
    };
  }
}

/**
 * Acknowledge a consumable product purchase
 * This must be called after crediting the coins to complete the purchase
 */
export async function acknowledgeProductPurchase(
  packageName: string,
  productId: string,
  purchaseToken: string
): Promise<boolean> {
  try {
    const authClient = await getAuthClient();
    google.options({ auth: authClient });

    await androidPublisher.purchases.products.acknowledge({
      packageName,
      productId,
      token: purchaseToken,
    });

    return true;
  } catch (error) {
    logger.error("Error acknowledging product purchase:", error);
    return false;
  }
}

/**
 * Verify a subscription purchase with Google Play
 * @param packageName The app's package name
 * @param subscriptionId The subscription product ID
 * @param purchaseToken The purchase token from the client
 */
export async function verifySubscriptionPurchase(
  packageName: string,
  subscriptionId: string,
  purchaseToken: string
): Promise<SubscriptionPurchaseResult> {
  try {
    const authClient = await getAuthClient();
    google.options({ auth: authClient });

    const response = await androidPublisher.purchases.subscriptionsv2.get({
      packageName,
      token: purchaseToken,
    });

    const subscription = response.data;

    if (!subscription) {
      return {
        valid: false,
        subscriptionState: GooglePlaySubscriptionState.SUBSCRIPTION_STATE_EXPIRED,
        orderId: "",
        startTimeMillis: "0",
        expiryTimeMillis: "0",
        autoRenewing: false,
        errorMessage: "Subscription not found",
      };
    }

    logger.info(
      `Google Play subscriptionsv2 response for ${subscriptionId}: state=${subscription.subscriptionState}, orderId=${subscription.latestOrderId}`
    );

    // Map subscription state safely, handling both string enum and numeric fallback
    let subscriptionState = GooglePlaySubscriptionState.SUBSCRIPTION_STATE_UNSPECIFIED;
    const rawState: unknown = subscription.subscriptionState;
    if (typeof rawState === "string" && rawState in GooglePlaySubscriptionState) {
      subscriptionState = rawState as GooglePlaySubscriptionState;
    } else if (rawState === 2 || rawState === "2") {
      subscriptionState = GooglePlaySubscriptionState.SUBSCRIPTION_STATE_ACTIVE;
    } else if (rawState === 4 || rawState === "4") {
      subscriptionState = GooglePlaySubscriptionState.SUBSCRIPTION_STATE_IN_GRACE_PERIOD;
    } else if (typeof rawState === "string") {
      subscriptionState = rawState as GooglePlaySubscriptionState;
    }

    // Check if subscription is active or in grace period
    const isValid =
      subscriptionState === GooglePlaySubscriptionState.SUBSCRIPTION_STATE_ACTIVE ||
      subscriptionState === GooglePlaySubscriptionState.SUBSCRIPTION_STATE_IN_GRACE_PERIOD;

    // Get line items for expiry info (subscriptionsv2 returns ISO 8601 string like "2026-10-15T01:33:21.501Z")
    const lineItem = subscription.lineItems?.[0];
    const rawExpiry = lineItem?.expiryTime;
    let expiryTime = "0";
    if (rawExpiry) {
      const parsed = Date.parse(rawExpiry);
      expiryTime = isNaN(parsed) ? rawExpiry : parsed.toString();
    }

    return {
      valid: isValid,
      subscriptionState,
      orderId: subscription.latestOrderId || "",
      startTimeMillis: subscription.startTime || "0",
      expiryTimeMillis: expiryTime,
      autoRenewing: lineItem?.autoRenewingPlan !== undefined,
      externalAccountId: subscription.externalAccountIdentifiers?.obfuscatedExternalAccountId || undefined,
      errorMessage: isValid ? undefined : `Subscription is not active (state: ${subscriptionState})`,
    };
  } catch (error) {
    logger.error("Error verifying subscription:", error);
    return {
      valid: false,
      subscriptionState: GooglePlaySubscriptionState.SUBSCRIPTION_STATE_EXPIRED,
      orderId: "",
      startTimeMillis: "0",
      expiryTimeMillis: "0",
      autoRenewing: false,
      errorMessage: error instanceof Error ? error.message : "Unknown error",
    };
  }
}

/**
 * Acknowledge a subscription purchase
 */
export async function acknowledgeSubscriptionPurchase(
  packageName: string,
  subscriptionId: string,
  purchaseToken: string
): Promise<boolean> {
  try {
    const authClient = await getAuthClient();
    google.options({ auth: authClient });

    await androidPublisher.purchases.subscriptions.acknowledge({
      packageName,
      subscriptionId,
      token: purchaseToken,
    });

    return true;
  } catch (error) {
    logger.error("Error acknowledging subscription:", error);
    return false;
  }
}

