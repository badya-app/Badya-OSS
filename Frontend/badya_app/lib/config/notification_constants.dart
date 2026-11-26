class NotificationConstants {
  // Notification IDs
  static const int streakReminderId = 1;
  static const int streakFreezeWarningId = 2;
  static const int engagementBaseId = 300;
  static const int testScheduledId = 99;
  static const int foregroundPushId = 500;

  // Channel IDs
  static const String streakReminderChannelId = 'streak_reminders';
  static const String streakFreezeChannelId = 'streak_freeze_warnings';
  static const String engagementChannelId = 'engagement_notifications';
  static const String testChannelId = 'test_channel';
  static const String pushChannelId = 'push_notifications';

  // Channel Names
  static const String streakReminderChannelName = 'Streak Reminders';
  static const String streakFreezeChannelName = 'Streak Warnings';
  static const String engagementChannelName = 'Learning Reminders';
  static const String testChannelName = 'Test Notifications';
  static const String pushChannelName = 'Push Notifications';

  // Topic Names (for preferences)
  static const String topicStreak = 'streak';
  static const String topicEngagement = 'engagement';
  static const String topicImports = 'imports';
  static const String topicUpdates = 'updates';
}
