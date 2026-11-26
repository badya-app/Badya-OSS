import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:Badya/config/local_mode.dart';
import 'package:Badya/utils/logger.dart';

import '../models/transaction_model.dart';

/// Service to manage coin balance, credits, and transactions
/// Follows the singleton pattern from AdkService
/// Uses multi-layer caching from UserPreferencesService
class CoinService {
  static final CoinService _instance = CoinService._internal();
  factory CoinService() => _instance;
  CoinService._internal();

  static FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static FirebaseAuth _auth = FirebaseAuth.instance;

  static String? get _uid => _auth.currentUser?.uid;

  // In-memory cache for current session
  static final Map<String, dynamic> _memoryCache = {};

  @visibleForTesting
  static set firestoreInstance(FirebaseFirestore instance) {
    _firestore = instance;
  }

  @visibleForTesting
  static set authInstance(FirebaseAuth instance) {
    _auth = instance;
  }

  // --- Helper Methods for Caching ---

  String _getCacheKey(String key) => '${_uid}_$key';

  Future<void> _setLocal(String key, dynamic value) async {
    if (_uid == null) return;
    final cacheKey = _getCacheKey(key);
    _memoryCache[cacheKey] = value;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (value is int) {
        await prefs.setInt(cacheKey, value);
      } else if (value is String) {
        await prefs.setString(cacheKey, value);
      } else if (value is bool) {
        await prefs.setBool(cacheKey, value);
      } else if (value is Map) {
        await prefs.setString(cacheKey, jsonEncode(value));
      }
    } catch (e) {
      Logger.error('Error saving to local cache', e);
    }
  }

  Future<T?> _getLocal<T>(String key) async {
    if (_uid == null) return null;
    final cacheKey = _getCacheKey(key);

    // 1. Check Memory
    if (_memoryCache.containsKey(cacheKey)) {
      final value = _memoryCache[cacheKey];
      if (value is T) return value;
    }

    // 2. Check SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      if (T == int) {
        final value = prefs.getInt(cacheKey);
        if (value != null) {
          _memoryCache[cacheKey] = value;
          return value as T;
        }
      } else if (T == String) {
        final value = prefs.getString(cacheKey);
        if (value != null) {
          _memoryCache[cacheKey] = value;
          return value as T;
        }
      } else if (T == bool) {
        final value = prefs.getBool(cacheKey);
        if (value != null) {
          _memoryCache[cacheKey] = value;
          return value as T;
        }
      }
    } catch (e) {
      Logger.error('Error reading from local cache', e);
    }
    return null;
  }

  // --- Coin Balance Methods ---

  /// Get current coin balance (with caching)
  Future<int> getCoinBalance() async {
    if (LocalMode.enabled) return LocalMode.defaultCoins;
    // 1. Check local cache first
    final cached = await _getLocal<int>('coin_balance');
    if (cached != null) {
      _syncBalanceFromFirestore(); // Background sync
      return cached;
    }

    // 2. Fetch from Firestore
    if (_uid == null) return 0;
    try {
      final doc = await _firestore.collection('users').doc(_uid).get();
      if (doc.exists && doc.data() != null) {
        final balance = (doc.data()!['coin_balance'] as num?)?.toInt() ?? 0;
        await _setLocal('coin_balance', balance);
        return balance;
      }
    } catch (e) {
      Logger.error('Error getting coin balance', e);
    }
    return 0;
  }

  /// Get total coins earned
  Future<int> getCoinsEarnedTotal() async {
    if (_uid == null) return 0;
    try {
      final doc = await _firestore.collection('users').doc(_uid).get();
      if (doc.exists && doc.data() != null) {
        return (doc.data()!['coins_earned_total'] as num?)?.toInt() ?? 0;
      }
    } catch (e) {
      Logger.error('Error getting coins earned total', e);
    }
    return 0;
  }

  /// Get total coins spent
  Future<int> getCoinsSpentTotal() async {
    if (_uid == null) return 0;
    try {
      final doc = await _firestore.collection('users').doc(_uid).get();
      if (doc.exists && doc.data() != null) {
        return (doc.data()!['coins_spent_total'] as num?)?.toInt() ?? 0;
      }
    } catch (e) {
      Logger.error('Error getting coins spent total', e);
    }
    return 0;
  }

  /// Refresh balance from Firestore (force sync)
  Future<int> refreshBalance() async {
    if (LocalMode.enabled) return LocalMode.defaultCoins;
    if (_uid == null) return 0;
    try {
      final doc = await _firestore.collection('users').doc(_uid).get();
      if (doc.exists && doc.data() != null) {
        final balance = (doc.data()!['coin_balance'] as num?)?.toInt() ?? 0;
        await _setLocal('coin_balance', balance);
        return balance;
      }
    } catch (e) {
      Logger.error('Error refreshing balance', e);
    }
    return 0;
  }

  /// Listen to real-time balance changes
  Stream<int> listenToBalance() {
    if (LocalMode.enabled) return Stream.value(LocalMode.defaultCoins);
    if (_uid == null) return Stream.value(0);

    return _firestore.collection('users').doc(_uid).snapshots().map((doc) {
      if (doc.exists && doc.data() != null) {
        final balance = (doc.data()!['coin_balance'] as num?)?.toInt() ?? 0;
        _setLocal('coin_balance', balance);
        return balance;
      }
      return 0;
    });
  }

  /// Background sync of balance from Firestore
  void _syncBalanceFromFirestore() {
    if (_uid == null) return;
    _firestore
        .collection('users')
        .doc(_uid)
        .get()
        .then((doc) {
          if (doc.exists && doc.data() != null) {
            final balance = (doc.data()!['coin_balance'] as num?)?.toInt() ?? 0;
            _setLocal('coin_balance', balance);
          }
        })
        .catchError((e) {
          Logger.error('Error background syncing balance', e);
        });
  }

  // --- Transaction Methods ---

  /// Get transactions with pagination and optional type filter
  /// Returns a record of (transactions, lastDocumentSnapshot) for cursor pagination.
  Future<(List<CoinTransaction>, DocumentSnapshot?)> getTransactions({
    TransactionType? type,
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) async {
    if (_uid == null) return (<CoinTransaction>[], null as DocumentSnapshot?);

    try {
      Query query = _firestore
          .collection('users')
          .doc(_uid)
          .collection('transactions')
          .orderBy('created_at', descending: true)
          .limit(limit);

      if (type != null) {
        query = query.where('type', isEqualTo: type.value);
      }

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snapshot = await query.get();
      final transactions = snapshot.docs
          .map((doc) => CoinTransaction.fromFirestore(doc))
          .toList();
      return (
        transactions,
        snapshot.docs.isEmpty ? null as DocumentSnapshot? : snapshot.docs.last,
      );
    } catch (e) {
      Logger.error('Error getting transactions', e);
      return (<CoinTransaction>[], null as DocumentSnapshot?);
    }
  }

  // --- Content Access Methods (Task 3.4) ---

  /// Result of content access check
  /// Check if user can access content (has enough coins)
  Future<ContentAccessResult> canAccessContent(
    ContentType contentType, {
    bool isImportedContent = false,
  }) async {
    if (LocalMode.enabled) {
      return ContentAccessResult(
        canAccess: true,
        cost: 0,
        currentBalance: LocalMode.defaultCoins,
      );
    }
    if (_uid == null) {
      return ContentAccessResult(
        canAccess: false,
        cost: contentType.costFor(isImportedContent: isImportedContent),
        reason: 'User not authenticated',
      );
    }

    try {
      final doc = await _firestore.collection('users').doc(_uid).get();
      if (!doc.exists || doc.data() == null) {
        return ContentAccessResult(
          canAccess: false,
          cost: contentType.costFor(isImportedContent: isImportedContent),
          reason: 'User data not found',
        );
      }

      final data = doc.data()!;
      final coinBalance = (data['coin_balance'] as num?)?.toInt() ?? 0;
      final cost = contentType.costFor(isImportedContent: isImportedContent);

      // If the content is free (cost == 0), grant access.
      if (cost == 0) {
        return ContentAccessResult(canAccess: true, cost: 0);
      }

      // If the user has enough coins, grant access.
      if (coinBalance >= cost) {
        return ContentAccessResult(canAccess: true, cost: cost);
      }

      return ContentAccessResult(
        canAccess: false,
        cost: cost,
        reason: 'Insufficient balance',
        currentBalance: coinBalance,
      );
    } catch (e) {
      Logger.error('Error checking content access', e);
      return ContentAccessResult(
        canAccess: false,
        cost: contentType.costFor(isImportedContent: isImportedContent),
        reason: 'Error: $e',
      );
    }
  }

  /// Spend coins for content
  /// Returns SpendResult indicating success/failure
  Future<SpendResult> spendForContent(
    ContentType contentType,
    String contentId, {
    bool isImportedContent = false,
  }) async {
    if (LocalMode.enabled) {
      return SpendResult(
        success: true,
        message: 'Access granted (local mode)',
        coinsSpent: 0,
        newBalance: LocalMode.defaultCoins,
      );
    }
    if (_uid == null) {
      return SpendResult(success: false, message: 'User not authenticated');
    }

    // First check if user can access
    final accessResult = await canAccessContent(
      contentType,
      isImportedContent: isImportedContent,
    );
    if (!accessResult.canAccess) {
      return SpendResult(
        success: false,
        message: accessResult.reason ?? 'Cannot access content',
        insufficientFunds: true,
      );
    }

    try {
      final result = await _firestore.runTransaction<SpendResult>((
        transaction,
      ) async {
        final userRef = _firestore.collection('users').doc(_uid);
        final userDoc = await transaction.get(userRef);

        if (!userDoc.exists || userDoc.data() == null) {
          return SpendResult(success: false, message: 'User not found');
        }

        final data = userDoc.data()!;
        final transactionsRef = userRef.collection('transactions');
        final now = Timestamp.now();
        final cost = contentType.costFor(isImportedContent: isImportedContent);

        // Free content - no coin deduction needed
        if (cost == 0) {
          return SpendResult(
            success: true,
            message: 'Access granted (free content)',
            coinsSpent: 0,
            newBalance: (data['coin_balance'] as num?)?.toInt() ?? 0,
          );
        }

        // Spend coins
        final coinBalance = (data['coin_balance'] as num?)?.toInt() ?? 0;
        final coinsSpentTotal =
            (data['coins_spent_total'] as num?)?.toInt() ?? 0;

        transaction.update(userRef, {
          'coin_balance': coinBalance - cost,
          'coins_spent_total': coinsSpentTotal + cost,
        });

        // Create spend transaction
        final transactionDoc = {
          'type': 'spend',
          'amount': cost,
          'description': '${contentType.displayName}: $contentId',
          'reference_id': contentId,
          'created_at': now,
        };
        transaction.set(transactionsRef.doc(), transactionDoc);

        // Update local cache
        await _setLocal('coin_balance', coinBalance - cost);

        return SpendResult(
          success: true,
          message: 'Spent $cost coins',
          coinsSpent: cost,
          newBalance: coinBalance - cost,
        );
      });

      return result;
    } catch (e) {
      Logger.error('Error spending for content', e);
      return SpendResult(success: false, message: 'Error: $e');
    }
  }

  /// Refund coins if content generation failed (e.g. video generation failed)
  Future<SpendResult> refundForContent(
    ContentType contentType,
    String contentId, {
    bool isImportedContent = false,
  }) async {
    if (LocalMode.enabled) {
      return SpendResult(
        success: true,
        message: 'No refund needed (local mode)',
        coinsSpent: 0,
        newBalance: LocalMode.defaultCoins,
      );
    }
    if (_uid == null) {
      return SpendResult(success: false, message: 'User not authenticated');
    }

    final cost = contentType.costFor(isImportedContent: isImportedContent);
    if (cost <= 0) {
      return SpendResult(success: true, message: 'No refund needed for free content');
    }

    try {
      final result = await _firestore.runTransaction<SpendResult>((
        transaction,
      ) async {
        final userRef = _firestore.collection('users').doc(_uid);
        final userDoc = await transaction.get(userRef);

        if (!userDoc.exists || userDoc.data() == null) {
          return SpendResult(success: false, message: 'User not found');
        }

        final data = userDoc.data()!;
        final coinBalance = (data['coin_balance'] as num?)?.toInt() ?? 0;
        final coinsSpentTotal =
            (data['coins_spent_total'] as num?)?.toInt() ?? 0;

        final newBalance = coinBalance + cost;
        final newSpentTotal = (coinsSpentTotal - cost) < 0 ? 0 : (coinsSpentTotal - cost);

        transaction.update(userRef, {
          'coin_balance': newBalance,
          'coins_spent_total': newSpentTotal,
        });

        final transactionsRef = userRef.collection('transactions');
        final transactionDoc = {
          'type': 'bonus',
          'amount': cost,
          'description': 'Refund for failed ${contentType.displayName}: $contentId',
          'reference_id': contentId,
          'created_at': Timestamp.now(),
        };
        transaction.set(transactionsRef.doc(), transactionDoc);

        await _setLocal('coin_balance', newBalance);

        return SpendResult(
          success: true,
          message: 'Refunded $cost coins',
          newBalance: newBalance,
        );
      });

      return result;
    } catch (e) {
      Logger.error('Error refunding content coins', e);
      return SpendResult(success: false, message: 'Error: $e');
    }
  }

  // --- Bonus Methods (Task 3.6) ---

  /// Claim starter bonus (150 coins on onboarding completion)
  /// Uses Cloud Function to bypass Firestore security rules that block client-side coin writes.
  Future<BonusResult> claimStarterBonus() async {
    if (LocalMode.enabled) {
      return BonusResult(
        success: true,
        message: 'Starter bonus active (local mode)',
        coinsAwarded: LocalMode.defaultCoins,
        newBalance: LocalMode.defaultCoins,
      );
    }
    if (_uid == null) {
      return BonusResult(success: false, message: 'User not authenticated');
    }

    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('claimBonus')
          .call({'bonusType': 'starter'});

      final data = result.data as Map<String, dynamic>;
      final success = data['success'] as bool? ?? false;
      final message = data['message'] as String? ?? '';
      final coinsAwarded = data['coinsAwarded'] as int?;
      final newBalance = data['newBalance'] as int?;

      // Update local cache if successful
      if (success && newBalance != null) {
        await _setLocal('coin_balance', newBalance);
      }

      return BonusResult(
        success: success,
        message: message,
        coinsAwarded: coinsAwarded,
        newBalance: newBalance,
        alreadyClaimed: message.contains('already claimed'),
      );
    } catch (e) {
      Logger.error('Error claiming starter bonus', e);
      // Check if it's an "already claimed" error from the cloud function
      final errorString = e.toString();
      if (errorString.contains('already claimed') ||
          errorString.contains('already-exists')) {
        return BonusResult(
          success: false,
          message: 'Starter bonus already claimed',
          alreadyClaimed: true,
        );
      }
      return BonusResult(success: false, message: 'Error: $e');
    }
  }



  /// Generic helper to award coins (e.g., level-up or achievement bonuses).
  ///
  /// - Creates a `bonus` transaction with the given description and optional referenceId.
  /// - Updates `coin_balance` and `coins_earned_total`.
  Future<BonusResult> awardCoins(
    int amount,
    String description, {
    String? referenceId,
    String? userId,
  }) async {
    final uid = userId ?? _uid;
    if (uid == null) {
      return BonusResult(success: false, message: 'User not authenticated');
    }

    if (amount <= 0) {
      return BonusResult(success: false, message: 'Amount must be positive');
    }

    try {
      final result = await _firestore.runTransaction<BonusResult>((
        transaction,
      ) async {
        final userRef = _firestore.collection('users').doc(uid);
        final userDoc = await transaction.get(userRef);

        if (!userDoc.exists || userDoc.data() == null) {
          return BonusResult(success: false, message: 'User not found');
        }

        final data = userDoc.data()!;
        final currentBalance = (data['coin_balance'] as num?)?.toInt() ?? 0;
        final coinsEarnedTotal =
            (data['coins_earned_total'] as num?)?.toInt() ?? 0;
        final newBalance = currentBalance + amount;

        transaction.update(userRef, {
          'coin_balance': newBalance,
          'coins_earned_total': coinsEarnedTotal + amount,
        });

        final transactionsRef = userRef.collection('transactions');
        final transactionDoc = {
          'type': TransactionType.bonus.value,
          'amount': amount,
          'description': description,
          'reference_id': referenceId,
          'created_at': Timestamp.now(),
        };
        transaction.set(transactionsRef.doc(), transactionDoc);

        return BonusResult(
          success: true,
          message: 'Awarded $amount coins',
          coinsAwarded: amount,
          newBalance: newBalance,
        );
      });

      // Update local cache if successful
      if (result.success && result.newBalance != null) {
        await _setLocal('coin_balance', result.newBalance);
      }

      return result;
    } catch (e) {
      Logger.error('Error awarding coins', e);
      return BonusResult(success: false, message: 'Error: $e');
    }
  }

  // --- Initialize User Coin Fields ---

  /// Initialize coin-related fields for a new user
  /// Called during user registration
  Future<void> initializeUserCoinFields({String? userId}) async {
    final uid = userId ?? _uid;
    if (uid == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .set({
            'coin_balance': 0,
            'coins_earned_total': 0,
            'coins_spent_total': 0,
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      Logger.error('Error initializing user coin fields', e);
    }
  }

  /// Clear local cache (useful for logout or testing)
  Future<void> clearCache() async {
    _memoryCache.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      // Clear all coin-related cached keys
      final keysToRemove = prefs
          .getKeys()
          .where((k) => k.contains('coin_balance'))
          .toList();
      for (final key in keysToRemove) {
        await prefs.remove(key);
      }
    } catch (e) {
      Logger.error('Error clearing cache', e);
    }
  }

  /// Reset memory cache only (for testing)
  @visibleForTesting
  static void resetMemoryCache() {
    _memoryCache.clear();
  }

  /// Get active subscription details for the current user
  Future<
      ({
        bool isSubscriber,
        String tier,
        String status,
        DateTime? periodEnd,
        bool autoRenewing
      })> getSubscriptionInfo() async {
    if (_uid == null) {
      return (
        isSubscriber: false,
        tier: 'free',
        status: 'none',
        periodEnd: null,
        autoRenewing: false,
      );
    }

    try {
      final doc = await _firestore.collection('users').doc(_uid).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final isSub = (data['isSubscriber'] as bool?) ?? false;
        final tier = (data['subscriptionTier'] as String?) ??
            ((data['subscription'] as Map<String, dynamic>?)?['tier'] as String?) ??
            'free';
        final status = (data['subscriptionStatus'] as String?) ??
            ((data['subscription'] as Map<String, dynamic>?)?['status'] as String?) ??
            'none';
        final periodEndTimestamp = (data['periodEnd'] as Timestamp?) ??
            ((data['subscription'] as Map<String, dynamic>?)?['current_period_end'] as Timestamp?);
        final autoRenew = (data['autoRenewing'] as bool?) ??
            (status == 'active');

        return (
          isSubscriber: isSub,
          tier: tier,
          status: status,
          periodEnd: periodEndTimestamp?.toDate(),
          autoRenewing: autoRenew,
        );
      }
    } catch (e) {
      Logger.error('Error fetching subscription info', e);
    }

    return (
      isSubscriber: false,
      tier: 'free',
      status: 'none',
      periodEnd: null,
      autoRenewing: false,
    );
  }
}
