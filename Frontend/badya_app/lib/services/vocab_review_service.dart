import 'dart:async';

import 'package:Badya/config/local_mode.dart';
import 'package:Badya/models/word_review_state.dart';
import 'package:Badya/models/review_stats.dart';
import 'package:Badya/utils/logger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SRS-powered vocabulary review service.
///
/// Manages the SM-2 spaced repetition algorithm and Firestore operations for
/// both **strange words** (`users/{uid}/strange_words/{language}`) and
/// **topic vocabulary** (`users/{uid}/topics/{topicId}_{language}`).
///
/// ## Scope Constants
///
/// Use [scopeStrangeWords] for words the user manually marked as difficult.
/// Use [scopeTopic] for vocabulary extracted from a specific topic lesson.
class VocabReviewService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  VocabReviewService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  // ─── Scope Constants ───────────────────────────────────────────────────

  static const String scopeStrangeWords = 'strange_words';
  static const String scopeTopic = 'topic';

  // ─── Helpers ───────────────────────────────────────────────────────────

  String? get _uid =>
      _auth.currentUser?.uid ?? (_useLocalStorage ? LocalMode.guestUid : null);

  bool get _useLocalStorage =>
      LocalMode.enabled || (kDebugMode && _auth.currentUser == null);

  /// Resolves the Firestore document reference for the given scope.
  DocumentReference _docRef(String userId, String scope, String scopeId) {
    switch (scope) {
      case scopeStrangeWords:
        return _firestore
            .collection('users')
            .doc(userId)
            .collection('strange_words')
            .doc(scopeId);
      case scopeTopic:
        return _firestore
            .collection('users')
            .doc(userId)
            .collection('topics')
            .doc(scopeId);
      default:
        throw ArgumentError(
          'Unknown scope: $scope. Use scopeStrangeWords or scopeTopic.',
        );
    }
  }

  /// Reads the `words` field from a Firestore document snapshot.
  /// Returns `null` if the document doesn't exist or has no `words` field.
  ///
  /// Supports three storage formats:
  ///   1. **Nested** — `words` is a `Map<String, Map<String, dynamic>>`
  ///   2. **List**   — `words` is a `List<String>` (legacy bare-word list)
  ///   3. **Flat**   — dotted keys like `words.apple.score` at document root
  ///      (legacy `set(merge: true)` behavior)
  Future<dynamic> _readWordsField(
    String userId,
    String scope,
    String scopeId,
  ) async {
    final snapshot = await _docRef(userId, scope, scopeId).get();
    if (!snapshot.exists) return null;

    final data = snapshot.data() as Map<String, dynamic>?;
    if (data == null) return null;

    final words = data['words'];

    // 1. Nested format — words is a Map directly
    if (words is Map) return words;

    // 2. Legacy List<String> format
    if (words is List) return words;

    // 3. Fallback: flat dotted keys like "words.apple.score"
    return extractWordsFromFlatKeys(data);
  }

  /// Parses flat dotted keys (e.g. `words.apple.score`) into a nested Map:
  /// `{apple: {score: 0}}`. Returns `null` if no matching keys are found.
  ///
  /// Handles word names containing dots (e.g. `Mr. Smith` → `Mr. Smith`)
  /// by splitting only on the first `.` after the `words.` prefix.
  /// Extracts flat dotted Firestore keys (e.g. `words.apple.score`) into
  /// a nested Map: `{apple: {score: 0}}`. Returns `null` if no matching
  /// keys are found.
  ///
  /// Public so it can be reused by other parts of the app (e.g. VoiceChatPage)
  /// that need to parse legacy flat-key formats.
  static Map<String, Map<String, dynamic>>? extractWordsFromFlatKeys(
    Map<String, dynamic> data,
  ) {
    const prefix = 'words.';
    final Map<String, Map<String, dynamic>> result = {};
    bool found = false;

    for (final key in data.keys) {
      if (!key.startsWith(prefix)) continue;
      found = true;

      // "words.apple.score" → remove prefix → "apple.score"
      final rest = key.substring(prefix.length);
      final dotIndex = rest.indexOf('.');
      if (dotIndex == -1) continue; // malformed: just "words.apple" w/o field

      final word = rest.substring(0, dotIndex);
      final field = rest.substring(dotIndex + 1);

      result.putIfAbsent(word, () => {});
      result[word]![field] = data[key];
    }

    return found ? result : null;
  }

  /// Reads current words, applies [mutator], writes back as a proper nested
  /// Map. Handles migration from flat dotted keys and legacy [List] format
  /// automatically — any write to a legacy doc migrates it to the nested
  /// Map format.
  Future<void> _modifyWords({
    required String uid,
    required String scope,
    required String scopeId,
    required void Function(Map<String, dynamic> words) mutator,
  }) async {
    final current = await _readWordsField(uid, scope, scopeId);
    late final Map<String, dynamic> words;

    if (current is Map) {
      words = Map<String, dynamic>.from(current);
    } else if (current is List) {
      // Legacy List<String> → auto-migrate to Map with default SRS state
      final now = DateTime.now();
      words = {};
      for (final item in current) {
        final word = item.toString();
        words[word] = WordReviewState(word: word, addedAt: now).toFirestore();
      }
    } else {
      words = <String, dynamic>{};
    }

    mutator(words);

    try {
      await _docRef(uid, scope, scopeId)
          .set({'words': words, 'last_updated': FieldValue.serverTimestamp()})
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      Logger.error('VocabReviewService._modifyWords: error', e);
    }
  }

  /// Shortcut: builds the scope ID for topic scope from topicId + language.
  static String topicScopeId(String topicId, String language) =>
      '${topicId}_$language';

  // ─── Read: Get All Words ─────────────────────────────────────────────

  /// Fetches all words with their SRS state from a given scope.
  ///
  /// Returns a list of [WordReviewState] objects. The scope can be
  /// [scopeStrangeWords] or [scopeTopic].
  ///
  /// If the underlying document stores `words` as a `List<String>` (legacy
  /// format), each word is returned as a **new** [WordReviewState] with
  /// default SRS values.
  Future<List<WordReviewState>> getAllWords({
    required String scope,
    required String scopeId,
    String? userId,
  }) async {
    final uid = userId ?? _uid;
    if (uid == null) return [];

    if (_useLocalStorage) {
      final prefs = await SharedPreferences.getInstance();
      final key = 'local_vocab_${uid}_${scope}_$scopeId';
      final stored = prefs.getStringList(key) ?? const <String>[];
      return stored.map((w) => WordReviewState(word: w)).toList();
    }

    try {
      final words = await _readWordsField(uid, scope, scopeId);

      if (words is Map) {
        // New format: Map of word -> {score, ef, interval, ...}
        return words.entries.map((entry) {
          return WordReviewState.fromFirestore(
            entry.key.toString(),
            Map<String, dynamic>.from(entry.value as Map),
          );
        }).toList();
      } else if (words is List) {
        // Legacy format: List<String> — wrap each with default SRS state
        return words.map((w) => WordReviewState(word: w.toString())).toList();
      }
    } catch (e) {
      Logger.error(
        'VocabReviewService.getAllWords: error for $scope/$scopeId',
        e,
      );
    }
    return [];
  }

  // ─── Read: Get Due Words (SM-2 Selection) ────────────────────────────

  /// Selects up to [maxCards] words due for review, sorted by priority.
  ///
  /// Priority order:
  ///   1. Forgotten words (`last_rating == 0`) — most urgent
  ///   2. New words (never reviewed)
  ///   3. Overdue words (review past due)
  ///   4. Words due soon (within 24h)
  ///
  /// [scope] — Use [scopeStrangeWords] or [scopeTopic] constants.
  /// [scopeId] — Language name for strange_words (e.g. `'English'`), or
  ///             `${topicId}_${language}` for topic scope.
  Future<List<WordReviewState>> getDueWords({
    required String scope,
    required String scopeId,
    String? userId,
    int maxCards = 10,
  }) async {
    final allWords = await getAllWords(
      scope: scope,
      scopeId: scopeId,
      userId: userId,
    );
    if (allWords.isEmpty) return [];

    // Sort by priority: forgotten > new > overdue > soon > rest
    final sorted = List<WordReviewState>.from(allWords);
    sorted.sort((a, b) {
      int priority(WordReviewState w) {
        if (w.lastRating == 0) return 10; // Forgotten — highest priority
        if (w.isNew) return 15; // Never reviewed
        if (w.isDue) return 20; // Overdue
        if (w.isSoon) return 30; // Due within 24h
        return 100; // Not due yet — lowest priority
      }

      final pa = priority(a);
      final pb = priority(b);
      if (pa != pb) return pa.compareTo(pb);

      // Within same priority, sort by oldest next_review_at first
      if (a.nextReviewAt != null && b.nextReviewAt != null) {
        return a.nextReviewAt!.compareTo(b.nextReviewAt!);
      }
      if (a.nextReviewAt == null && b.nextReviewAt == null) return 0;
      return a.nextReviewAt == null
          ? -1
          : 1; // Null (new) goes before scheduled
    });

    // Take only words that are actually due or coming due soon
    final dueWords = sorted
        .where((w) => w.isNew || w.isDue || w.isSoon)
        .take(maxCards)
        .toList();

    return dueWords;
  }

  /// Convenience overload: fetches due words from the **strange_words** scope.
  Future<List<WordReviewState>> getDueStrangeWords(
    String language, {
    String? userId,
    int maxCards = 10,
  }) {
    return getDueWords(
      scope: scopeStrangeWords,
      scopeId: language,
      userId: userId,
      maxCards: maxCards,
    );
  }

  // ─── Read: Get Stats ─────────────────────────────────────────────────

  /// Computes [ReviewStats] for the given language's strange words.
  Future<ReviewStats> getStats(String language, {String? userId}) async {
    final words = await getAllWords(
      scope: scopeStrangeWords,
      scopeId: language,
      userId: userId,
    );
    return ReviewStats.fromWordList(words);
  }

  // ─── Read: Get Due Count ─────────────────────────────────────────────

  /// Returns the number of words due for review (new + overdue) in the
  /// strange_words scope for [language].
  Future<int> getDueCount(String language, {String? userId}) async {
    final stats = await getStats(language, userId: userId);
    return stats.dueCount;
  }

  // ─── Write: Submit Single Rating ─────────────────────────────────────

  /// Applies SM-2 to a single word in the **strange_words** scope and
  /// persists the updated SRS state to Firestore.
  Future<void> submitRating({
    required String word,
    required String language,
    required int rating,
    String? userId,
  }) async {
    final uid = userId ?? _uid;
    if (uid == null) return;

    final currentState = await _fetchSingleWord(uid, language, word);
    final newState = currentState.applyRating(rating.clamp(0, 3));
    await _writeWordState(uid, scopeStrangeWords, language, newState);
  }

  // ─── Write: Batch Submit Session Ratings ─────────────────────────────

  /// Batch-submits ratings from a completed voice session to the
  /// **strange_words** scope.
  ///
  /// Each entry in [wordRatings] maps a word to its SRS rating (0-3).
  /// The ratings are normally derived from the analyze agent's word_scores:
  ///   `(word_score ~/ 25).clamp(0, 3)`
  Future<void> submitSessionRatings({
    required String language,
    required Map<String, int> wordRatings,
    String? userId,
  }) async {
    final uid = userId ?? _uid;
    if (uid == null || wordRatings.isEmpty) return;

    await _modifyWords(
      uid: uid,
      scope: scopeStrangeWords,
      scopeId: language,
      mutator: (wordsMap) {
        for (final entry in wordRatings.entries) {
          final word = entry.key;
          final rating = entry.value.clamp(0, 3);

          final currentState = wordsMap[word] is Map
              ? WordReviewState.fromFirestore(
                  word,
                  Map<String, dynamic>.from(wordsMap[word] as Map),
                )
              : WordReviewState(word: word);
          final newState = currentState.applyRating(rating);
          wordsMap[word] = newState.toFirestore();
        }
      },
    );
  }

  // ─── Write: Add Word ─────────────────────────────────────────────────

  /// Adds a new word to the **strange_words** scope with default SRS state.
  /// If the word already exists, this is a no-op (merge preserves existing).
  Future<void> addWord({
    required String word,
    required String language,
    String? definition,
    String? exampleSentence,
    String? userId,
  }) async {
    final uid = userId ?? _uid;
    if (uid == null || word.trim().isEmpty) return;

    final newState = WordReviewState(
      word: word.trim(),
      addedAt: DateTime.now(),
      definition: definition,
      exampleSentence: exampleSentence,
    );

    await _writeWordState(uid, scopeStrangeWords, language, newState);
  }

  /// Adds multiple words at once — reads existing words, appends new unique
  /// ones, and writes back as a proper nested Map.
  Future<void> addWords({
    required List<String> words,
    required String language,
    String? userId,
  }) async {
    final uid = userId ?? _uid;
    if (uid == null) return;

    final uniqueWords = words
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty)
        .toSet()
        .toList();
    if (uniqueWords.isEmpty) return;

    final now = DateTime.now();
    await _modifyWords(
      uid: uid,
      scope: scopeStrangeWords,
      scopeId: language,
      mutator: (wordsMap) {
        for (final word in uniqueWords) {
          if (!wordsMap.containsKey(word)) {
            wordsMap[word] = WordReviewState(
              word: word,
              addedAt: now,
            ).toFirestore();
          }
        }
      },
    );
  }

  // ─── Write: Delete Word ──────────────────────────────────────────────

  /// Removes a word and its SRS state from the **strange_words** scope.
  Future<void> deleteWord(
    String word,
    String language, {
    String? userId,
  }) async {
    return deleteWords([word], language, userId: userId);
  }

  /// Removes multiple words and their SRS state — reads current words,
  /// removes them, and writes back as a proper nested Map.
  Future<void> deleteWords(
    List<String> words,
    String language, {
    String? userId,
  }) async {
    final uid = userId ?? _uid;
    if (uid == null || words.isEmpty) return;

    await _modifyWords(
      uid: uid,
      scope: scopeStrangeWords,
      scopeId: language,
      mutator: (wordsMap) {
        for (final word in words) {
          wordsMap.remove(word);
        }
      },
    );
  }

  // ─── Write: Edit Word (rename) ──────────────────────────────────────

  /// Renames a word preserving its full SRS state.
  ///
  /// Reads the current SRS state for [oldWord], removes the old key, and
  /// inserts it under [newWord]. This is effectively a "rename" operation
  /// that preserves all SRS data (score, ef, interval, reviews, etc.).
  ///
  /// If [oldWord] doesn't exist, this is a no-op. If [newWord] already
  /// exists, its state will be overwritten.
  Future<void> editWord({
    required String oldWord,
    required String newWord,
    required String language,
    String? userId,
  }) async {
    final uid = userId ?? _uid;
    if (uid == null || oldWord.trim().isEmpty || newWord.trim().isEmpty) return;
    final trimmed = newWord.trim();
    if (oldWord == trimmed) return;

    await _modifyWords(
      uid: uid,
      scope: scopeStrangeWords,
      scopeId: language,
      mutator: (wordsMap) {
        final state = wordsMap.remove(oldWord);
        if (state != null) {
          wordsMap[trimmed] = state;
        }
      },
    );
  }

  // ─── Write: Mark as Learned ──────────────────────────────────────────

  /// Marks a word as "learned" (mastered) by setting its interval to 365 days.
  Future<void> markAsLearned(
    String word,
    String language, {
    String? userId,
  }) async {
    return markWordsAsLearned([word], language, userId: userId);
  }

  /// Marks multiple words as "learned" (mastered) — reads current state,
  /// sets interval=365 and next_review_at = now + 365 days, writes back.
  Future<void> markWordsAsLearned(
    List<String> words,
    String language, {
    String? userId,
  }) async {
    final uid = userId ?? _uid;
    if (uid == null || words.isEmpty) return;

    await _modifyWords(
      uid: uid,
      scope: scopeStrangeWords,
      scopeId: language,
      mutator: (wordsMap) {
        for (final word in words) {
          final state = wordsMap[word] is Map
              ? Map<String, dynamic>.from(wordsMap[word] as Map)
              : <String, dynamic>{};
          state['interval'] = 365.0;
          state['next_review_at'] = Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 365)),
          );
          state['last_rating'] = 3;
          state['last_reviewed_at'] = Timestamp.fromDate(DateTime.now());
          wordsMap[word] = state;
        }
      },
    );
  }

  // ─── Write: Reset Progress ───────────────────────────────────────────

  /// Resets a word's SRS state to defaults (as if never reviewed).
  Future<void> resetProgress(
    String word,
    String language, {
    String? userId,
  }) async {
    return resetProgressForWords([word], language, userId: userId);
  }

  /// Resets multiple words' SRS state to defaults in a single Firestore write.
  Future<void> resetProgressForWords(
    List<String> words,
    String language, {
    String? userId,
  }) async {
    final uid = userId ?? _uid;
    if (uid == null || words.isEmpty) return;

    final now = DateTime.now();
    await _modifyWords(
      uid: uid,
      scope: scopeStrangeWords,
      scopeId: language,
      mutator: (wordsMap) {
        for (final word in words) {
          wordsMap[word] = WordReviewState(
            word: word,
            addedAt: now,
          ).toFirestore();
        }
      },
    );
  }

  // ─── Write: Add Words to Topic Scope ─────────────────────────────────

  /// Adds new words to a **topic** scope with default SRS state.
  ///
  /// Preserves existing SRS state for words already in the topic document.
  /// This is the topic-scope equivalent of [addWords].
  ///
  /// [topicId] and [language] are combined into a scope ID via [topicScopeId].
  Future<void> addWordsToTopic({
    required String topicId,
    required String language,
    required List<String> words,
    String? userId,
  }) async {
    final uid = userId ?? _uid;
    if (uid == null) return;

    final uniqueWords = words
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty)
        .toSet()
        .toList();
    if (uniqueWords.isEmpty) return;

    final scopeId = topicScopeId(topicId, language);

    if (_useLocalStorage) {
      final prefs = await SharedPreferences.getInstance();
      final key = 'local_vocab_${uid}_${scopeTopic}_$scopeId';
      final existing = prefs.getStringList(key) ?? <String>[];
      final merged = <String>{...existing, ...uniqueWords}.toList();
      await prefs.setStringList(key, merged);
      return;
    }

    final now = DateTime.now();

    await _modifyWords(
      uid: uid,
      scope: scopeTopic,
      scopeId: scopeId,
      mutator: (wordsMap) {
        for (final word in uniqueWords) {
          if (!wordsMap.containsKey(word)) {
            wordsMap[word] = WordReviewState(
              word: word,
              addedAt: now,
            ).toFirestore();
          }
        }
      },
    );
  }

  /// Synchronises the entire word list for a **topic** scope.
  ///
  /// Reads the existing words map, removes any words not in [words], and adds
  /// new words (with default SRS state) that aren't already present.
  /// Existing SRS state for words that remain in the list is preserved.
  ///
  /// This is used by pages that manage the full word list (add, edit, delete)
  /// and need to write the complete set in one operation.
  ///
  /// [topicId] and [language] are combined into a scope ID via [topicScopeId].
  Future<void> syncTopicWords({
    required String topicId,
    required String language,
    required List<String> words,
    String? userId,
  }) async {
    final uid = userId ?? _uid;
    if (uid == null) return;

    final wordsSet = words
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty)
        .toSet();
    final scopeId = topicScopeId(topicId, language);

    if (_useLocalStorage) {
      final prefs = await SharedPreferences.getInstance();
      final key = 'local_vocab_${uid}_${scopeTopic}_$scopeId';
      await prefs.setStringList(key, wordsSet.toList());
      return;
    }

    final now = DateTime.now();

    await _modifyWords(
      uid: uid,
      scope: scopeTopic,
      scopeId: scopeId,
      mutator: (wordsMap) {
        // Remove words not in the new list
        wordsMap.removeWhere((key, _) => !wordsSet.contains(key));
        // Add new words with default SRS state
        for (final word in wordsSet) {
          if (!wordsMap.containsKey(word)) {
            wordsMap[word] = WordReviewState(
              word: word,
              addedAt: now,
            ).toFirestore();
          }
        }
      },
    );
  }

  // ─── Write: Session Ratings for Topic Scope ──────────────────────────

  /// Submits ratings for a **topic** scope (as opposed to [submitSessionRatings]
  /// which operates on the strange_words scope).
  ///
  /// [topicScopeId] should be `${topicId}_${language}`.
  Future<void> submitTopicSessionRatings({
    required String topicScopeId,
    required Map<String, int> wordRatings,
    String? userId,
  }) async {
    final uid = userId ?? _uid;
    if (uid == null || wordRatings.isEmpty) return;

    await _modifyWords(
      uid: uid,
      scope: scopeTopic,
      scopeId: topicScopeId,
      mutator: (wordsMap) {
        for (final entry in wordRatings.entries) {
          final word = entry.key;
          final rating = entry.value.clamp(0, 3);

          final currentState = wordsMap[word] is Map
              ? WordReviewState.fromFirestore(
                  word,
                  Map<String, dynamic>.from(wordsMap[word] as Map),
                )
              : WordReviewState(word: word);
          final newState = currentState.applyRating(rating);
          wordsMap[word] = newState.toFirestore();
        }
      },
    );
  }

  // ─── Get Due Count for Topic Scope ──────────────────────────────────

  /// Returns the number of words due for review in a **topic** scope.
  Future<int> getDueCountForTopic({
    required String topicId,
    required String language,
    String? userId,
  }) async {
    final scopeId = topicScopeId(topicId, language);
    final uid = userId ?? _uid;
    if (uid == null) return 0;

    try {
      final dueWords = await getDueWords(
        scope: scopeTopic,
        scopeId: scopeId,
        userId: uid,
        maxCards: 1000, // Get all due words for count
      );
      return dueWords.length;
    } catch (e) {
      Logger.error('VocabReviewService.getDueCountForTopic: error', e);
      return 0;
    }
  }

  // ─── Topic Scope: Edit Word ─────────────────────────────────────────

  /// Renames a word in a **topic** scope preserving its full SRS state.
  Future<void> editWordInTopic({
    required String oldWord,
    required String newWord,
    required String topicId,
    required String language,
    String? userId,
  }) async {
    final uid = userId ?? _uid;
    if (uid == null || oldWord.trim().isEmpty || newWord.trim().isEmpty) return;
    final trimmed = newWord.trim();
    if (oldWord == trimmed) return;

    final scopeId = topicScopeId(topicId, language);
    await _modifyWords(
      uid: uid,
      scope: scopeTopic,
      scopeId: scopeId,
      mutator: (wordsMap) {
        final state = wordsMap.remove(oldWord);
        if (state != null) {
          wordsMap[trimmed] = state;
        }
      },
    );
  }

  // ─── Topic Scope: Delete Words ──────────────────────────────────────

  /// Removes multiple words from a **topic** scope.
  Future<void> deleteWordsFromTopic({
    required List<String> words,
    required String topicId,
    required String language,
    String? userId,
  }) async {
    final uid = userId ?? _uid;
    if (uid == null || words.isEmpty) return;

    final scopeId = topicScopeId(topicId, language);
    await _modifyWords(
      uid: uid,
      scope: scopeTopic,
      scopeId: scopeId,
      mutator: (wordsMap) {
        for (final word in words) {
          wordsMap.remove(word);
        }
      },
    );
  }

  // ─── Topic Scope: Mark as Learned ───────────────────────────────────

  /// Marks multiple words as \"learned\" (mastered) in a **topic** scope.
  Future<void> markWordsAsLearnedInTopic({
    required List<String> words,
    required String topicId,
    required String language,
    String? userId,
  }) async {
    final uid = userId ?? _uid;
    if (uid == null || words.isEmpty) return;

    final scopeId = topicScopeId(topicId, language);
    await _modifyWords(
      uid: uid,
      scope: scopeTopic,
      scopeId: scopeId,
      mutator: (wordsMap) {
        for (final word in words) {
          final state = wordsMap[word] is Map
              ? Map<String, dynamic>.from(wordsMap[word] as Map)
              : <String, dynamic>{};
          state['interval'] = 365.0;
          state['next_review_at'] = Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 365)),
          );
          state['last_rating'] = 3;
          state['last_reviewed_at'] = Timestamp.fromDate(DateTime.now());
          wordsMap[word] = state;
        }
      },
    );
  }

  // ─── Topic Scope: Reset Progress ────────────────────────────────────

  /// Resets multiple words' SRS state to defaults in a **topic** scope.
  Future<void> resetProgressForWordsInTopic({
    required List<String> words,
    required String topicId,
    required String language,
    String? userId,
  }) async {
    final uid = userId ?? _uid;
    if (uid == null || words.isEmpty) return;

    final scopeId = topicScopeId(topicId, language);

    if (_useLocalStorage) {
      final prefs = await SharedPreferences.getInstance();
      final key = 'local_vocab_${uid}_${scopeTopic}_$scopeId';
      final existing = prefs.getStringList(key) ?? <String>[];
      final merged = <String>{...existing, ...words}.toList();
      await prefs.setStringList(key, merged);
      return;
    }

    final now = DateTime.now();
    await _modifyWords(
      uid: uid,
      scope: scopeTopic,
      scopeId: scopeId,
      mutator: (wordsMap) {
        for (final word in words) {
          wordsMap[word] = WordReviewState(
            word: word,
            addedAt: now,
          ).toFirestore();
        }
      },
    );
  }

  // ─── Internal: Fetch Single Word ─────────────────────────────────────

  Future<WordReviewState> _fetchSingleWord(
    String uid,
    String language,
    String word,
  ) async {
    try {
      final words = await _readWordsField(uid, scopeStrangeWords, language);
      if (words is Map) {
        final wordData = words[word];
        if (wordData is Map) {
          return WordReviewState.fromFirestore(
            word,
            Map<String, dynamic>.from(wordData),
          );
        }
      }
    } catch (e) {
      Logger.error('VocabReviewService._fetchSingleWord: error', e);
    }
    return WordReviewState(word: word);
  }

  // ─── Internal: Write Single Word State ───────────────────────────────

  /// Writes a single word's SRS state using a proper nested Map.
  Future<void> _writeWordState(
    String uid,
    String scope,
    String scopeId,
    WordReviewState state,
  ) async {
    await _modifyWords(
      uid: uid,
      scope: scope,
      scopeId: scopeId,
      mutator: (words) {
        words[state.word] = state.toFirestore();
      },
    );
  }

  // ─── Local Caching (SharedPreferences) ───────────────────────────────

  /// Cache key template for SRS word states.
  static String _cacheKey(String uid, String language) =>
      'srs_cache_${uid}_$language';

  /// Caches word SRS states locally so they survive app restarts.
  Future<void> cacheWordStates(
    String language, {
    String? userId,
    List<WordReviewState>? states,
  }) async {
    final uid = userId ?? _uid;
    if (uid == null) return;

    try {
      final data = states != null ? WordReviewState.listToJson(states) : null;

      if (data != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_cacheKey(uid, language), data);
      }
    } catch (e) {
      Logger.warn('VocabReviewService.cacheWordStates: $e');
    }
  }

  /// Loads cached SRS word states from SharedPreferences.
  Future<List<WordReviewState>?> loadCachedStates(
    String language, {
    String? userId,
  }) async {
    final uid = userId ?? _uid;
    if (uid == null) return null;

    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_cacheKey(uid, language));
      if (json != null && json.isNotEmpty) {
        return WordReviewState.listFromJson(json);
      }
    } catch (e) {
      Logger.warn('VocabReviewService.loadCachedStates: $e');
    }
    return null;
  }

  /// Clears the local SRS cache for a given language.
  Future<void> clearCache(String language, {String? userId}) async {
    final uid = userId ?? _uid;
    if (uid == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey(uid, language));
    } catch (e) {
      Logger.warn('VocabReviewService.clearCache: $e');
    }
  }

  // ─── Migration: Legacy List → Map ────────────────────────────────────

  /// Converts a legacy `words: List<String>` document to the new
  /// `words: Map<String, SrsState>` format in-place.
  ///
  /// Call this once per user per language during migration.
  Future<void> migrateListToMap({
    required String language,
    String? userId,
  }) async {
    final uid = userId ?? _uid;
    if (uid == null) return;

    try {
      final words = await _readWordsField(uid, scopeStrangeWords, language);
      if (words is! List) return;

      final wordList = words.cast<String>();
      if (wordList.isEmpty) return;

      final now = DateTime.now();
      final wordsMap = <String, dynamic>{};
      for (final word in wordList) {
        wordsMap[word] = WordReviewState(
          word: word,
          addedAt: now,
        ).toFirestore();
      }

      await _docRef(uid, scopeStrangeWords, language)
          .set({
            'words': wordsMap,
            'last_updated': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));

      Logger.info(
        'VocabReviewService: migrated ${wordList.length} words for $language',
      );
    } catch (e) {
      Logger.error(
        'VocabReviewService.migrateListToMap: error for $language',
        e,
      );
    }
  }

  /// Checks whether a document still uses the legacy List format.
  Future<bool> needsMigration(String language, {String? userId}) async {
    final uid = userId ?? _uid;
    if (uid == null) return false;

    try {
      final words = await _readWordsField(uid, scopeStrangeWords, language);
      return words is List;
    } catch (_) {
      return false;
    }
  }
}
