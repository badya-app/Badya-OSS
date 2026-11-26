class AppConstants {
  // Notification initialization
  static const int notificationInitMaxAttempts = 50;
  static const Duration notificationInitCheckInterval = Duration(milliseconds: 100);

  // Streak reminder
  static const int streakReminderHour = 22; // 10 PM

  // Global UI/Animation Delays
  static const Duration animationDelayShort = Duration(milliseconds: 300);
  static const Duration animationDelayMedium = Duration(seconds: 1);
  static const Duration animationDelayLong = Duration(seconds: 2);

  // Audio/Voice Delays
  static const Duration audioDelayShort = Duration(milliseconds: 100);
  static const Duration audioDelayMedium = Duration(milliseconds: 500);

  // Service Pollings
  static const Duration videoPollingInterval = Duration(seconds: 3);

  // Business Logic
  static const int dailyStreakXpGoal = 10;

  /// Google Play listing (Android-only app).
  static const String playStorePackageId = 'com.badya.app';

  static Uri get playStoreListingUri => Uri.parse(
        'https://play.google.com/store/apps/details?id=$playStorePackageId',
      );

  /// Delay before showing the review prompt on completion screens.
  static const Duration reviewPromptDelay = Duration(milliseconds: 2500);

  /// Total XP above this value triggers the one-time store review pre-prompt.
  static const int reviewPromptXpThreshold = 20;

  /// True when a grant moves the user from at-or-below [reviewPromptXpThreshold]
  /// to above it.
  static bool crossedReviewPromptThreshold(int totalXpBefore, int totalXpAfter) {
    return totalXpBefore <= reviewPromptXpThreshold &&
        totalXpAfter > reviewPromptXpThreshold;
  }
}
