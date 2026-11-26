import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:Badya/config/app_constants.dart';
import 'package:Badya/services/app_review_prompt_service.dart';
import 'package:Badya/services/streak_completion_handler.dart';
import 'package:Badya/config/local_mode.dart';
import 'package:Badya/utils/logger.dart';

import 'level_service.dart';

enum LessonType { rolePlay, storyWeaver, echoChamber, wordSmith }

class AnalysisResult {
  final String userPerformanceSummary;
  final String languageLevel;
  final int understandingPercentage;
  final int expressionPercentage;
  final int communicationPercentage;
  final Map<String, int> wordScores;
  final int score;
  final String feedback;

  AnalysisResult({
    required this.userPerformanceSummary,
    required this.languageLevel,
    required this.understandingPercentage,
    required this.expressionPercentage,
    required this.communicationPercentage,
    required this.wordScores,
    this.score = 0,
    this.feedback = '',
  });

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    // word_scores is now a List[{word, score}] from the backend
    // (changed from Dict to avoid Gemini additionalProperties schema error).
    // We convert it back to Map<String, int> so all downstream logic is unchanged.
    Map<String, int> parsedWordScores = {};
    final rawWordScores = json['word_scores'];
    if (rawWordScores is List) {
      for (final entry in rawWordScores) {
        if (entry is Map) {
          final word = entry['word']?.toString();
          final score = (entry['score'] as num?)?.toInt();
          if (word != null && score != null) {
            parsedWordScores[word] = score;
          }
        }
      }
    } else if (rawWordScores is Map) {
      // Fallback: handle legacy Map format gracefully
      parsedWordScores = rawWordScores.map(
        (k, v) => MapEntry(k.toString(), (v as num).toInt()),
      );
    }

    return AnalysisResult(
      userPerformanceSummary: json['user_performance_summary'] ?? '',
      languageLevel: json['language_level'] ?? '',
      understandingPercentage: json['understanding_percentage'] ?? 0,
      expressionPercentage: json['expression_percentage'] ?? 0,
      communicationPercentage: json['communication_percentage'] ?? 0,
      wordScores: parsedWordScores,
      score: (json['score'] as num?)?.toInt() ?? 0,
      feedback: json['feedback'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_performance_summary': userPerformanceSummary,
      'language_level': languageLevel,
      'understanding_percentage': understandingPercentage,
      'expression_percentage': expressionPercentage,
      'communication_percentage': communicationPercentage,
      'word_scores': wordScores,
      'score': score,
      'feedback': feedback,
      'timestamp': FieldValue.serverTimestamp(),
    };
  }
}

class ScoreService {
  static FirebaseFirestore? _firestoreOverride;
  static FirebaseAuth? _authOverride;

  static FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;
  static FirebaseAuth get _auth => _authOverride ?? FirebaseAuth.instance;

  static String? get _uid =>
      LocalMode.enabled ? LocalMode.guestUid : _auth.currentUser?.uid;

  @visibleForTesting
  static set firestoreInstance(FirebaseFirestore instance) {
    _firestoreOverride = instance;
    _resetStreakCache();
  }

  @visibleForTesting
  static set authInstance(FirebaseAuth instance) {
    _authOverride = instance;
    _resetStreakCache();
  }

  /// Clears the in-memory streak cache (single-flight future, TTL entry,
  /// last-known value). Called when the injected instances change so tests
  /// and account switches never reuse a stale result.
  static void _resetStreakCache() {
    _streakCacheUid = null;
    _streakCacheAt = null;
    _streakCacheValue = null;
    _streakInFlight = null;
    _streakInFlightUid = null;
    _streakGeneration = 0;
  }

  static Future<int> getScore(String language) async {
    if (_uid == null) return 0;
    try {
      final doc = await _firestore.collection('users').doc(_uid).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        // Read from language_xp (per-language accumulated XP)
        final langXp = data['language_xp'] as Map<String, dynamic>?;
        if (langXp != null && langXp.containsKey(language)) {
          return (langXp[language] as num).toInt();
        }
      }
    } catch (e) {
      Logger.error('Error getting score', e);
    }
    return 0;
  }

  /// Saves a per-language XP score atomically to `language_xp[language]`.
  ///
  /// Note: Under normal operation XP is accumulated incrementally via
  /// `saveLessonScore` → `_updateLanguageXp`. This method overwrites the
  /// per-language bucket with the absolute value provided, so use with care.
  static Future<void> saveScore(
    String language,
    int score, {
    String? userId,
  }) async {
    final uid = userId ?? _uid;
    if (uid == null) return;
    try {
      final userRef = _firestore.collection('users').doc(uid);

      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(userRef);
        if (!snapshot.exists) return;

        final data = snapshot.data() as Map<String, dynamic>;
        final langXp = Map<String, dynamic>.from(data['language_xp'] ?? {});
        langXp[language] = score;

        transaction.update(userRef, {
          'language_xp': langXp,
          'last_updated': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      Logger.error('Error saving score', e);
    }
  }

  static Future<int> getTotalXP() async {
    if (_uid == null) return 0;
    try {
      final doc = await _firestore.collection('users').doc(_uid).get();
      if (doc.exists && doc.data() != null) {
        return _totalXpFromData(doc.data()!);
      }
    } catch (e) {
      Logger.error('Error getting total XP', e);
    }
    return 0;
  }

  /// Total-XP math shared by [getTotalXP] and [xpSnapshotStream]: the max
  /// of the per-language sum and the legacy `total_xp` field.
  ///
  /// Tolerant of loosely-typed document data (fake Firestore stores nested
  /// maps as `Map<dynamic, dynamic>`) so it can never throw mid-stream.
  static int _totalXpFromData(Map<String, dynamic> data) {
    // Read from language_xp (per-language accumulated XP)
    final sumLangXp = _languageXpFromData(data).values.fold<int>(
      0,
      (acc, v) => acc + v,
    );
    final totalXpRaw = data['total_xp'];
    final totalXp = totalXpRaw is num ? totalXpRaw.toInt() : 0;
    return max(sumLangXp, totalXp);
  }

  /// Per-language XP buckets — the same source [getScore] reads.
  /// Never throws: a non-map value yields an empty map and non-numeric
  /// bucket values count as 0.
  static Map<String, int> _languageXpFromData(Map<String, dynamic> data) {
    final langXp = data['language_xp'];
    if (langXp is! Map) return {};
    return langXp.map(
      (k, v) => MapEntry(k.toString(), v is num ? v.toInt() : 0),
    );
  }

  /// Live snapshot of the user's XP + streak fields. Emits the current
  /// state on subscribe and again as soon as any write lands on the user
  /// document (lesson XP, mini-game XP, streak updates) — the XP
  /// equivalent of `CoinService.listenToBalance`, so screens like Home and
  /// Profile update the moment XP is awarded, without a manual refresh.
  ///
  /// Errors are logged and dropped (never rethrown) so a transient read
  /// failure can't crash UI listeners; Firestore resumes the stream.
  static Stream<({int totalXp, int streak, Map<String, int> languageXp})>
  xpSnapshotStream([String? userId]) {
    final uid = userId ?? _uid;
    final empty = (totalXp: 0, streak: 0, languageXp: <String, int>{});
    if (uid == null) return Stream.value(empty);
    return _firestore
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((doc) {
          final data = doc.data();
          if (data == null) return empty;
          final streakRaw = data['streak'];
          return (
            totalXp: _totalXpFromData(data),
            streak: streakRaw is num ? streakRaw.toInt() : 0,
            languageXp: _languageXpFromData(data),
          );
        })
        .handleError((Object e) {
          Logger.error('Error streaming XP snapshot', e);
        });
  }

  static Future<String> getNativeLanguage() async {
    if (_uid == null) return 'Arabic';
    try {
      final doc = await _firestore.collection('users').doc(_uid).get();
      if (doc.exists && doc.data() != null) {
        return doc.data()!['native_language'] as String? ?? 'Arabic';
      }
    } catch (e) {
      Logger.error('Error getting native language', e);
    }
    return 'Arabic';
  }

  static Future<void> saveNativeLanguage(String language) async {
    if (_uid == null) return;
    try {
      await _firestore
          .collection('users')
          .doc(_uid)
          .set({
            'native_language': language,
            'last_updated': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      Logger.error('Error saving native language', e);
    }
  }

  static Future<int> getStreak([String? userId]) async {
    final uid = userId ?? _uid;
    if (uid == null) return 0;
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        return (doc.data()!['streak'] as num?)?.toInt() ?? 0;
      }
    } catch (e) {
      Logger.error('Error getting streak', e);
    }
    return 0;
  }

  static Future<void> saveStreak(int streak, {String? userId}) async {
    final uid = userId ?? _uid;
    if (uid == null) return;
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .set({
            'streak': streak,
            'last_updated': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      Logger.error('Error saving streak', e);
    }
  }

  // ── Session-scoped streak cache ────────────────────────────────────────
  // refreshStreak() runs at app startup and on home/profile loads. The
  // single-flight guard collapses concurrent calls into one recompute, the
  // TTL avoids recomputing on every screen visit, and the last-known value
  // is returned (never persisted) when reads fail, e.g. while offline.
  static const Duration _streakRefreshInterval = Duration(minutes: 10);
  static String? _streakCacheUid;
  static DateTime? _streakCacheAt;
  static int? _streakCacheValue;
  static Future<int>? _streakInFlight;
  static String? _streakInFlightUid;
  static int _streakGeneration = 0;

  /// Recompute the current streak from `daily_activity` data and persist it.
  ///
  /// A day qualifies if `xp_earned >= [AppConstants.dailyStreakXpGoal]`.
  /// The streak is the number of consecutive qualifying days ending **today
  /// or yesterday** (grace period): a user who practiced yesterday but hasn't
  /// practiced yet today keeps their streak; it only resets after a full
  /// missed day.
  ///
  /// Call this from user-facing surfaces (app startup, home, profile) so a
  /// missed day clears the stored streak even when the user opens the app
  /// without completing a lesson.
  ///
  /// Note: `daily_activity` docs are bucketed by **UTC** date (see
  /// [_updateDailyActivity]); this method uses the same UTC day.
  ///
  /// [force] bypasses the session cache — pass it right after a
  /// `daily_activity` write (see [_updateDailyActivity]) so a newly
  /// qualifying day is always recomputed.
  ///
  /// Returns the fresh streak value (also persisted via [saveStreak]). If a
  /// read fails (e.g. the app is offline), the last known value is returned
  /// WITHOUT persisting anything — a streak computed from failed reads must
  /// never overwrite the user's real streak.
  static Future<int> refreshStreak({String? userId, bool force = false}) {
    final uid = userId ?? _uid;
    if (uid == null) return Future.value(0);

    // Single-flight: concurrent callers share one recompute — but only for
    // the SAME user, so an in-flight recompute from a previous account can
    // never leak its result to a different user.
    final inFlight = _streakInFlight;
    if (!force && inFlight != null && _streakInFlightUid == uid) {
      return inFlight;
    }

    // TTL: within a session, don't recompute more often than necessary.
    if (!force &&
        _streakCacheUid == uid &&
        _streakCacheAt != null &&
        _streakCacheValue != null &&
        DateTime.now().difference(_streakCacheAt!) < _streakRefreshInterval) {
      return Future.value(_streakCacheValue);
    }

    final generation = ++_streakGeneration;
    final future = _recomputeStreak(uid, generation);
    _streakInFlight = future;
    _streakInFlightUid = uid;
    future.whenComplete(() {
      if (_streakInFlight == future) {
        _streakInFlight = null;
        _streakInFlightUid = null;
      }
    });
    return future;
  }

  static Future<int> _recomputeStreak(String uid, int generation) async {
    try {
      final nowUtc = DateTime.now().toUtc();
      final today = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);

      // Fetch the past 60 days in a single range query instead of N
      // sequential point reads (Optimization 3.5).
      final cutoff = today.subtract(const Duration(days: 60));
      final snapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('daily_activity')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff))
          .get();

      // Build a set of qualifying date IDs from the returned docs.
      final qualifyingDates = <String>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final xpEarned = (data['xp_earned'] as num?)?.toInt() ?? 0;
        if (xpEarned >= AppConstants.dailyStreakXpGoal) {
          qualifyingDates.add(doc.id); // doc.id is 'YYYY-MM-DD'
        }
      }

      // Helper: check if a UTC date's formatted ID is in the qualifying set.
      bool qualifies(DateTime d) => qualifyingDates.contains(_formatDateId(d));

      // Grace period: the streak may end at today OR yesterday.
      DateTime? start;
      if (qualifies(today)) {
        start = today;
      } else if (qualifies(today.subtract(const Duration(days: 1)))) {
        start = today.subtract(const Duration(days: 1));
      }

      if (start == null) {
        return _finishStreakRefresh(uid, generation, 0);
      }

      // Walk back while days qualify; stop at the first non-qualifying
      // day or the cutoff boundary (60 days).
      int streak = 0;
      var day = start;
      for (int i = 0; i < 60; i++) {
        if (!qualifies(day)) break;
        streak++;
        day = day.subtract(const Duration(days: 1));
      }

      return _finishStreakRefresh(uid, generation, streak);
    } catch (e) {
      Logger.error('Error recomputing streak', e);
      return _lastKnownStreak(uid);
    }
  }

  /// Persists + caches a successful recompute — but only when [generation]
  /// is still the latest. A slower, older recompute must never overwrite a
  /// fresher value (out-of-order write guard for concurrent refreshes).
  static Future<int> _finishStreakRefresh(
    String uid,
    int generation,
    int streak,
  ) async {
    if (generation == _streakGeneration) {
      await saveStreak(streak, userId: uid);
      _streakCacheUid = uid;
      _streakCacheAt = DateTime.now();
      _streakCacheValue = streak;
    }
    return streak;
  }

  /// Fallback used when reads fail: the last known value for this user, else
  /// the stored value. Never persists anything.
  static Future<int> _lastKnownStreak(String uid) async {
    if (_streakCacheUid == uid && _streakCacheValue != null) {
      return _streakCacheValue!;
    }
    return getStreak(uid);
  }



  /// Fetch the days of a given month on which the user earned at
  /// least [AppConstants.dailyStreakXpGoal] XP.
  ///
  /// When [year] and [month] are omitted, the current local month is used.
  /// Returns day-of-month integers, used to render real activity history in
  /// [ConsistencyCalendar].
  static Future<Set<int>> getActiveActivityDaysForCurrentMonth([
    String? userId,
    int? year,
    int? month,
  ]) async {
    final uid = userId ?? _uid;
    if (uid == null) return {};
    try {
      final now = DateTime.now();
      final targetYear = year ?? now.year;
      final targetMonth = month ?? now.month;
      final monthStartUtc = DateTime.utc(targetYear, targetMonth, 1);
      final monthEndUtc = DateTime.utc(targetYear, targetMonth + 1, 1);

      final snapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('daily_activity')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStartUtc))
          .where('date', isLessThan: Timestamp.fromDate(monthEndUtc))
          .get();

      final activeDays = <int>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final xpEarned = (data['xp_earned'] as num?)?.toInt() ?? 0;
        if (xpEarned < AppConstants.dailyStreakXpGoal) continue;
        final ts = data['date'] as Timestamp?;
        if (ts == null) continue;
        activeDays.add(ts.toDate().toLocal().day);
      }
      return activeDays;
    } catch (e) {
      Logger.error('Error fetching active activity days', e);
      return {};
    }
  }

  /// Returns the set of months (as `DateTime` with only year+month meaningful)
  /// in which the user has at least one qualifying day of activity.
  ///
  /// Used by [ConsistencyCalendar] to disable navigation arrows when the
  /// user is at the earliest or latest month with activity.
  static Future<Set<DateTime>> getAvailableMonths([
    String? userId,
  ]) async {
    final uid = userId ?? _uid;
    if (uid == null) return {};
    try {
      // Fetch all qualifying daily_activity docs (small, bounded by user's
      // total active days). Group by year+month.
      final snapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('daily_activity')
          .get();

      final months = <DateTime>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final xpEarned = (data['xp_earned'] as num?)?.toInt() ?? 0;
        if (xpEarned < AppConstants.dailyStreakXpGoal) continue;
        final ts = data['date'] as Timestamp?;
        if (ts == null) continue;
        final date = ts.toDate().toLocal();
        months.add(DateTime(date.year, date.month));
      }
      return months;
    } catch (e) {
      Logger.error('Error fetching available months', e);
      return {};
    }
  }

  // --- New Logic for Score Calculation & Analysis ---

  static int calculateLessonScore(AnalysisResult result, LessonType type) {
    if (result.wordScores.isEmpty &&
        result.score == 0 &&
        result.understandingPercentage == 0 &&
        result.expressionPercentage == 0 &&
        result.communicationPercentage == 0) {
      return 0;
    }

    // Average of word scores
    double wordScoreAvg = 0;
    if (result.wordScores.isNotEmpty) {
      double total = 0;
      result.wordScores.forEach((_, score) => total += score);
      wordScoreAvg = total / result.wordScores.length;
    }

    switch (type) {
      case LessonType.storyWeaver:
        return (result.understandingPercentage * 0.50 +
                result.expressionPercentage * 0.30 +
                result.communicationPercentage * 0.20)
            .round();

      case LessonType.echoChamber:
        return (result.expressionPercentage * 0.40 +
                result.understandingPercentage * 0.30 +
                result.communicationPercentage * 0.30)
            .round();

      case LessonType.rolePlay:
        return (result.communicationPercentage * 0.50 +
                result.expressionPercentage * 0.30 +
                result.understandingPercentage * 0.20)
            .round();

      case LessonType.wordSmith:
        return wordScoreAvg.round();
    }
  }

  /// Calculate the combined score for a single part of imported content.
  ///
  /// [partProgress] — 0.0-1.0 consumption progress (scroll or watch %)
  /// [lessonScore] — Score from calculateLessonScore() after lesson paths completed
  ///
  /// Formula: (partProgress × 50) + (lessonScore × 50)
  /// Returns 0-100 integer.
  static int calculateCombinedProgressScore({
    required double partProgress,
    required int lessonScore,
  }) {
    // partProgress (0-1) contributes up to 50 points.
    // lessonScore (0-100) contributes up to 50 points (× 0.5).
    // Final range: 0-100.
    return ((partProgress * 50) + (lessonScore * 0.5)).round();
  }

  static Future<void> saveLessonScore(
    String userId,
    String topicId,
    String language,
    String lessonType,
    int score, {
    Map<String, int>? wordScores,
    bool isImported = false, // NEW — distinguishes imported from AI-generated
    String? contentId, // NEW — user_content doc ID for cross-referencing
  }) async {
    try {
      final docId = '${topicId}_$language';
      final docRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('progress')
          .doc(docId);

      // Read previous lesson score for idempotent XP + activity updates.
      int previousLessonScore = 0;
      bool hadPreviousScore = false;

      try {
        final existing = await docRef.get();
        if (existing.exists && existing.data() != null) {
          final existingData = existing.data() as Map<String, dynamic>;
          final existingLessons =
              existingData['lessons'] as Map<String, dynamic>? ?? {};
          if (existingLessons.containsKey(lessonType)) {
            final raw = existingLessons[lessonType];
            if (raw is num) {
              previousLessonScore = raw.toInt();
              hadPreviousScore = true;
            }
          }
        }
      } catch (e) {
        Logger.error('Error reading existing lesson score', e);
      }

      final data = {
        'id': topicId,
        'language': language,
        'lessons.$lessonType': score,
        'last_updated': FieldValue.serverTimestamp(),
      };

      if (isImported && contentId != null) {
        data['content_type'] = 'imported';
        data['content_id'] = contentId;
      }

      if (wordScores != null && wordScores.isNotEmpty) {
        data['word_scores'] = wordScores;
      }

      await docRef
          .update(data)
          .timeout(const Duration(seconds: 10))
          .catchError((e) async {
        if (e is TimeoutException) return;
        // If document doesn't exist, create it with set(merge: true).
        final initialData = {
          'id': topicId,
          'language': language,
          'lessons': {lessonType: score},
          'last_updated': FieldValue.serverTimestamp(),
        };
        if (isImported && contentId != null) {
          initialData['content_type'] = 'imported';
          initialData['content_id'] = contentId;
        }
        if (wordScores != null && wordScores.isNotEmpty) {
          initialData['word_scores'] = wordScores;
        }
        await docRef
            .set(initialData, SetOptions(merge: true))
            .timeout(const Duration(seconds: 10));
      });

      // Also update lesson_progress in the per-part progress doc for imported content
      if (isImported && contentId != null) {
        final partPrefix = topicId.lastIndexOf('_part_');
        if (partPrefix >= 0) {
          final orderIndexStr = topicId.substring(partPrefix + 6);
          final orderIndex = int.tryParse(orderIndexStr);
          if (orderIndex != null) {
            final partProgressRef = _firestore
                .collection('user_content')
                .doc(contentId)
                .collection('progress')
                .doc(orderIndex.toString());
            await partProgressRef
                .set({
                  'lesson_progress.$lessonType': true,
                  'updated_at': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true))
                .timeout(const Duration(seconds: 10));
          }
        }
      }

      // After saving lesson score, update topic score (avg of lessons)
      await _updateTopicScore(userId, topicId, language);

      // XP calculation & level integration:
      // XP = max(20, lessonScore) × XP multiplier (per lesson type)
      // To make this idempotent across retries, only award the *difference*
      // between the new XP value for this lesson and any previously stored
      // XP value for the same (topicId, language, lessonType).
      final previousXp = previousLessonScore > 0
          ? _calculateXpDelta(previousLessonScore, lessonType)
          : 0;
      final currentXp = _calculateXpDelta(score, lessonType);
      final rawDelta = currentXp - previousXp;

      // Do not decrease XP if the new score is lower; only grant positive diff.
      final xpDelta = rawDelta > 0 ? rawDelta : 0;

      // Count a completed lesson only the first time this specific
      // (topicId, language, lessonType) combination is stored.
      final lessonsDelta = hadPreviousScore ? 0 : 1;

      if (xpDelta > 0) {
        final crossed = await LevelService.addXP(userId, xpDelta);
        await AppReviewPromptService.instance
            .noteReviewThresholdCrossed(crossed);
        // Also increment the per-language XP bucket so getScore() and
        // getTotalXP() reflect the same source of truth.
        await _updateLanguageXp(userId, language, xpDelta);
      }
      if (xpDelta != 0 || lessonsDelta != 0) {
        await _updateDailyActivity(userId, language, xpDelta, lessonsDelta);
      }

    } catch (e) {
      Logger.error('Error saving lesson score', e);
    }
  }

  /// Compute XP delta from a lesson score and type.
  /// - Base = max(20, score)
  /// - Multiplier depends on lesson type:
  ///   - word_smith → 1.0
  ///   - story_weaver → 1.5
  ///   - echo_chamber → 1.8
  ///   - role_master → 1.8
  ///   - default → 1.0
  static int _calculateXpDelta(int rawScore, String lessonType) {
    // If the lesson score is 0 or below, do not award any XP at all.
    if (rawScore <= 0) return 0;

    final base = rawScore;
    double multiplier;
    switch (lessonType) {
      case 'word_smith':
        multiplier = 0.4;
        break;
      case 'story_weaver':
        multiplier = 0.75;
        break;
      case 'echo_chamber':
        multiplier = 0.7;
        break;
      case 'role_master':
        multiplier = 0.7;
        break;
      default:
        multiplier = 1.0;
    }
    return (base * multiplier).round();
  }

  /// Update `users/{uid}/daily_activity/{YYYY-MM-DD}` with lesson + XP stats.
  static Future<void> _updateDailyActivity(
    String userId,
    String language,
    int xpDelta,
    int lessonsDelta,
  ) async {
    try {
      final nowUtc = DateTime.now().toUtc();
      final dateOnly = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
      final id = _formatDateId(dateOnly);

      final docRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('daily_activity')
          .doc(id);

      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);

        int lessonsCompleted = 0;
        int xpEarned = 0;
        Map<String, dynamic> byLanguage = {};

        if (snapshot.exists && snapshot.data() != null) {
          final data = snapshot.data() as Map<String, dynamic>;
          lessonsCompleted = (data['lessons_completed'] as num?)?.toInt() ?? 0;
          xpEarned = (data['xp_earned'] as num?)?.toInt() ?? 0;
          byLanguage = Map<String, dynamic>.from(data['by_language'] ?? {});
        }

        lessonsCompleted += lessonsDelta;
        xpEarned += xpDelta;

        final langData = Map<String, dynamic>.from(byLanguage[language] ?? {});
        final langLessons =
            (langData['lessons_completed'] as num?)?.toInt() ?? 0;
        final langXp = (langData['xp_earned'] as num?)?.toInt() ?? 0;

        byLanguage[language] = {
          'lessons_completed': langLessons + lessonsDelta,
          'xp_earned': langXp + xpDelta,
        };

        transaction.set(docRef, {
          'date': Timestamp.fromDate(dateOnly),
          'lessons_completed': lessonsCompleted,
          'xp_earned': xpEarned,
          'by_language': byLanguage,
        });
      });

      // After updating daily activity, recompute the user's streak based
      // on XP earned per day. A day only counts towards the streak if the
      // user earned at least [AppConstants.dailyStreakXpGoal] XP on that date. force: the daily_activity
      // write just landed, so the session cache must be bypassed. Run it in
      // the background — recomputing an N-day streak costs N+3 reads and
      // must not block the lesson-completion path.
      unawaited(refreshStreak(userId: userId, force: true));

      final todaySnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('daily_activity')
          .doc(id)
          .get();

      if (todaySnapshot.exists) {
        final data = todaySnapshot.data();
        final xpEarned = (data?['xp_earned'] as num?)?.toInt() ?? 0;
        if (xpEarned >= AppConstants.dailyStreakXpGoal) {
          await StreakCompletionHandler.onStreakCompleted();
        }
      }
    } catch (e) {
      Logger.error('Error updating daily activity', e);
    }
  }

  static String _formatDateId(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }



  static Future<void> _updateTopicScore(
    String userId,
    String topicId,
    String language,
  ) async {
    final docId = '${topicId}_$language';
    final docRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('progress')
        .doc(docId);

    final snapshot = await docRef.get();
    if (!snapshot.exists) return;

    final data = snapshot.data() as Map<String, dynamic>;
    final lessons = data['lessons'] as Map<String, dynamic>? ?? {};

    // Topic score is the average of its 4 lesson scores
    final lessonKeys = [
      'word_smith',
      'story_weaver',
      'echo_chamber',
      'role_master',
    ];
    double totalScore = 0;

    for (final key in lessonKeys) {
      totalScore += (lessons[key] as num?)?.toDouble() ?? 0.0;
    }

    int topicScore = (totalScore / 4.0).round();

    await docRef
        .update({
          'topic_score': topicScore,
          'last_updated': FieldValue.serverTimestamp(),
        })
        .timeout(const Duration(seconds: 10));

    // Sync topic_score back to user_content.progress for AI-generated content
    // so the topic card progress bar reflects actual lesson completion.
    // Imported content uses _syncOverallProgress() instead (handles per-part progress).
    if (!topicId.contains('_part_')) {
      try {
        final normalizedProgress = (topicScore / 100.0).clamp(0.0, 1.0);
        await _firestore
            .collection('user_content')
            .doc(topicId)
            .update({
              'progress': normalizedProgress,
              'updated_at': FieldValue.serverTimestamp(),
            })
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        Logger.warn('Failed to sync topic_score to user_content.progress for $topicId: $e');
      }
    }
  }

  static Future<void> initializeTopicProgress(
    String userId,
    String topicId,
    String language,
  ) async {
    final docId = '${topicId}_$language';
    final docRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('progress')
        .doc(docId);

    final snapshot = await docRef.get();
    if (!snapshot.exists) {
      // Document doesn't exist, create it with all lessons at 0
      await docRef
          .set({
            'id': topicId,
            'topic_id': topicId, // Added to ensure topic_id is stored
            'language': language,
            'lessons': {
              'word_smith': 0,
              'story_weaver': 0,
              'echo_chamber': 0,
              'role_master': 0,
            },
            'topic_score': 0,
            'last_updated': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 10));
    } else {
      // Document exists, check if all lessons are present
      final data = snapshot.data() as Map<String, dynamic>;
      final lessons = Map<String, dynamic>.from(data['lessons'] ?? {});
      bool updated = false;

      final expectedLessons = [
        'word_smith',
        'story_weaver',
        'echo_chamber',
        'role_master',
      ];
      for (final lesson in expectedLessons) {
        if (!lessons.containsKey(lesson)) {
          lessons[lesson] = 0;
          updated = true;
        }
      }

      if (updated) {
        await docRef
            .update({
              'lessons': lessons,
              'last_updated': FieldValue.serverTimestamp(),
            })
            .timeout(const Duration(seconds: 10));
        await _updateTopicScore(userId, topicId, language);
      }
    }
  }

  /// Atomically increments `language_xp[language]` in the user document by
  /// [xpDelta]. This is the canonical per-language XP bucket read by
  /// [getScore] and summed by [getTotalXP].
  static Future<void> _updateLanguageXp(
    String userId,
    String language,
    int xpDelta,
  ) async {
    if (xpDelta <= 0) return;
    try {
      final userRef = _firestore.collection('users').doc(userId);
      await userRef
          .update({
            'language_xp.$language': FieldValue.increment(xpDelta),
            'last_updated': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 10))
          .catchError((e) async {
            if (e is TimeoutException) return;
            // Initialize language_xp if the field doesn't exist yet
            await userRef
                .set({
                  'language_xp': {language: xpDelta},
                  'last_updated': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true))          .timeout(const Duration(seconds: 10));
      });
    } catch (e) {
      Logger.error('Error updating language XP for $language', e);
    }
  }

  /// Awards XP earned from a mini-game (e.g. Word Unscramble) after a
  /// correct answer, keeping every XP surface in sync:
  /// - [LevelService.addXP] — `total_xp` + `level` (+ level-up coin bonus)
  /// - [_updateLanguageXp] — per-language bucket read by getScore/getTotalXP
  /// - [_updateDailyActivity] — daily activity + streak progress
  ///
  /// Errors are logged and swallowed so a failed write never interrupts
  /// gameplay.
  static Future<void> awardMiniGameXp(
    String language,
    int xpDelta, {
    String? userId,
  }) async {
    if (xpDelta <= 0) return;
    final uid = userId ?? _uid;
    if (uid == null) return;
    try {
      final crossed = await LevelService.addXP(uid, xpDelta);
      await AppReviewPromptService.instance.noteReviewThresholdCrossed(crossed);
      await _updateLanguageXp(uid, language, xpDelta);
      await _updateDailyActivity(uid, language, xpDelta, 0);
    } catch (e) {
      Logger.error('Error awarding mini-game XP', e);
    }
  }

  static Future<void> saveAnalysisResult(
    String userId,
    String topicId,
    String language,
    AnalysisResult result,
  ) async {
    try {
      // Skip saving if there's no actual performance data (e.g. word_smith mode).
      final hasPerformanceData =
          result.userPerformanceSummary.isNotEmpty ||
          result.languageLevel.isNotEmpty;
      if (!hasPerformanceData) return;

      // Update latest summary and language level on user profile for easy access
      // Stored per-language so studying multiple languages doesn't overwrite.
      await _firestore
          .collection('users')
          .doc(userId)
          .set({
            'last_performance_summary.$language': result.userPerformanceSummary,
            'last_language_level.$language': result.languageLevel,
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));

      // Also store percentages, summary, and language level in the topic progress document
      final docId = '${topicId}_$language';
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('progress')
          .doc(docId)
          .set({
            'communication_percentage': result.communicationPercentage,
            'expression_percentage': result.expressionPercentage,
            'understanding_percentage': result.understandingPercentage,
            'user_performance_summary': result.userPerformanceSummary,
            'language_level': result.languageLevel,
            'last_updated': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      Logger.error('Error saving analysis result', e);
    }
  }

  /// Updates per-word scores in the **topics** document using flat dotted
  /// keys (e.g. `words.{word}.score`).
  ///
  /// @deprecated This creates Format B (flat dotted keys) which conflicts
  /// with Format A (nested map) written by [VocabReviewService]. Word scores
  /// are already stored in the `progress/{topicId}_{language}` document's
  /// `word_scores` field via [saveLessonScore]. SRS state is managed by
  /// [VocabReviewService.submitSessionRatings] and
  /// [VocabReviewService.submitTopicSessionRatings].
  ///
  /// This method is kept as a no-op stub to avoid breaking any remaining
  /// callers during migration. It will be removed in a future cleanup pass.
  @Deprecated(
    'Word scores are already stored via saveLessonScore() wordScores param. '
    'SRS state is managed by VocabReviewService. This method creates a conflicting '
    'storage format and will be removed.',
  )
  static Future<void> updateWordPriority(
    String userId,
    String topicId,
    String language,
    Map<String, int> wordScores,
  ) async {
    // No-op: flat dotted keys (Format B) conflict with nested maps (Format A).
    // Word scores are persisted via saveLessonScore(wordScores: ...) to the
    // progress/{topicId}_{language} document, and SRS state is written by
    // VocabReviewService.submitSessionRatings() / submitTopicSessionRatings().
    Logger.info(
      'ScoreService.updateWordPriority is deprecated and is now a no-op. '
      'Word scores are saved via saveLessonScore().',
    );
  }

  /// Reads a per-language string from a user-profile map field
  /// (e.g. `last_performance_summary.English`). Legacy single-string values
  /// are ignored so they are not shown for every language.
  static String? _perLanguageProfileString(dynamic field, String language) {
    if (field is! Map) return null;
    final value = field[language];
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Latest AI analysis stored on a progress doc for [language], by
  /// [last_updated].
  static Future<Map<String, dynamic>?> _latestAnalysisFromProgress(
    String userId,
    String language,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('progress')
          .where('language', isEqualTo: language)
          .get();

      Timestamp? bestTime;
      String? bestSummary;
      String? bestLevel;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final ts = data['last_updated'] as Timestamp?;
        if (ts == null) continue;

        final summary =
            (data['user_performance_summary'] as String?)?.trim() ?? '';
        final level = (data['language_level'] as String?)?.trim() ?? '';
        if (summary.isEmpty && level.isEmpty) continue;

        if (bestTime == null || ts.compareTo(bestTime) > 0) {
          bestTime = ts;
          bestSummary = summary.isEmpty ? null : summary;
          bestLevel = level.isEmpty ? null : level;
        }
      }

      if (bestSummary == null && bestLevel == null) return null;
      return {
        'user_performance_summary': bestSummary ?? '',
        'language_level': bestLevel ?? '',
      };
    } catch (e) {
      Logger.error('Error getting progress analysis for $language', e);
      return null;
    }
  }

  static Future<String?> getLatestPerformanceSummary(
    String userId,
    String language,
  ) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists && doc.data() != null) {
        final fromProfile = _perLanguageProfileString(
          doc.data()!['last_performance_summary'],
          language,
        );
        if (fromProfile != null) return fromProfile;
      }
      final fromProgress = await _latestAnalysisFromProgress(userId, language);
      final summary =
          (fromProgress?['user_performance_summary'] as String?)?.trim();
      if (summary != null && summary.isNotEmpty) return summary;
    } catch (e) {
      Logger.error('Error getting performance summary', e);
    }
    return null;
  }

  /// Fetches the latest language_level assessment from the user's profile.
  /// This is used by chat/voice agents to adapt their teaching style.
  static Future<String?> getLatestLanguageLevel(
    String userId,
    String language,
  ) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists && doc.data() != null) {
        final fromProfile = _perLanguageProfileString(
          doc.data()!['last_language_level'],
          language,
        );
        if (fromProfile != null) return fromProfile;
      }
      final fromProgress = await _latestAnalysisFromProgress(userId, language);
      final level = (fromProgress?['language_level'] as String?)?.trim();
      if (level != null && level.isNotEmpty) return level;
    } catch (e) {
      Logger.error('Error getting language level', e);
    }
    return null;
  }

  /// DEPRECATED: Vocabulary collection is being phased out.
  /// This method is kept as a no-op stub to avoid breaking callers
  /// during migration. It will be removed in a future cleanup pass.
  static Future<List<String>> getRecentVocabulary(
    String userId,
    String language,
  ) async {
    // Vocabulary collection has been deprecated.
    return [];
  }

  /// Update the combined score stored in a per-part progress doc.
  /// Called after lesson paths complete for a part.
  static Future<void> updatePartScore({
    required String contentId,
    required int orderIndex,
    required int combinedScore,
  }) async {
    try {
      final progressRef = _firestore
          .collection('user_content')
          .doc(contentId)
          .collection('progress')
          .doc(orderIndex.toString());

      await progressRef
          .update({
            'score': combinedScore,
            'updated_at': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      Logger.error(
        'Error updating part score for $contentId part $orderIndex',
        e,
      );
    }
  }

  /// Call this after saveLessonScore() to persist the combined score
  /// back to the per-part progress doc for imported content.
  ///
  /// [topicId] format: "{contentId}_part_{orderIndex}"
  /// This method parses the contentId and orderIndex from the topicId.
  static Future<void> syncPartScoreAfterLesson({
    required String userId,
    required String topicId,
    required String language,
  }) async {
    // Only process if this is an imported content topic
    if (!topicId.contains('_part_')) return;

    // Parse: "{contentId}_part_{orderIndex}" → contentId, orderIndex
    final partPrefix = topicId.lastIndexOf('_part_');
    if (partPrefix < 0) return;

    final contentId = topicId.substring(0, partPrefix);
    final orderIndexStr = topicId.substring(partPrefix + 6); // skip '_part_'
    final orderIndex = int.tryParse(orderIndexStr);
    if (orderIndex == null) return;

    // Read the part progress to get the consumption %
    try {
      final progressDoc = await _firestore
          .collection('user_content')
          .doc(contentId)
          .collection('progress')
          .doc(orderIndex.toString())
          .get();

      if (!progressDoc.exists) return;
      final partProgress =
          (progressDoc.data()?['last_position'] as num?)?.toDouble() ?? 0.0;

      // Read the topic score (avg of 4 lesson types) from the progress doc
      final topicScore = await getTopicScore(userId, topicId, language);

      // Combine: (partProgress × 50) + (topicScore × 50)
      final combinedScore = calculateCombinedProgressScore(
        partProgress: partProgress,
        lessonScore: topicScore,
      );

      await updatePartScore(
        contentId: contentId,
        orderIndex: orderIndex,
        combinedScore: combinedScore,
      );
    } catch (e) {
      Logger.error('Error syncing part score for $topicId', e);
    }
  }

  /// Fetches the topic score (average of all 4 lesson types) for a given topic.
  static Future<int> getTopicScore(
    String userId,
    String topicId,
    String language,
  ) async {
    try {
      final docId = '${topicId}_$language';
      final doc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('progress')
          .doc(docId)
          .get();
      if (doc.exists && doc.data() != null) {
        return (doc.data()!['topic_score'] as num?)?.toInt() ?? 0;
      }
    } catch (e) {
      Logger.error('Error getting topic score', e);
    }
    return 0;
  }

  /// Fetches the complete last analysis result (all fields) from Firestore.
  /// Returns a map with keys: user_performance_summary, language_level,
  /// understanding_percentage, expression_percentage, communication_percentage,
  /// word_scores. Returns null if no previous analysis exists.
  static Future<Map<String, dynamic>?> getLatestFullAnalysis(
    String userId,
    String language,
  ) async {
    try {
      String? summary;
      String? level;

      final doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        summary = _perLanguageProfileString(
          data['last_performance_summary'],
          language,
        );
        level = _perLanguageProfileString(
          data['last_language_level'],
          language,
        );
      }

      if (summary == null && level == null) {
        return _latestAnalysisFromProgress(userId, language);
      }

      return {
        'user_performance_summary': summary ?? '',
        'language_level': level ?? '',
      };
    } catch (e) {
      Logger.error('Error getting full analysis', e);
      return null;
    }
  }
}
