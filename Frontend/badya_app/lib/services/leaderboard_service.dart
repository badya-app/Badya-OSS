import 'dart:math';

import 'package:Badya/config/local_mode.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:Badya/models/leaderboard_entry.dart';
import 'package:Badya/utils/logger.dart';

/// Service to fetch and manage leaderboard data.
///
/// Queries the `users` collection for public profiles and ranks them
/// across 3 metric categories:
/// - `'xp'`: Overall XP (max of total_xp and sum of language_xp)
/// - `'streak'`: Active streak days
/// - `'language'`: Per-language XP score (expands multi-language learners)
/// Results are cached in memory with a 5-minute TTL.
class LeaderboardService {
  static final LeaderboardService _instance = LeaderboardService._internal();
  factory LeaderboardService() => _instance;
  LeaderboardService._internal();

  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  static FirebaseAuth get _auth => FirebaseAuth.instance;

  static String? get _uid => _auth.currentUser?.uid;

  // In-memory cache: category → (timestamp, entries)
  static final Map<String, _CacheEntry> _cache = {};

  /// Cache TTL: 5 minutes.
  static const Duration _cacheTtl = Duration(minutes: 5);

  /// Valid category names.
  static const List<String> validCategories = [
    'xp',
    'streak',
    'language',
  ];

  /// Returns the top 5 users for the given [category].
  ///
  /// [category] must be one of: 'xp', 'streak', 'language'.
  Future<List<LeaderboardEntry>> getTopUsers(String category) async {
    assert(validCategories.contains(category));

    // Return cached data if still fresh.
    final cached = _cache[category];
    if (cached != null &&
        DateTime.now().difference(cached.timestamp) < _cacheTtl) {
      return cached.entries;
    }

    try {
      // Fetch users, limited to 50 for client-side sorting.
      // In Firestore, where('is_public', isEqualTo: true) excludes documents
      // where 'is_public' does not exist yet. So we query the users collection
      // and filter out documents explicitly set to is_public == false.
      QuerySnapshot<Map<String, dynamic>> snapshot;
      try {
        snapshot = await _firestore
            .collection('users')
            .limit(50)
            .get()
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        // Fallback to is_public filter if rules require it
        snapshot = await _firestore
            .collection('users')
            .where('is_public', isEqualTo: true)
            .limit(50)
            .get()
            .timeout(const Duration(seconds: 10));
      }

      final currentUid = _uid;
      final List<_RawEntry> rawEntries = [];

      for (final doc in snapshot.docs) {
        final data = doc.data();
        // Skip explicitly private profiles
        if (data['is_public'] == false) continue;

        final displayName =
            (data['display_name'] as String?) ?? 'Anonymous';
        final photoUrl = data['photo_url'] as String?;
        final isCurrentUser = doc.id == currentUid;

        if (category == 'xp') {
          // Calculate user's overall XP: max of total_xp and sum of language_xp
          final langXpMap = _extractLanguageXp(data);
          final sumLangXp = langXpMap.values.fold<int>(0, (acc, v) => acc + v);
          final totalXp = _toInt(data['total_xp']);
          final score = max(sumLangXp, totalXp);

          if (score > 0) {
            rawEntries.add(_RawEntry(
              userId: doc.id,
              displayName: displayName,
              photoUrl: photoUrl,
              score: score,
              isCurrentUser: isCurrentUser,
            ));
          }
        } else if (category == 'streak') {
          final streak = _toInt(data['streak']);
          if (streak > 0) {
            rawEntries.add(_RawEntry(
              userId: doc.id,
              displayName: displayName,
              photoUrl: photoUrl,
              score: streak,
              isCurrentUser: isCurrentUser,
            ));
          }
        } else if (category == 'language') {
          final langXpMap = _extractLanguageXp(data);
          for (final entry in langXpMap.entries) {
            final score = entry.value;
            if (score > 0) {
              rawEntries.add(_RawEntry(
                userId: doc.id,
                displayName: displayName,
                photoUrl: photoUrl,
                score: score,
                isCurrentUser: isCurrentUser,
                language: entry.key,
              ));
            }
          }
        }
      }

      // Sort descending by score.
      rawEntries.sort((a, b) => b.score.compareTo(a.score));

      // Take top 5 and assign ranks 1 to 5.
      final top5 = rawEntries.take(5).toList();
      final entries = <LeaderboardEntry>[];
      for (int i = 0; i < top5.length; i++) {
        final raw = top5[i];
        entries.add(LeaderboardEntry(
          userId: raw.userId,
          displayName: raw.displayName,
          photoUrl: raw.photoUrl,
          score: raw.score,
          rank: i + 1,
          isCurrentUser: raw.isCurrentUser,
          language: raw.language,
          subtitle: raw.language,
        ));
      }

      // Cache the result.
      _cache[category] = _CacheEntry(
        timestamp: DateTime.now(),
        entries: entries,
      );

      return entries;
    } catch (e) {
      Logger.error('Error fetching leaderboard for $category', e);
      // Return stale cache if available, otherwise empty list.
      return cached?.entries ?? [];
    }
  }

  /// Clears the in-memory cache, forcing a fresh fetch on next call.
  void clearCache() => _cache.clear();

  /// Extracts per-language XP map safely.
  static Map<String, int> _extractLanguageXp(Map<String, dynamic> data) {
    final langXp = data['language_xp'];
    if (langXp is! Map) return {};
    return langXp.map(
      (k, v) => MapEntry(k.toString(), v is num ? v.toInt() : 0),
    );
  }

  /// Safely converts a dynamic value to int, defaulting to 0.
  static int _toInt(dynamic value) {
    if (value is num) return value.toInt();
    return 0;
  }
}

/// Internal helper for an unsorted leaderboard entry.
class _RawEntry {
  final String userId;
  final String displayName;
  final String? photoUrl;
  final int score;
  final bool isCurrentUser;
  final String? language;

  _RawEntry({
    required this.userId,
    required this.displayName,
    this.photoUrl,
    required this.score,
    required this.isCurrentUser,
    this.language,
  });
}

/// Internal cache wrapper with a timestamp.
class _CacheEntry {
  final DateTime timestamp;
  final List<LeaderboardEntry> entries;

  _CacheEntry({required this.timestamp, required this.entries});
}
