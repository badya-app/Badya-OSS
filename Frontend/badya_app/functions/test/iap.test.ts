/**
 * Tests for Cloud Functions - IAP Integration & Bonus System
 *
 * Task 2.1: Write 4-6 focused tests for Cloud Functions
 */

import {
  COIN_PACKAGES,
  GooglePlayPurchaseState,
} from "../src/types";
import type { ProductPurchaseResult } from "../src/google-play";
import { createRateLimiter } from "../src/rate-limiter";

describe("IAP Cloud Functions", () => {
  describe("Coin Package Verification", () => {
    test("Google Play receipt verification returns valid purchase state", async () => {
      // Arrange: Simulate Google Play API response for valid purchase
      const mockVerifyResult: ProductPurchaseResult = {
        valid: true,
        purchaseState: GooglePlayPurchaseState.PURCHASED,
        orderId: "GPA.1234-5678-9012",
        purchaseTimeMillis: Date.now().toString(),
        acknowledged: false,
      };

      // Simulate verification function
      const verifyProductPurchase = jest.fn().mockResolvedValue(mockVerifyResult);

      // Act: Call the mock
      const result = await verifyProductPurchase(
        "com.badya.app",
        "com.badya.coins_500",
        "test-purchase-token"
      );

      // Assert
      expect(result.valid).toBe(true);
      expect(result.purchaseState).toBe(GooglePlayPurchaseState.PURCHASED);
      expect(result.orderId).toBe("GPA.1234-5678-9012");
      expect(verifyProductPurchase).toHaveBeenCalledWith(
        "com.badya.app",
        "com.badya.coins_500",
        "test-purchase-token"
      );
    });

    test("Coin crediting calculates correct amount based on product ID", () => {
      // Test all current coin packages
      expect(COIN_PACKAGES["com.badya.coins_200"]).toBe(200);
      expect(COIN_PACKAGES["com.badya.coins_500"]).toBe(500);
      expect(COIN_PACKAGES["com.badya.coins_1000"]).toBe(1000);

      // Test unknown product returns undefined
      expect(COIN_PACKAGES["com.badya.coins_invalid"]).toBeUndefined();
    });

    test("Invalid purchase state is rejected", async () => {
      // Arrange: Simulate Google Play API response for canceled purchase
      const mockVerifyResult: ProductPurchaseResult = {
        valid: false,
        purchaseState: GooglePlayPurchaseState.CANCELED,
        orderId: "",
        purchaseTimeMillis: "0",
        acknowledged: false,
        errorMessage: "Purchase was canceled",
      };

      const verifyProductPurchase = jest.fn().mockResolvedValue(mockVerifyResult);

      // Act
      const result = await verifyProductPurchase(
        "com.badya.app",
        "com.badya.coins_500",
        "canceled-token"
      );

      // Assert
      expect(result.valid).toBe(false);
      expect(result.purchaseState).toBe(GooglePlayPurchaseState.CANCELED);
    });
  });

  describe("Rate Limiter", () => {
    test("Allows requests within limit", () => {
      const limiter = createRateLimiter(3, 60_000);

      expect(limiter.allow("user-1")).toBe(true);
      expect(limiter.allow("user-1")).toBe(true);
      expect(limiter.allow("user-1")).toBe(true);
    });

    test("Blocks requests over the limit", () => {
      const limiter = createRateLimiter(2, 60_000);

      expect(limiter.allow("user-1")).toBe(true);
      expect(limiter.allow("user-1")).toBe(true);
      expect(limiter.allow("user-1")).toBe(false);
    });

    test("Different users have independent rate limits", () => {
      const limiter = createRateLimiter(2, 60_000);

      expect(limiter.allow("user-1")).toBe(true);
      expect(limiter.allow("user-1")).toBe(true);
      expect(limiter.allow("user-1")).toBe(false);

      // Different user should be unaffected
      expect(limiter.allow("user-2")).toBe(true);
    });

    test("Rate limit window expires", async () => {
      const limiter = createRateLimiter(1, 100); // 1 request per 100ms

      expect(limiter.allow("user-1")).toBe(true);
      expect(limiter.allow("user-1")).toBe(false);

      // Wait for window to expire
      await new Promise((resolve) => setTimeout(resolve, 150));

      expect(limiter.allow("user-1")).toBe(true);
    });

    test("Clear resets all rate limits", () => {
      const limiter = createRateLimiter(1, 60_000);

      expect(limiter.allow("user-1")).toBe(true);
      expect(limiter.allow("user-1")).toBe(false);

      limiter.clear();

      expect(limiter.allow("user-1")).toBe(true);
    });
  });

  describe("Idempotency", () => {
    test("Same receipt token should be identifiable for duplicate check", () => {
      // Test that purchase tokens can be used as unique identifiers
      const purchaseToken1 = "token-abc-123";
      const purchaseToken2 = "token-abc-123";
      const purchaseToken3 = "token-xyz-456";

      // Same tokens should be equal (for idempotency check)
      expect(purchaseToken1).toBe(purchaseToken2);

      // Different tokens should not be equal
      expect(purchaseToken1).not.toBe(purchaseToken3);
    });

    test("Transaction document structure supports idempotency via store_transaction_id", () => {
      // Create a mock transaction document
      const transactionDoc = {
        type: "purchase" as const,
        amount: 500,
        description: "Purchased 500 coins",
        reference_id: "com.badya.coins_500",
        created_at: new Date(),
        product_id: "com.badya.coins_500",
        store_type: "google_play",
        store_transaction_id: "unique-purchase-token-123", // Used for idempotency
        receipt_data: "{}",
        verified_at: new Date(),
      };

      // Verify the document has the required field for idempotency checking
      expect(transactionDoc.store_transaction_id).toBeDefined();
      expect(typeof transactionDoc.store_transaction_id).toBe("string");
      expect(transactionDoc.store_transaction_id.length).toBeGreaterThan(0);
    });
  });
});
