import 'package:Badya/config/local_mode.dart';
import 'package:Badya/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:Badya/services/notification_service.dart';
import 'package:Badya/services/notification_pool_service.dart';
import 'package:Badya/services/active_hours_validator.dart';
import 'package:Badya/config/app_constants.dart';

/// Manages streak reminders - reduced to 1 fixed reminder per day at 7:00 PM
/// - Only sends if user hasn't completed their daily streak
/// - Respects active hours configured by user
class StreakReminderManager {
  static const int _reminderId = 101;
  static const int _nextDayReminderId = 201;

  final NotificationService _notificationService;
  final NotificationPoolService _poolService = NotificationPoolService();
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;
  final ActiveHoursValidator _activeHoursValidator = ActiveHoursValidator();

  // Cached config — avoids re-reading Firestore on every schedule cycle
  ReminderConfig? _cachedConfig;

  // Cached "completed today" — avoids re-reading daily_activity on redundant calls
  bool? _cachedCompletedToday;
  DateTime _completedTodayCacheTime = DateTime(2000);

  StreakReminderManager({required NotificationService notificationService})
    : _notificationService = notificationService;

  /// Initialize streak reminders - call this on app startup
  Future<void> initialize() async {
    if (LocalMode.enabled) return;
    tz_data.initializeTimeZones();

    // Schedule the single reminder for today/tomorrow
    await scheduleAllReminders();
  }

  /// Get current reminder configuration
  Future<ReminderConfig> getReminderConfig() async {
    if (_cachedConfig != null) return _cachedConfig!;

    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return ReminderConfig.defaultConfig();

      final doc = await _firestore.collection('users').doc(userId).get();
      if (!doc.exists || !doc.data()!.containsKey('streak_reminder_config')) {
        return ReminderConfig.defaultConfig();
      }

      final configMap =
          doc.data()!['streak_reminder_config'] as Map<String, dynamic>;
      _cachedConfig = ReminderConfig.fromMap(configMap);
      return _cachedConfig!;
    } catch (e) {
      Logger.error('Error fetching reminder config', e);
      return ReminderConfig.defaultConfig();
    }
  }

  /// Save reminder configuration
  Future<void> saveReminderConfig(ReminderConfig config) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return;

      await _firestore
          .collection('users')
          .doc(userId)
          .set({
        'streak_reminder_config': config.toMap(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 10));

      // Invalidate cache so next read fetches fresh data
      _cachedConfig = null;

      // Reschedule reminders with new config
      await scheduleAllReminders();
    } catch (e) {
      Logger.error('Error saving reminder config', e);
    }
  }

  /// Schedule the single streak reminder for the day
  Future<void> scheduleAllReminders() async {
    if (!_notificationService.isInitialized) {
      return;
    }

    try {
      final completedToday = await hasCompletedTodayStreak();
      if (completedToday) {
        await _cancelAllReminders();
        return;
      }

      // Cancel previous reminders
      await _cancelAllReminders();

      final config = await getReminderConfig();
      if (!config.enabled) return;

      final time = config.reminderTime;

      // Schedule for today if time hasn't passed, or tomorrow
      await _scheduleReminderAtTime(_reminderId, time);
      await _scheduleReminderForNextDay(_nextDayReminderId, time);
    } catch (e) {
      Logger.error('Failed to schedule streak reminder', e);
    }
  }

  /// Schedule a single reminder
  Future<void> _scheduleReminderAtTime(
    int notificationId,
    TimeOfDay time,
  ) async {
    try {
      final now = tz.TZDateTime.now(tz.local);
      var scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        time.hour,
        time.minute,
      );

      // If time has passed today, skip scheduling today's instance
      if (scheduledDate.isBefore(now)) {
        return;
      }

      // Check if scheduled time is within active hours
      final isValidTime = await _activeHoursValidator.isScheduledTimeValid(
        scheduledDate.toLocal(),
      );

      if (!isValidTime) return;

      // Get message from dynamic pool
      final message = await _poolService.getBestMessage(category: 'streak');

      await _notificationService.zonedScheduleStreakReminder(
        notificationId,
        scheduledDate,
        1, // Single reminder now
        customMessage: message,
      );
    } catch (e) {
      Logger.error('Error scheduling reminder at time', e);
    }
  }

  /// Check if user completed today's streak (XP >= 10)
  Future<bool> hasCompletedTodayStreak() async {
    // Return cached result if checked within the last 60 seconds
    if (_cachedCompletedToday != null &&
        DateTime.now().difference(_completedTodayCacheTime).inSeconds < 60) {
      return _cachedCompletedToday!;
    }

    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return false;

      final nowUtc = DateTime.now().toUtc();
      final dateOnly = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
      final today = _formatDateId(dateOnly);
      final doc = await _firestore
          .collection('users')
          .doc(userId)
          .collection('daily_activity')
          .doc(today)
          .get();

      if (!doc.exists) return false;

      final xpEarned = (doc.data()?['xp_earned'] as num?)?.toInt() ?? 0;
      final completed = xpEarned >= AppConstants.dailyStreakXpGoal;
      _cachedCompletedToday = completed;
      _completedTodayCacheTime = DateTime.now();
      return completed;
    } catch (e) {
      Logger.error('Error checking streak status', e);
      return false;
    }
  }

  String _formatDateId(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// Cancel reminders for today (called when user completes streak)
  Future<void> cancelRemainingReminders() async {
    try {
      await _notificationService.cancelNotification(_reminderId);
    } catch (e) {
      Logger.error('Failed to cancel remaining reminders', e);
    }
  }

  Future<void> _cancelAllReminders() async {
    await _notificationService.cancelNotification(_reminderId);
    await _notificationService.cancelNotification(_nextDayReminderId);
  }

  Future<void> _scheduleReminderForNextDay(
    int notificationId,
    TimeOfDay time,
  ) async {
    try {
      final now = tz.TZDateTime.now(tz.local);
      final scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day + 1,
        time.hour,
        time.minute,
      );

      final isValidTime = await _activeHoursValidator.isScheduledTimeValid(
        scheduledDate.toLocal(),
      );

      if (!isValidTime) return;

      final message = await _poolService.getBestMessage(category: 'streak');

      await _notificationService.zonedScheduleStreakReminder(
        notificationId,
        scheduledDate,
        1,
        customMessage: message,
      );
    } catch (e) {
      Logger.error('Error scheduling next day reminder', e);
    }
  }
}

// Deprecated ReminderConfig but kept for structural compatibility if needed by other components
class ReminderConfig {
  final bool enabled;
  final TimeOfDay reminderTime;
  final String message;

  ReminderConfig({
    this.enabled = true,
    this.reminderTime = const TimeOfDay(hour: 19, minute: 0),
    this.message = 'Keep your streak alive! 🔥',
  });

  factory ReminderConfig.defaultConfig() => ReminderConfig();

  factory ReminderConfig.fromMap(Map<String, dynamic> map) {
    return ReminderConfig(
      enabled: map['enabled'] as bool? ?? true,
      reminderTime: _timeFromString(map['time1'] as String? ?? '19:00'),
    );
  }

  Map<String, dynamic> toMap() => {
    'enabled': enabled,
    'time1': _timeToString(reminderTime),
    'message': message,
  };

  static TimeOfDay _timeFromString(String s) {
    final parts = s.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  static String _timeToString(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
