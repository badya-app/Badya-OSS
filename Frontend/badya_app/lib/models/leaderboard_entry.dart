/// Model representing a single entry on the leaderboard.
class LeaderboardEntry {
  final String userId;
  final String displayName;
  final String? photoUrl;
  final int score;
  final int rank;
  final bool isCurrentUser;
  final String? language;
  final String? subtitle;

  const LeaderboardEntry({
    required this.userId,
    required this.displayName,
    this.photoUrl,
    required this.score,
    required this.rank,
    this.isCurrentUser = false,
    this.language,
    this.subtitle,
  });

  LeaderboardEntry copyWith({
    String? userId,
    String? displayName,
    String? photoUrl,
    int? score,
    int? rank,
    bool? isCurrentUser,
    String? language,
    String? subtitle,
  }) {
    return LeaderboardEntry(
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      score: score ?? this.score,
      rank: rank ?? this.rank,
      isCurrentUser: isCurrentUser ?? this.isCurrentUser,
      language: language ?? this.language,
      subtitle: subtitle ?? this.subtitle,
    );
  }
}
