import 'dart:async';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inapp_purchase_plus/flutter_inapp_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:Badya/utils/logger.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/transaction_model.dart';

/// Result of an IAP operation
class IAPResult {
  final bool success;
  final String message;
  final int? coinsAdded;
  final int? creditsGranted;
  final int? bonusCoins;
  final bool isSubscription;
  /// Whether the Cloud Function successfully acknowledged the purchase
  /// with Google Play. When false, the receipt should be kept for retry.
  final bool acknowledged;
  /// Whether the purchase is currently in pending state (e.g. slow test card / pending payment)
  final bool isPending;

  IAPResult({
    required this.success,
    required this.message,
    this.coinsAdded,
    this.creditsGranted,
    this.bonusCoins,
    this.isSubscription = false,
    this.acknowledged = true,
    this.isPending = false,
  });
}

/// Service to handle In-App Purchases
/// Follows singleton pattern from AdkService
/// Includes mock mode for development (kDebugMode)
class IAPService {
  static final IAPService _instance = IAPService._internal();
  factory IAPService() => _instance;
  IAPService._internal();

  final FlutterInappPurchase _iap = FlutterInappPurchase.instance;
  StreamSubscription<PurchasedItem?>? _purchaseSubscription;
  StreamSubscription<PurchaseResult?>? _purchaseErrorSubscription;

  // Product IDs
  // One-time coin packages
  static const Set<String> _coinProductIds = {
    'com.badya.coins_200',
    'com.badya.coins_500',
    'com.badya.coins_1000',
  };

  // Subscription product IDs
  static const Set<String> _subscriptionProductIds = {
    'com.badya.sub_coins_200',
    'com.badya.sub_coins_500',
    'com.badya.sub_coins_1000',
  };

  static Set<String> get coinProductIds => _coinProductIds;
  static Set<String> get subscriptionProductIds => _subscriptionProductIds;
  static Set<String> get allProductIds => {..._coinProductIds, ..._subscriptionProductIds};

  // Cached products
  List<IAPItem> _coinProducts = [];
  List<IAPItem> _subscriptionProducts = [];

  // Track in-flight purchase tokens to prevent duplicate concurrent verification
  final Set<String> _processingTokens = <String>{};
  bool _isInitialized = false;

  // Mock mode flag - uses kDebugMode by default
  bool mockMode = kDebugMode;

  List<IAPItem> get coinProducts => _coinProducts;
  List<IAPItem> get subscriptionProducts => _subscriptionProducts;

  // Purchase callbacks
  Function(IAPResult)? onPurchaseComplete;
  Function(String)? onPurchaseError;

  /// Initialize IAP and load products
  Future<bool> initialize() async {
    if (mockMode) {
      Logger.info('IAPService: Running in mock mode');
      _loadMockProducts();
      return true;
    }

    if (_isInitialized) {
      Logger.info('IAPService: Already initialized, refreshing products');
      await loadProducts();
      return true;
    }

    // Cancel any previous subscriptions just in case
    await _purchaseSubscription?.cancel();
    _purchaseSubscription = null;
    await _purchaseErrorSubscription?.cancel();
    _purchaseErrorSubscription = null;

    // Retry any pending purchase acknowledgments from previous sessions
    await _retryPendingAcknowledgments();

    // Initialize connection to the store
    final initResult = await _iap.initialize();
    if (initResult == null) {
      Logger.warn('IAPService: Store not available');
      return false;
    }

    // Listen to purchase updates
    _purchaseSubscription = FlutterInappPurchase.purchaseUpdated.listen(
      _handlePurchaseUpdate,
      onError: (error) {
        Logger.error('IAPService: Purchase stream error', error);
        onPurchaseError?.call(error.toString());
      },
    );

    // Listen to purchase errors (e.g., user cancellation, payment declined)
    _purchaseErrorSubscription = FlutterInappPurchase.purchaseError.listen(
      (PurchaseResult? result) {
        final code = result?.code ?? -1;
        final message = result?.message ?? 'Purchase failed or cancelled';
        Logger.warn('IAPService: Purchase error/cancelled: [$code] $message');
        onPurchaseError?.call(message);
      },
      onError: (error) {
        Logger.error('IAPService: Purchase error stream error', error);
        onPurchaseError?.call(error.toString());
      },
    );

    _isInitialized = true;

    // Load products
    await loadProducts();
    return true;
  }

  /// Load available products from the store
  Future<void> loadProducts() async {
    if (mockMode) {
      _loadMockProducts();
      return;
    }

    try {
      // 1. Load consumable coin packages
      final coinItems = await _iap.getProducts(_coinProductIds.toList());
      _coinProducts = coinItems
          .where((p) => _coinProductIds.contains(p.productId))
          .toList();

      // 2. Load subscription products
      final subItems = await _iap.getSubscriptions(_subscriptionProductIds.toList());
      _subscriptionProducts = subItems
          .where((p) => _subscriptionProductIds.contains(p.productId))
          .toList();

      Logger.info(
        'IAPService: Loaded ${_coinProducts.length} coin products and ${_subscriptionProducts.length} subscription products',
      );
    } catch (e) {
      Logger.error('IAPService: Error loading products', e);
    }
  }

  /// Load mock products for development
  void _loadMockProducts() {
    _coinProducts = CoinPackage.packages
        .map((p) => IAPItem.fromJSON({
              'productId': p.productId,
              'title': '${p.coins} Coins',
              'description':
                  p.bonusPercent > 0 ? '+${p.bonusPercent}% bonus!' : 'Basic pack',
              'price': '\$${p.price.toStringAsFixed(2)}',
              'currency': 'USD',
              'originalPrice': p.price.toString(),
            }))
        .toList();

    _subscriptionProducts = SubscriptionPackage.packages
        .map((s) => IAPItem.fromJSON({
              'productId': s.productId,
              'title': '${s.coinsPerMonth} Coins / mo',
              'description': '${s.coinsPerMonth} coins per month auto-renewing plan',
              'price': '\$${s.price.toStringAsFixed(2)}',
              'currency': 'USD',
              'originalPrice': s.price.toString(),
            }))
        .toList();
  }

  /// Purchase a coin package
  Future<bool> purchaseCoinPackage(String productId) async {
    if (mockMode) {
      return _mockPurchaseCoinPackage(productId);
    }

    // Verify product exists
    final productExists = _coinProducts.any((p) => p.productId == productId);
    if (!productExists) {
      throw Exception('Product not found: $productId');
    }

    // requestPurchase takes the product ID string
    await _iap.requestPurchase(productId);
    return true;
  }

  /// Purchase/subscribe to a subscription plan
  Future<bool> buySubscription(String productId) async {
    if (mockMode) {
      return _mockPurchaseSubscription(productId);
    }

    final productExists =
        _subscriptionProducts.any((p) => p.productId == productId);
    if (!productExists) {
      throw Exception('Subscription not found: $productId');
    }

    // Attach current user's UID to obfuscatedAccountId for server-side webhook attribution
    final uid = FirebaseAuth.instance.currentUser?.uid;
    await _iap.requestSubscription(
      productId,
      obfuscatedAccountIdAndroid: uid,
    );
    return true;
  }

  /// Open Google Play's subscription management page for Badya
  Future<bool> launchSubscriptionManagement({String? productId}) async {
    final skuParam = productId != null ? 'sku=$productId&' : '';
    final url = Uri.parse(
      'https://play.google.com/store/account/subscriptions?${skuParam}package=com.badya',
    );
    try {
      if (await canLaunchUrl(url)) {
        return await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      Logger.error('IAPService: Error launching subscription management', e);
    }
    return false;
  }

  /// Restore purchases (for subscriptions)
  Future<void> restorePurchases() async {
    if (mockMode) {
      Logger.info('IAPService: Mock restore purchases');
      return;
    }

    await _iap.getAvailablePurchases();
  }

  /// Handle purchase update from the store
  void _handlePurchaseUpdate(PurchasedItem? purchase) async {
    if (purchase == null) return;

    final productId = purchase.productId;
    final purchaseToken = purchase.purchaseToken;

    if (productId == null || purchaseToken == null) {
      Logger.error('IAPService: Purchase missing productId or purchaseToken');
      return;
    }

    // Ignore purchases that are still pending payment (e.g., slow test cards, cash/bank transfers)
    if (purchase.purchaseStateAndroid == PurchaseState.pending ||
        purchase.transactionStateIOS == TransactionState.deferred) {
      Logger.info(
        'IAPService: Purchase $productId ($purchaseToken) is pending payment. Waiting for store completion.',
      );
      final pendingResult = IAPResult(
        success: false,
        isPending: true,
        message: 'Payment is pending approval by Google Play.',
      );
      onPurchaseComplete?.call(pendingResult);
      return;
    }

    final isCoinPurchase = _coinProductIds.contains(productId);
    final isSubPurchase = _subscriptionProductIds.contains(productId);

    if (!isCoinPurchase && !isSubPurchase) {
      Logger.info('IAPService: Unrecognized purchase ignored: $productId');
      return;
    }

    // Prevent concurrent verification for the same purchase token
    if (_processingTokens.contains(purchaseToken)) {
      Logger.info(
        'IAPService: Purchase $productId with token $purchaseToken is already being processed.',
      );
      return;
    }
    _processingTokens.add(purchaseToken);

    try {
      // Persist the receipt locally before verifying (with deduplication)
      await _persistPurchaseReceipt(purchase);

      final result = await _verifyAndDeliverPurchase(
        purchase,
        isSubscription: isSubPurchase,
      );

      if (result.verified && result.acknowledged) {
        if (isCoinPurchase) {
          // Must consume consumable products so users can buy them again!
          await _iap.finishTransaction(purchase, isConsumable: true);
        }
        await _removePurchaseReceipt(purchase);
      } else if (result.isPending) {
        Logger.info(
          'IAPService: Purchase is pending verification on server. Leaving transaction intact.',
        );
      } else if (result.verified && !result.acknowledged) {
        Logger.warn(
          'IAPService: Server verified goods but acknowledgment '
          'failed for $productId. Receipt kept for retry.',
        );
        await _iap.finishTransaction(purchase, isConsumable: isCoinPurchase);
      } else {
        // Failed verification that is not pending
        await _iap.finishTransaction(purchase, isConsumable: isCoinPurchase);
        await _removePurchaseReceipt(purchase);
      }
    } finally {
      _processingTokens.remove(purchaseToken);
    }
  }

  /// Verify purchase with backend and deliver goods
  Future<({bool verified, bool acknowledged, bool isPending})> _verifyAndDeliverPurchase(
    PurchasedItem purchase, {
    bool isSubscription = false,
  }) async {
    try {
      final productId = purchase.productId!;
      final purchaseToken = purchase.purchaseToken!;

      final result = isSubscription
          ? await _verifySubscriptionWithBackend(
              productId: productId,
              purchaseToken: purchaseToken,
            )
          : await _verifyPurchaseWithBackend(
              productId: productId,
              purchaseToken: purchaseToken,
            );

      onPurchaseComplete?.call(result);
      return (
        verified: result.success,
        acknowledged: result.acknowledged,
        isPending: result.isPending,
      );
    } catch (e) {
      Logger.error('IAPService: Error verifying purchase', e);
      onPurchaseError?.call(e.toString());
      return (verified: false, acknowledged: false, isPending: false);
    }
  }

  /// Call backend to verify subscription purchase
  Future<IAPResult> _verifySubscriptionWithBackend({
    required String productId,
    required String purchaseToken,
  }) async {
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('verifySubscription');
      final result = await callable.call({
        'productId': productId,
        'purchaseToken': purchaseToken,
        'packageName': 'com.badya.app',
      });

      final data = result.data as Map<String, dynamic>;
      final isPending = (data['isPending'] as bool?) ?? false;
      return IAPResult(
        success: (data['success'] as bool?) ?? false,
        message: (data['message'] as String?) ?? '',
        coinsAdded: data['coinsAdded'] as int?,
        isSubscription: true,
        acknowledged: (data['acknowledged'] as bool?) ?? true,
        isPending: isPending,
      );
    } catch (e) {
      Logger.error('IAPService: Backend subscription verification error', e);
      return IAPResult(
        success: false,
        message: 'Subscription verification failed: $e',
        isSubscription: true,
      );
    }
  }

  /// Call backend to verify coin purchase
  Future<IAPResult> _verifyPurchaseWithBackend({
    required String productId,
    required String purchaseToken,
  }) async {
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('verifyPurchase');
      final result = await callable.call({
        'productId': productId,
        'purchaseToken': purchaseToken,
        'packageName': 'com.badya.app',
      });

      final data = result.data as Map<String, dynamic>;
      final isPending = (data['isPending'] as bool?) ?? false;
      return IAPResult(
        success: (data['success'] as bool?) ?? false,
        message: (data['message'] as String?) ?? '',
        coinsAdded: data['coinsAdded'] as int?,
        acknowledged: (data['acknowledged'] as bool?) ?? true,
        isPending: isPending,
      );
    } catch (e) {
      Logger.error('IAPService: Backend verification error', e);
      return IAPResult(
        success: false,
        message: 'Verification failed: $e',
      );
    }
  }

  /// Sync subscription status with backend on app resume.
  /// Catches any renewals that happened server-side via RTDN
  /// while the app was closed.
  Future<IAPResult> syncSubscription() async {
    if (mockMode) {
      return IAPResult(
        success: true,
        message: 'Mock sync — no-op',
        isSubscription: true,
      );
    }

    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('syncSubscription');
      final result = await callable.call({});

      final data = result.data as Map<String, dynamic>;
      return IAPResult(
        success: data['success'] as bool,
        message: data['message'] as String,
        coinsAdded: (data['bonusCoins'] as int?) ?? 0,
        isSubscription: true,
      );
    } catch (e) {
      Logger.error('IAPService: Error syncing subscription', e);
      return IAPResult(
        success: false,
        message: 'Sync failed: $e',
        isSubscription: true,
      );
    }
  }

  // --- Local Receipt Persistence (Task 6: crash recovery) ---

  static const String _pendingReceiptsKey = 'pending_iap_receipts';

  /// Persist a purchase receipt locally before sending to the Cloud Function.
  /// This ensures we can retry acknowledgment if the app crashes mid-flow.
  Future<void> _persistPurchaseReceipt(PurchasedItem purchase) async {
    if (mockMode) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final receipts = prefs.getStringList(_pendingReceiptsKey) ?? [];

      // Avoid duplicate persistence for the same purchaseToken
      final alreadyPersisted = receipts.any((r) {
        try {
          final data = jsonDecode(r) as Map<String, dynamic>;
          return data['purchaseToken'] == purchase.purchaseToken;
        } catch (_) {
          return false;
        }
      });
      if (alreadyPersisted) return;

      final receipt = jsonEncode({
        'productId': purchase.productId,
        'purchaseToken': purchase.purchaseToken,
        'timestamp': DateTime.now().toIso8601String(),
      });

      receipts.add(receipt);
      await prefs.setStringList(_pendingReceiptsKey, receipts);
      Logger.info(
          'IAPService: Persisted pending receipt: ${purchase.productId}');
    } catch (e) {
      Logger.error('IAPService: Error persisting receipt', e);
    }
  }

  /// Remove a persisted receipt after successful processing.
  Future<void> _removePurchaseReceipt(PurchasedItem purchase) async {
    if (mockMode) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final receipts = prefs.getStringList(_pendingReceiptsKey) ?? [];

      final purchaseToken = purchase.purchaseToken;

      receipts.removeWhere((r) {
        try {
          final data = jsonDecode(r) as Map<String, dynamic>;
          return data['purchaseToken'] == purchaseToken;
        } catch (_) {
          return false;
        }
      });

      await prefs.setStringList(_pendingReceiptsKey, receipts);
    } catch (e) {
      Logger.error('IAPService: Error removing receipt', e);
    }
  }

  /// Retry acknowledgment for any pending receipts from a previous session.
  /// Called during [initialize] so we recover from crashes that happened
  /// after the server credited coins but before acknowledgment completed.
  Future<void> _retryPendingAcknowledgments() async {
    if (mockMode) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final receipts = prefs.getStringList(_pendingReceiptsKey) ?? [];

      if (receipts.isEmpty) return;

      Logger.info(
        'IAPService: Retrying acknowledgment for '
        '${receipts.length} pending purchase(s)',
      );

      final remaining = <String>[];

      for (final receiptJson in receipts) {
        try {
          final data = jsonDecode(receiptJson) as Map<String, dynamic>;
          final productId = data['productId'] as String;
          final purchaseToken = data['purchaseToken'] as String;

          // Re-verify with the backend; the server will acknowledge
          // if not already done (idempotent).
          final isSubscription = _subscriptionProductIds.contains(productId);
          final result = isSubscription
              ? await _verifySubscriptionWithBackend(
                  productId: productId,
                  purchaseToken: purchaseToken,
                )
              : await _verifyPurchaseWithBackend(
                  productId: productId,
                  purchaseToken: purchaseToken,
                );

          if (result.success && result.acknowledged) {
            Logger.info(
              'IAPService: Successfully retried acknowledgment '
              'for $productId',
            );
            // Don't add back to remaining — processed successfully.
          } else {
            Logger.warn(
              'IAPService: Retry verification/acknowledgment failed for '
              '$productId: ${result.message}'
              ' (acknowledged: ${result.acknowledged})',
            );
            remaining.add(receiptJson);
          }
        } catch (e) {
          Logger.error('IAPService: Error retrying receipt', e);
          remaining.add(receiptJson);
        }
      }

      await prefs.setStringList(_pendingReceiptsKey, remaining);
    } catch (e) {
      Logger.error('IAPService: Error in retryPendingAcknowledgments', e);
    }
  }

  // --- Mock purchase methods for development ---

  Future<bool> _mockPurchaseCoinPackage(String productId) async {
    // Simulate successful purchase locally for development
    // without hitting the real Cloud Function backend
    final package = CoinPackage.getByProductId(productId);
    if (package == null) {
      onPurchaseError?.call('Unknown product: $productId');
      return false;
    }

    final result = IAPResult(
      success: true,
      message: 'Mock purchase successful',
      coinsAdded: package.coins,
    );
    onPurchaseComplete?.call(result);
    return true;
  }

  Future<bool> _mockPurchaseSubscription(String productId) async {
    final package = SubscriptionPackage.getByProductId(productId);
    if (package == null) {
      onPurchaseError?.call('Unknown subscription: $productId');
      return false;
    }

    final result = IAPResult(
      success: true,
      message: 'Mock subscription successful',
      coinsAdded: package.coinsPerMonth,
      isSubscription: true,
    );
    onPurchaseComplete?.call(result);
    return true;
  }

  /// Consume any pending/unconsumed purchases on Android
  /// Useful to unblock users whose purchases got stuck in 'Item already owned' state
  Future<void> consumeAllStuckItems() async {
    if (mockMode) return;
    try {
      await _iap.consumeAll();
      Logger.info('IAPService: Finished consuming all existing purchases');
    } catch (e) {
      Logger.warn('IAPService: Error consuming all items: $e');
    }
  }

  /// Dispose resources
  void dispose() {
    _purchaseSubscription?.cancel();
    _purchaseErrorSubscription?.cancel();
  }
}
