import 'dart:async';
import 'dart:math';

import 'package:Badya/config/local_mode.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:Badya/utils/logger.dart';

import '../services/coin_service.dart';
import '../config/app_constants.dart';

/// Service responsible for XP → Level math and level-up side effects.
///
/// Follows the static pattern used by `ScoreService` so it can be
/// configured with fake instances in tests.
class LevelService {
  static FirebaseFirestore? _firestoreOverride;
  static FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  @visibleForTesting
  static set firestoreInstance(FirebaseFirestore instance) {
    _firestoreOverride = instance;
  }

  // Allows tests to disable coin awards to avoid touching real Firestore.
  static bool _enableCoinAwards = true;

  @visibleForTesting
  static set enableCoinAwards(bool value) {
    _enableCoinAwards = value;
  }

  /// XP needed for Level N: 50 × (N-1)²
  static int xpForLevel(int level) {
    if (level <= 1) return 0;
    final n = level - 1;
    return 50 * n * n;
  }

  /// Compute level from total XP:
  /// Level = floor(sqrt(XP / 50)) + 1
  static int levelForXp(int totalXp) {
    if (totalXp <= 0) return 1;
    final lvl = sqrt(totalXp / 50.0);
    final result = lvl.floor() + 1;
    return result < 1 ? 1 : result;
  }

  /// Compute helper values for UI: xp_for_current_level, xp_for_next_level, xp_to_next_level.
  static ({int xpForCurrentLevel, int xpForNextLevel, int xpToNextLevel})
  xpProgress(int totalXp) {
    final level = levelForXp(totalXp);
    final xpCurrent = xpForLevel(level);
    final xpNext = xpForLevel(level + 1);
    final xpToNext = (xpNext - totalXp).clamp(0, xpNext - xpCurrent);
    return (
      xpForCurrentLevel: xpCurrent,
      xpForNextLevel: xpNext,
      xpToNextLevel: xpToNext,
    );
  }

  /// Add XP to a user, recomputing level and xp_to_next_level.
  ///
  /// - Uses a Firestore transaction for atomic XP updates.
  /// - Returns `true` when total XP crosses above [AppConstants.reviewPromptXpThreshold].
  /// - After a successful transaction, if the user leveled up, awards
  ///   coin bonuses via `CoinService.awardCoins` (outside the XP transaction).
  static Future<bool> addXP(String userId, int deltaXp) async {
    if (deltaXp <= 0) return false;

    int oldLevel = 1;
    int newLevel = 1;
    int newTotalXp = 0;
    var crossedReviewThreshold = false;

    final userRef = _firestore.collection('users').doc(userId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(userRef);
      if (!snapshot.exists) {
        newTotalXp = deltaXp;
        crossedReviewThreshold = AppConstants.crossedReviewPromptThreshold(
          0,
          newTotalXp,
        );
        newLevel = levelForXp(newTotalXp);
        final progress = xpProgress(newTotalXp);
        transaction.set(userRef, {
          'total_xp': newTotalXp,
          'level': newLevel,
          'xp_to_next_level': progress.xpToNextLevel,
          'xp_updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return;
      }

      final data = snapshot.data() as Map<String, dynamic>;
      final currentXp = (data['total_xp'] as num?)?.toInt() ?? 0;
      oldLevel = levelForXp(currentXp);

      newTotalXp = max(0, currentXp + deltaXp);
      crossedReviewThreshold = AppConstants.crossedReviewPromptThreshold(
        currentXp,
        newTotalXp,
      );
      newLevel = levelForXp(newTotalXp);

      final progress = xpProgress(newTotalXp);

      transaction.update(userRef, {
        'total_xp': newTotalXp,
        'level': newLevel,
        'xp_to_next_level': progress.xpToNextLevel,
        'xp_updated_at': FieldValue.serverTimestamp(),
      });
    }).timeout(const Duration(seconds: 10));

    // After XP transaction succeeds, handle level-up coin bonuses.
    if (!_enableCoinAwards) return crossedReviewThreshold;
    if (newLevel <= oldLevel) return crossedReviewThreshold;

    final coinsToAward = _coinsForLevelRange(oldLevel + 1, newLevel);
    if (coinsToAward <= 0) return crossedReviewThreshold;

    try {
      await CoinService().awardCoins(
        coinsToAward,
        'Level $newLevel bonus',
        referenceId: 'level_up_$newLevel',
        userId: userId,
      );
    } catch (e) {
      Logger.error('Error awarding level-up coins', e);
    }

    return crossedReviewThreshold;
  }

  /// Total coins for all levels in [fromLevel, toLevel].
  static int _coinsForLevelRange(int fromLevel, int toLevel) {
    int total = 0;
    for (var lvl = fromLevel; lvl <= toLevel; lvl++) {
      total += _coinsForSingleLevel(lvl);
    }
    return total;
  }

  /// Coin bonus rules:
  /// - Levels 1–5: Level × 15
  /// - Levels 6–15: Level × 12
  /// - Levels 16–30: Level × 10
  /// - Levels 31+: Level × 8
  static int _coinsForSingleLevel(int level) {
    if (level <= 0) return 0;
    if (level <= 5) return level * 15;
    if (level <= 15) return level * 12;
    if (level <= 30) return level * 10;
    return level * 8;
  }

  /// Public helper to expose the coin bonus for a single level to the UI.
  ///
  /// This uses the same rules as `_coinsForSingleLevel` but is safe for
  /// widgets to call when they want to show "Reward: X coins" for a level.
  static int coinsForLevel(int level) {
    return _coinsForSingleLevel(level);
  }

  /// Total coins awarded when leveling up from [oldLevel] to [newLevel].
  ///
  /// This is the same as `_coinsForLevelRange` but exposed publicly so
  /// widgets can show the exact reward amount.
  static int coinsForLevelRange(int oldLevel, int newLevel) {
    if (newLevel <= oldLevel) return 0;
    return _coinsForLevelRange(oldLevel + 1, newLevel);
  }
}
