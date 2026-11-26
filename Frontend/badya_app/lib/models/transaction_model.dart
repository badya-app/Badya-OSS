import 'package:cloud_firestore/cloud_firestore.dart';

/// Transaction types for coin movements
enum TransactionType {
  purchase, // Bought coins with money (IAP)
  bonus, // Received bonus coins (greeting, subscription)
  spend, // Spent coins on content
  sale, // Marketplace sale (future)
  subscription, // Subscription credit / renewal
}

/// Extension to convert TransactionType to/from string for Firestore
extension TransactionTypeExtension on TransactionType {
  String get value {
    switch (this) {
      case TransactionType.purchase:
        return 'purchase';
      case TransactionType.bonus:
        return 'bonus';
      case TransactionType.spend:
        return 'spend';
      case TransactionType.sale:
        return 'sale';
      case TransactionType.subscription:
        return 'subscription';
    }
  }

  static TransactionType fromString(String value) {
    switch (value) {
      case 'purchase':
        return TransactionType.purchase;
      case 'bonus':
        return TransactionType.bonus;
      case 'spend':
        return TransactionType.spend;
      case 'sale':
        return TransactionType.sale;
      case 'subscription':
        return TransactionType.subscription;
      default:
        throw ArgumentError('Unknown transaction type: $value');
    }
  }
}

/// Model for a coin/credit transaction
class CoinTransaction {
  final String id;
  final TransactionType type;
  final int amount;
  final String description;
  final String? referenceId;
  final DateTime createdAt;

  // Purchase-specific fields
  final String? productId;
  final String? storeType;
  final String? storeTransactionId;
  final String? receiptData;
  final DateTime? verifiedAt;

  CoinTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.description,
    this.referenceId,
    required this.createdAt,
    this.productId,
    this.storeType,
    this.storeTransactionId,
    this.receiptData,
    this.verifiedAt,
  });

  /// Create from Firestore document
  factory CoinTransaction.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CoinTransaction(
      id: doc.id,
      type: TransactionTypeExtension.fromString(data['type'] as String),
      amount: (data['amount'] as num).toInt(),
      description: data['description'] as String,
      referenceId: data['reference_id'] as String?,
      createdAt: (data['created_at'] as Timestamp).toDate(),
      productId: data['product_id'] as String?,
      storeType: data['store_type'] as String?,
      storeTransactionId: data['store_transaction_id'] as String?,
      receiptData: data['receipt_data'] as String?,
      verifiedAt: data['verified_at'] != null
          ? (data['verified_at'] as Timestamp).toDate()
          : null,
    );
  }

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    final map = <String, dynamic>{
      'type': type.value,
      'amount': amount,
      'description': description,
      'created_at': Timestamp.fromDate(createdAt),
    };

    if (referenceId != null) map['reference_id'] = referenceId;
    if (productId != null) map['product_id'] = productId;
    if (storeType != null) map['store_type'] = storeType;
    if (storeTransactionId != null) {
      map['store_transaction_id'] = storeTransactionId;
    }
    if (receiptData != null) map['receipt_data'] = receiptData;
    if (verifiedAt != null) {
      map['verified_at'] = Timestamp.fromDate(verifiedAt!);
    }

    return map;
  }

  /// Create a copy with modified fields
  CoinTransaction copyWith({
    String? id,
    TransactionType? type,
    int? amount,
    String? description,
    String? referenceId,
    DateTime? createdAt,
    String? productId,
    String? storeType,
    String? storeTransactionId,
    String? receiptData,
    DateTime? verifiedAt,
  }) {
    return CoinTransaction(
      id: id ?? this.id,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      description: description ?? this.description,
      referenceId: referenceId ?? this.referenceId,
      createdAt: createdAt ?? this.createdAt,
      productId: productId ?? this.productId,
      storeType: storeType ?? this.storeType,
      storeTransactionId: storeTransactionId ?? this.storeTransactionId,
      receiptData: receiptData ?? this.receiptData,
      verifiedAt: verifiedAt ?? this.verifiedAt,
    );
  }
}

/// Content types with their coin costs
enum ContentType {
  wordSmith, // Voice lesson only
  storyWeaver, // Text + chat + 3 images
  echoChamber, // Text + TTS + 5 images + voice
  roleMaster, // Voice session
  thumbnail, // Thumbnail image generation
}

extension ContentTypeExtension on ContentType {
  /// Coin cost for AI-generated content (the default).
  int get coinCost {
    switch (this) {
      case ContentType.wordSmith:
        return 10;
      case ContentType.storyWeaver:
        return 15;
      case ContentType.echoChamber:
        return 30;
      case ContentType.roleMaster:
        return 10;
      case ContentType.thumbnail:
        return 3;
    }
  }

  /// Coin cost for imported content (reduced pricing).
  int get importedCoinCost {
    switch (this) {
      case ContentType.wordSmith:
        return 10;
      case ContentType.storyWeaver:
        return 5;
      case ContentType.echoChamber:
        return 25;
      case ContentType.roleMaster:
        return 10;
      case ContentType.thumbnail:
        return 3;
    }
  }

  /// Get the appropriate cost based on whether the content is imported.
  int costFor({bool isImportedContent = false}) =>
      isImportedContent ? importedCoinCost : coinCost;

  String get displayName {
    switch (this) {
      case ContentType.wordSmith:
        return 'Word Smith';
      case ContentType.storyWeaver:
        return 'Story Weaver';
      case ContentType.echoChamber:
        return 'Echo Chamber';
      case ContentType.roleMaster:
        return 'Role Master';
      case ContentType.thumbnail:
        return 'Thumbnail';
    }
  }
}

/// Result of content access check
class ContentAccessResult {
  final bool canAccess;
  final int cost;
  final String? reason;
  final int? currentBalance;

  ContentAccessResult({
    required this.canAccess,
    required this.cost,
    this.reason,
    this.currentBalance,
  });
}

/// Result of spending coins
class SpendResult {
  final bool success;
  final String message;
  final int? coinsSpent;
  final int? newBalance;
  final bool insufficientFunds;

  SpendResult({
    required this.success,
    required this.message,
    this.coinsSpent,
    this.newBalance,
    this.insufficientFunds = false,
  });
}

/// Result of claiming a bonus
class BonusResult {
  final bool success;
  final String message;
  final int? coinsAwarded;
  final int? newBalance;
  final bool alreadyClaimed;

  BonusResult({
    required this.success,
    required this.message,
    this.coinsAwarded,
    this.newBalance,
    this.alreadyClaimed = false,
  });
}

/// Coin package definitions
class CoinPackage {
  final String productId;
  final int coins;
  final double price;
  final int bonusPercent;

  const CoinPackage({
    required this.productId,
    required this.coins,
    required this.price,
    this.bonusPercent = 0,
  });

  /// Coin packages with updated pricing:
  /// - 200 coins for $4.99 (base rate)
  /// - 500 coins for $10.99 (12% savings for user)
  /// - 1000 coins for $20 (20% savings for user)
  static const List<CoinPackage> packages = [
    // Base package: $4.99 for 200 coins
    CoinPackage(
      productId: 'com.badya.coins_200',
      coins: 200,
      price: 4.99,
      bonusPercent: 0,
    ),
    // Medium package: $10.99 for 500 coins (12% savings)
    CoinPackage(
      productId: 'com.badya.coins_500',
      coins: 500,
      price: 10.99,
      bonusPercent: 12,
    ),
    // Large package: $20 for 1000 coins (20% savings)
    CoinPackage(
      productId: 'com.badya.coins_1000',
      coins: 1000,
      price: 20.00,
      bonusPercent: 20,
    ),
  ];

  /// Get package by product ID
  static CoinPackage? getByProductId(String productId) {
    try {
      return packages.firstWhere((p) => p.productId == productId);
    } catch (_) {
      return null;
    }
  }
}

/// Subscription package definitions
class SubscriptionPackage {
  final String productId;
  final String tier;
  final int coinsPerMonth;
  final double price;
  final int savingsPercent;

  const SubscriptionPackage({
    required this.productId,
    required this.tier,
    required this.coinsPerMonth,
    required this.price,
    this.savingsPercent = 0,
  });

  static const List<SubscriptionPackage> packages = [
    // Prices match the one-time coin packages (no subscription discount)
    SubscriptionPackage(
      productId: 'com.badya.sub_coins_200',
      tier: '200',
      coinsPerMonth: 200,
      price: 4.99,
      savingsPercent: 0,
    ),
    SubscriptionPackage(
      productId: 'com.badya.sub_coins_500',
      tier: '500',
      coinsPerMonth: 500,
      price: 10.99,
      savingsPercent: 0,
    ),
    SubscriptionPackage(
      productId: 'com.badya.sub_coins_1000',
      tier: '1000',
      coinsPerMonth: 1000,
      price: 20.00,
      savingsPercent: 0,
    ),
  ];

  static SubscriptionPackage? getByProductId(String productId) {
    try {
      return packages.firstWhere((p) => p.productId == productId);
    } catch (_) {
      return null;
    }
  }
}

