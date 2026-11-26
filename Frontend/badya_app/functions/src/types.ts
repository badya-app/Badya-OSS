import { Timestamp } from "firebase-admin/firestore";

/**
 * Transaction types for coin movements
 */
export type TransactionType =
  | "purchase"
  | "bonus"
  | "spend"
  | "subscription"
  | "sale";

/**
 * Subscription tiers
 */
export type SubscriptionTier = "200" | "500" | "1000";

/**
 * Subscription status
 */
export type SubscriptionStatus = "active" | "canceled" | "on_hold" | "expired" | "pending";

/**
 * Coin package product IDs
 * Updated pricing:
 * - 200 coins @ $4.99 (base rate)
 * - 500 coins @ $10.99 (12% savings)
 * - 1000 coins @ $20 (20% savings)
 */
export const COIN_PACKAGES: Record<string, number> = {
  "com.badya.coins_200": 200,
  "com.badya.coins_500": 500,
  "com.badya.coins_1000": 1000,
};

/**
 * Subscription product IDs with their tier mappings and monthly coins
 */
export const SUBSCRIPTION_PRODUCTS: Record<
  string,
  { tier: SubscriptionTier; monthlyCoins: number }
> = {
  "com.badya.sub_coins_200": { tier: "200", monthlyCoins: 200 },
  "com.badya.sub_coins_500": { tier: "500", monthlyCoins: 500 },
  "com.badya.sub_coins_1000": { tier: "1000", monthlyCoins: 1000 },
};

/**
 * User subscription map stored in Firestore
 */
export interface UserSubscription {
  tier: SubscriptionTier;
  status: SubscriptionStatus;
  current_period_end?: Timestamp;
  store_subscription_id?: string;
  store_type?: string;
}

/**
 * Transaction document stored in Firestore
 */
export interface TransactionDocument {
  type: TransactionType;
  amount: number;
  description: string;
  reference_id?: string;
  created_at: Timestamp;
  // Purchase-specific fields
  product_id?: string;
  store_type?: string;
  store_transaction_id?: string;
  receipt_data?: string;
  verified_at?: Timestamp;
}

/**
 * Request payload for verifying a coin purchase
 */
export interface VerifyPurchaseRequest {
  productId: string;
  purchaseToken: string;
  packageName?: string;
}

/**
 * Request payload for verifying/activating a subscription
 */
export interface VerifySubscriptionRequest {
  productId: string;
  purchaseToken: string;
  packageName?: string;
}

/**
 * Response from verification functions
 */
export interface VerificationResponse {
  success: boolean;
  message: string;
  newBalance?: number;
  coinsAdded?: number;
  bonusCoins?: number;
  /** Whether the purchase was successfully acknowledged with Google Play */
  acknowledged?: boolean;
  /** Whether the purchase is currently in pending state (e.g. slow test card / cash payment) */
  isPending?: boolean;
}

/**
 * Google Play purchase state
 */
export enum GooglePlayPurchaseState {
  PURCHASED = 0,
  CANCELED = 1,
  PENDING = 2,
}

/**
 * Google Play subscription state (matches Google Play v3 subscriptionsv2 string enums)
 */
export enum GooglePlaySubscriptionState {
  SUBSCRIPTION_STATE_UNSPECIFIED = "SUBSCRIPTION_STATE_UNSPECIFIED",
  SUBSCRIPTION_STATE_PENDING = "SUBSCRIPTION_STATE_PENDING",
  SUBSCRIPTION_STATE_ACTIVE = "SUBSCRIPTION_STATE_ACTIVE",
  SUBSCRIPTION_STATE_PAUSED = "SUBSCRIPTION_STATE_PAUSED",
  SUBSCRIPTION_STATE_IN_GRACE_PERIOD = "SUBSCRIPTION_STATE_IN_GRACE_PERIOD",
  SUBSCRIPTION_STATE_ON_HOLD = "SUBSCRIPTION_STATE_ON_HOLD",
  SUBSCRIPTION_STATE_CANCELED = "SUBSCRIPTION_STATE_CANCELED",
  SUBSCRIPTION_STATE_EXPIRED = "SUBSCRIPTION_STATE_EXPIRED",
}

/**
 * Google Play RTDN SubscriptionNotification types
 * https://developer.android.com/google/play/billing/rtdn-reference#sub
 */
export enum PlaySubscriptionNotificationType {
  SUBSCRIPTION_RECOVERED = 1,
  SUBSCRIPTION_RENEWED = 2,
  SUBSCRIPTION_CANCELED = 3,
  SUBSCRIPTION_PURCHASED = 4,
  SUBSCRIPTION_ON_HOLD = 5,
  SUBSCRIPTION_IN_GRACE_PERIOD = 6,
  SUBSCRIPTION_RESTARTED = 7,
  SUBSCRIPTION_PRICE_CHANGE_CONFIRMED = 8,
  SUBSCRIPTION_DEFERRED = 9,
  SUBSCRIPTION_PAUSED = 10,
  SUBSCRIPTION_PAUSE_SCHEDULE_CHANGED = 11,
  SUBSCRIPTION_REVOKED = 12,
  SUBSCRIPTION_EXPIRED = 13,
}

export interface GooglePlaySubscriptionNotification {
  version: string;
  notificationType: PlaySubscriptionNotificationType;
  purchaseToken: string;
  subscriptionId: string;
}

export interface GooglePlayDeveloperNotification {
  version: string;
  packageName: string;
  eventTimeMillis: string;
  subscriptionNotification?: GooglePlaySubscriptionNotification;
  testNotification?: {
    version: string;
  };
}





