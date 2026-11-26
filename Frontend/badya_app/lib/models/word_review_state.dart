import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Data model for a word's SRS (Spaced Repetition System) state.
///
/// Stored in Firestore as a map within `strange_words/{language}.words.{word}`
/// or `topics/{topicId}_{language}.words.{word}`.
///
/// Fields use camelCase in Dart and snake_case in Firestore.
class WordReviewState {
  /// The word text (e.g. "aberration").
  final String word;

  /// Word accuracy score from the analyze agent (0-100).
  final int score;

  /// Easiness factor [1.3, 3.0], default 2.5.
  final double easinessFactor;

  /// Current interval in days, default 0.0.
  final double interval;

  /// Consecutive correct recalls, default 0.
  final int repetitions;

  /// Next scheduled review; null = never reviewed.
  final DateTime? nextReviewAt;

  /// Timestamp of the last review.
  final DateTime? lastReviewedAt;

  /// Last rating: 0=Forgot, 1=Hard, 2=Good, 3=Easy; null if never rated.
  final int? lastRating;

  /// Lifetime review count.
  final int totalReviews;

  /// Count of "Forgot" ratings.
  final int forgottenCount;

  /// Count of "Easy" ratings.
  final int easyCount;

  /// When the word was added to the review system.
  final DateTime? addedAt;

  /// Optional definition of the word.
  final String? definition;

  /// Optional example sentence for the word.
  final String? exampleSentence;

  const WordReviewState({
    required this.word,
    this.score = 0,
    this.easinessFactor = 2.5,
    this.interval = 0.0,
    this.repetitions = 0,
    this.nextReviewAt,
    this.lastReviewedAt,
    this.lastRating,
    this.totalReviews = 0,
    this.forgottenCount = 0,
    this.easyCount = 0,
    this.addedAt,
    this.definition,
    this.exampleSentence,
  });

  // ─── Factory: from Firestore Map ────────────────────────────────────────

  /// Creates a [WordReviewState] from the Firestore data map stored at
  /// `words.{word}.{field}` inside the parent document.
  factory WordReviewState.fromFirestore(String word, Map<String, dynamic> data) {
    return WordReviewState(
      word: word,
      score: (data['score'] as num?)?.toInt() ?? 0,
      easinessFactor: (data['ef'] as num?)?.toDouble() ?? 2.5,
      interval: (data['interval'] as num?)?.toDouble() ?? 0.0,
      repetitions: (data['repetitions'] as num?)?.toInt() ?? 0,
      nextReviewAt: data['next_review_at'] != null
          ? (data['next_review_at'] as Timestamp).toDate()
          : null,
      lastReviewedAt: data['last_reviewed_at'] != null
          ? (data['last_reviewed_at'] as Timestamp).toDate()
          : null,
      lastRating: (data['last_rating'] as num?)?.toInt(),
      totalReviews: (data['total_reviews'] as num?)?.toInt() ?? 0,
      forgottenCount: (data['forgotten_count'] as num?)?.toInt() ?? 0,
      easyCount: (data['easy_count'] as num?)?.toInt() ?? 0,
      addedAt: data['added_at'] != null
          ? (data['added_at'] as Timestamp).toDate()
          : null,
      definition: data['definition'] as String?,
      exampleSentence: data['example_sentence'] as String?,
    );
  }

  // ─── Convert to Firestore Map ──────────────────────────────────────────

  /// Converts this state to a Firestore-encodable map (snake_case keys).
  Map<String, dynamic> toFirestore() {
    return {
      'score': score,
      'ef': easinessFactor,
      'interval': interval,
      'repetitions': repetitions,
      if (nextReviewAt != null) 'next_review_at': Timestamp.fromDate(nextReviewAt!),
      if (lastReviewedAt != null)
        'last_reviewed_at': Timestamp.fromDate(lastReviewedAt!),
      if (lastRating != null) 'last_rating': lastRating,
      'total_reviews': totalReviews,
      'forgotten_count': forgottenCount,
      'easy_count': easyCount,
      if (addedAt != null) 'added_at': Timestamp.fromDate(addedAt!),
      if (definition != null) 'definition': definition,
      if (exampleSentence != null) 'example_sentence': exampleSentence,
    };
  }

  // ─── To/From JSON (for local caching / serialization) ──────────────────

  Map<String, dynamic> toJson() {
    return {
      'word': word,
      'score': score,
      'ef': easinessFactor,
      'interval': interval,
      'repetitions': repetitions,
      'next_review_at': nextReviewAt?.toIso8601String(),
      'last_reviewed_at': lastReviewedAt?.toIso8601String(),
      'last_rating': lastRating,
      'total_reviews': totalReviews,
      'forgotten_count': forgottenCount,
      'easy_count': easyCount,
      'added_at': addedAt?.toIso8601String(),
      'definition': definition,
      'example_sentence': exampleSentence,
    };
  }

  factory WordReviewState.fromJson(Map<String, dynamic> json) {
    return WordReviewState(
      word: json['word'] as String? ?? '',
      score: (json['score'] as num?)?.toInt() ?? 0,
      easinessFactor: (json['ef'] as num?)?.toDouble() ?? 2.5,
      interval: (json['interval'] as num?)?.toDouble() ?? 0.0,
      repetitions: (json['repetitions'] as num?)?.toInt() ?? 0,
      nextReviewAt: json['next_review_at'] != null
          ? DateTime.tryParse(json['next_review_at'] as String)
          : null,
      lastReviewedAt: json['last_reviewed_at'] != null
          ? DateTime.tryParse(json['last_reviewed_at'] as String)
          : null,
      lastRating: (json['last_rating'] as num?)?.toInt(),
      totalReviews: (json['total_reviews'] as num?)?.toInt() ?? 0,
      forgottenCount: (json['forgotten_count'] as num?)?.toInt() ?? 0,
      easyCount: (json['easy_count'] as num?)?.toInt() ?? 0,
      addedAt: json['added_at'] != null
          ? DateTime.tryParse(json['added_at'] as String)
          : null,
      definition: json['definition'] as String?,
      exampleSentence: json['example_sentence'] as String?,
    );
  }

  /// Encode a list of [WordReviewState] to a JSON string for local caching.
  static String listToJson(List<WordReviewState> states) {
    return jsonEncode(states.map((s) => s.toJson()).toList());
  }

  /// Decode a list of [WordReviewState] from a JSON string.
  static List<WordReviewState> listFromJson(String jsonStr) {
    final list = jsonDecode(jsonStr) as List<dynamic>;
    return list
        .map((e) => WordReviewState.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ─── SM-2: Apply Rating ────────────────────────────────────────────────

  /// Applies the SM-2 algorithm with the given [rating] (0-3) and returns
  /// a new [WordReviewState] with updated SRS fields.
  WordReviewState applyRating(int rating) {
    final clampedRating = rating.clamp(0, 3);

    // SM-2 formula for new EF
    double newEF = easinessFactor +
        (0.1 - (5 - clampedRating) * (0.08 + (5 - clampedRating) * 0.02));
    newEF = newEF.clamp(1.3, 3.0);

    int newReps;
    double newInterval;

    if (clampedRating < 2) {
      // Forgot or Hard — reset repetitions, short interval
      newReps = 0;
      newInterval = 10.0 / (24 * 60); // 10 minutes in days
    } else {
      // Good or Easy — advance
      newReps = repetitions + 1;
      if (newReps == 1) {
        newInterval = 1.0; // 1 day
      } else if (newReps == 2) {
        newInterval = 3.0; // 3 days
      } else {
        newInterval = interval * newEF;
      }
    }

    // Bonus modifiers
    if (clampedRating == 3) {
      newInterval *= 1.3; // Easy bonus
    } else if (clampedRating == 1) {
      newInterval *= 0.5; // Hard penalty
    }

    // Clamp interval between 10 minutes and 365 days
    newInterval = newInterval.clamp(10.0 / (24 * 60), 365.0);

    final now = DateTime.now();
    return WordReviewState(
      word: word,
      score: score,
      easinessFactor: newEF,
      interval: newInterval,
      repetitions: newReps,
      nextReviewAt: now.add(
        Duration(milliseconds: (newInterval * 24 * 60 * 60 * 1000).toInt()),
      ),
      lastReviewedAt: now,
      lastRating: clampedRating,
      totalReviews: totalReviews + 1,
      forgottenCount: forgottenCount + (clampedRating == 0 ? 1 : 0),
      easyCount: easyCount + (clampedRating == 3 ? 1 : 0),
      addedAt: addedAt,
      definition: definition,
      exampleSentence: exampleSentence,
    );
  }

  // ─── Helper Properties ─────────────────────────────────────────────────

  /// Whether this word is new (never reviewed).
  bool get isNew => nextReviewAt == null;

  /// Whether this word is due for review (next_review_at <= now or never reviewed).
  bool get isDue {
    if (nextReviewAt == null) return true;
    return nextReviewAt!.isBefore(DateTime.now()) ||
        nextReviewAt!.isAtSameMomentAs(DateTime.now());
  }

  /// Whether this word is considered mastered (interval >= 21 days).
  bool get isMastered => interval >= 21.0;

  /// Whether this word is due within the next 24 hours (but not overdue).
  bool get isSoon {
    if (nextReviewAt == null) return false;
    final now = DateTime.now();
    return nextReviewAt!.isAfter(now) &&
        nextReviewAt!.isBefore(now.add(const Duration(hours: 24)));
  }

  // ─── copyWith ──────────────────────────────────────────────────────────

  WordReviewState copyWith({
    String? word,
    int? score,
    double? easinessFactor,
    double? interval,
    int? repetitions,
    DateTime? nextReviewAt,
    DateTime? lastReviewedAt,
    int? lastRating,
    int? totalReviews,
    int? forgottenCount,
    int? easyCount,
    DateTime? addedAt,
    String? definition,
    String? exampleSentence,
    bool clearNextReviewAt = false,
    bool clearLastReviewedAt = false,
    bool clearLastRating = false,
    bool clearAddedAt = false,
  }) {
    return WordReviewState(
      word: word ?? this.word,
      score: score ?? this.score,
      easinessFactor: easinessFactor ?? this.easinessFactor,
      interval: interval ?? this.interval,
      repetitions: repetitions ?? this.repetitions,
      nextReviewAt: clearNextReviewAt ? null : (nextReviewAt ?? this.nextReviewAt),
      lastReviewedAt:
          clearLastReviewedAt ? null : (lastReviewedAt ?? this.lastReviewedAt),
      lastRating: clearLastRating ? null : (lastRating ?? this.lastRating),
      totalReviews: totalReviews ?? this.totalReviews,
      forgottenCount: forgottenCount ?? this.forgottenCount,
      easyCount: easyCount ?? this.easyCount,
      addedAt: clearAddedAt ? null : (addedAt ?? this.addedAt),
      definition: definition ?? this.definition,
      exampleSentence: exampleSentence ?? this.exampleSentence,
    );
  }
}
