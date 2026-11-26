/// Aggregated review statistics for a language's SRS state.
///
/// Used by the Strange Words page and Language Profile page to display
/// a quick overview of the user's vocabulary review status.
class ReviewStats {
  /// Total number of words in the review system.
  final int totalWords;

  /// Number of words due for review (new + overdue).
  final int dueCount;

  /// Number of mastered words (interval >= 21 days).
  final int masteredCount;

  /// Number of new words (never reviewed).
  final int newCount;

  /// Recall rate as a fraction 0.0–1.0.
  /// Computed as (total_reviews - forgotten_count) / total_reviews,
  /// or 1.0 if no reviews have been completed.
  final double recallRate;

  /// Number of words due within the next 24 hours (but not overdue).
  final int soonCount;

  /// Number of words that are overdue (past their review date).
  final int overdueCount;

  /// Total number of individual review sessions completed.
  /// Used to determine if recall data is meaningful (0 = no reviews yet).
  final int totalReviews;

  const ReviewStats({
    this.totalWords = 0,
    this.dueCount = 0,
    this.masteredCount = 0,
    this.newCount = 0,
    this.recallRate = 1.0,
    this.soonCount = 0,
    this.overdueCount = 0,
    this.totalReviews = 0,
  });

  // ─── Factory ───────────────────────────────────────────────────────────

  /// Creates [ReviewStats] from a list of [WordReviewState] entries.
  ///
  /// This is the primary way to build stats — by passing the full word list
  /// for a language and letting this method compute the aggregate counts.
  ///
  /// ```dart
  /// final stats = ReviewStats.fromWordList(allWords);
  /// ```
  factory ReviewStats.fromWordList(List allWords) {
    // Accept either List<WordReviewState> or dynamic from JSON
    int totalWords = 0;
    int dueCount = 0;
    int masteredCount = 0;
    int newCount = 0;
    int soonCount = 0;
    int overdueCount = 0;
    int totalReviews = 0;
    int totalForgotten = 0;

    for (final entry in allWords) {
      totalWords++;

      // Determine "new" status
      final nextReviewAt = _extractNextReviewAt(entry);
      final interval = _extractInterval(entry);
      final isNew = nextReviewAt == null;
      final isMastered = interval != null && interval >= 21.0;

      if (isNew) {
        newCount++;
        dueCount++; // New words are due for review
      } else if (isMastered) {
        masteredCount++;
      } else if (nextReviewAt.isBefore(DateTime.now())) {
        overdueCount++;
        dueCount++;
      } else if (nextReviewAt
          .isBefore(DateTime.now().add(const Duration(hours: 24)))) {
        soonCount++;
        // "Soon" words are not "due" yet, but they will be within 24h
      }

      // Recall rate stats
      final reviews = _extractTotalReviews(entry);
      final forgotten = _extractForgottenCount(entry);
      totalReviews += reviews ?? 0;
      totalForgotten += forgotten ?? 0;
    }

    final recallRate =
        totalReviews > 0 ? (totalReviews - totalForgotten) / totalReviews : 1.0;

    return ReviewStats(
      totalWords: totalWords,
      dueCount: dueCount,
      masteredCount: masteredCount,
      newCount: newCount,
      recallRate: recallRate.clamp(0.0, 1.0),
      soonCount: soonCount,
      overdueCount: overdueCount,
      totalReviews: totalReviews,
    );
  }

  // ─── Private Helpers ───────────────────────────────────────────────────

  static DateTime? _extractNextReviewAt(dynamic entry) {
    if (entry is Map<String, dynamic>) {
      final raw = entry['next_review_at'];
      if (raw == null) return null;
      if (raw is DateTime) return raw;
    }
    // If it's an object with .nextReviewAt getter (e.g. WordReviewState)
    try {
      final dt = (entry as dynamic).nextReviewAt;
      return dt as DateTime?;
    } catch (_) {
      return null;
    }
  }

  static double? _extractInterval(dynamic entry) {
    if (entry is Map<String, dynamic>) {
      final raw = entry['interval'];
      if (raw is num) return raw.toDouble();
    }
    try {
      final val = (entry as dynamic).interval;
      return (val as double?)?.toDouble();
    } catch (_) {
      return null;
    }
  }

  static int? _extractTotalReviews(dynamic entry) {
    if (entry is Map<String, dynamic>) {
      final raw = entry['total_reviews'];
      if (raw is num) return raw.toInt();
    }
    try {
      final val = (entry as dynamic).totalReviews;
      return val as int?;
    } catch (_) {
      return null;
    }
  }

  static int? _extractForgottenCount(dynamic entry) {
    if (entry is Map<String, dynamic>) {
      final raw = entry['forgotten_count'];
      if (raw is num) return raw.toInt();
    }
    try {
      final val = (entry as dynamic).forgottenCount;
      return val as int?;
    } catch (_) {
      return null;
    }
  }

  // ─── copyWith ──────────────────────────────────────────────────────────

  ReviewStats copyWith({
    int? totalWords,
    int? dueCount,
    int? masteredCount,
    int? newCount,
    double? recallRate,
    int? soonCount,
    int? overdueCount,
    int? totalReviews,
  }) {
    return ReviewStats(
      totalWords: totalWords ?? this.totalWords,
      dueCount: dueCount ?? this.dueCount,
      masteredCount: masteredCount ?? this.masteredCount,
      newCount: newCount ?? this.newCount,
      recallRate: recallRate ?? this.recallRate,
      soonCount: soonCount ?? this.soonCount,
      overdueCount: overdueCount ?? this.overdueCount,
      totalReviews: totalReviews ?? this.totalReviews,
    );
  }
}
