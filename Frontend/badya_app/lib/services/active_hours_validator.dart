import 'package:flutter/material.dart';
import 'package:Badya/services/notification_preferences_service.dart';
import 'package:Badya/utils/logger.dart';

/// Helper service to validate if current time is within active hours
/// Active hours represent when notifications ARE allowed to be sent
class ActiveHoursValidator {
  final NotificationPreferencesService _prefsService;

  ActiveHoursValidator({
    NotificationPreferencesService? prefsService,
  }) : _prefsService = prefsService ?? NotificationPreferencesService();

  /// Check if current time is within active hours window
  /// Returns true if notifications are allowed right now
  Future<bool> isWithinActiveHours() async {
    try {
      // Check master toggle first
      final masterEnabled = await _prefsService.getMasterToggle();
      if (!masterEnabled) {
        Logger.info('Notifications disabled by master toggle');
        return false;
      }

      // Get current time and day
      final now = DateTime.now();
      final currentTime = TimeOfDay.now();
      final currentDayOfWeek = now.weekday; // 1=Monday, 7=Sunday

      // Get active hours configuration
      final startTime = await _prefsService.getStartTime();
      final endTime = await _prefsService.getEndTime();
      final selectedDays = await _prefsService.getNotificationDays();

      // Check if today is in selected days
      if (!selectedDays.contains(currentDayOfWeek.toString())) {
        Logger.info('Notifications disabled for today (day $currentDayOfWeek)');
        return false;
      }

      // Check if current time is within the active hours range
      final isWithinRange = _isTimeInRange(currentTime, startTime, endTime);

      if (!isWithinRange) {
        Logger.info(
          'Current time ${_formatTime(currentTime)} is outside active hours '
          '${_formatTime(startTime)} - ${_formatTime(endTime)}',
        );
      }

      return isWithinRange;
    } catch (e) {
      Logger.error('Error checking active hours', e);
      // Default to allowing notifications on error
      return true;
    }
  }

  /// Check if a specific scheduled time would be within active hours
  /// Returns true if the notification should be scheduled
  Future<bool> isScheduledTimeValid(DateTime scheduledTime) async {
    try {
      final masterEnabled = await _prefsService.getMasterToggle();
      if (!masterEnabled) return false;

      final timeOfDay = TimeOfDay.fromDateTime(scheduledTime);
      final dayOfWeek = scheduledTime.weekday;

      final startTime = await _prefsService.getStartTime();
      final endTime = await _prefsService.getEndTime();
      final selectedDays = await _prefsService.getNotificationDays();

      // Check day
      if (!selectedDays.contains(dayOfWeek.toString())) {
        return false;
      }

      // Check time range
      return _isTimeInRange(timeOfDay, startTime, endTime);
    } catch (e) {
      Logger.error('Error validating scheduled time', e);
      return true;
    }
  }

  /// Check if time is within range, handling midnight crossover
  bool _isTimeInRange(TimeOfDay current, TimeOfDay start, TimeOfDay end) {
    final currentMinutes = current.hour * 60 + current.minute;
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;

    if (startMinutes <= endMinutes) {
      // Normal range (e.g., 8:00 AM to 10:00 PM)
      return currentMinutes >= startMinutes && currentMinutes <= endMinutes;
    } else {
      // Range crosses midnight (e.g., 10:00 PM to 2:00 AM)
      return currentMinutes >= startMinutes || currentMinutes <= endMinutes;
    }
  }

  String _formatTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  /// Calculate how many notifications would be sent per day based on active hours
  /// Returns a map with notification type counts
  Future<Map<String, int>> estimateDailyNotificationCount() async {
    final masterEnabled = await _prefsService.getMasterToggle();
    if (!masterEnabled) {
      return {
        'streak_reminders': 0,
        'total_per_day': 0,
      };
    }

    final startTime = await _prefsService.getStartTime();
    final endTime = await _prefsService.getEndTime();
    final selectedDays = await _prefsService.getNotificationDays();

    // Calculate active hours window in hours
    final startMinutes = startTime.hour * 60 + startTime.minute;
    final endMinutes = endTime.hour * 60 + endTime.minute;
    
    int windowMinutes;
    if (startMinutes <= endMinutes) {
      windowMinutes = endMinutes - startMinutes;
    } else {
      // Crosses midnight
      windowMinutes = (24 * 60 - startMinutes) + endMinutes;
    }
    
    final windowHours = windowMinutes / 60;

    // Streak reminders (3 per day at 9 AM, 2 PM, 8 PM)
    final defaultStreakTimes = [
      const TimeOfDay(hour: 9, minute: 0),
      const TimeOfDay(hour: 14, minute: 0),
      const TimeOfDay(hour: 20, minute: 0),
    ];

    int streakRemindersInRange = 0;
    for (final time in defaultStreakTimes) {
      if (_isTimeInRange(time, startTime, endTime)) {
        streakRemindersInRange++;
      }
    }

    // Currently, streak reminders are the only local notifications
    // FCM notifications from backend are separate
    final totalPerDay = streakRemindersInRange;

    return {
      'streak_reminders': streakRemindersInRange,
      'active_hours': windowHours.round(),
      'active_days': selectedDays.length,
      'total_per_day': totalPerDay,
    };
  }

  /// Get human-readable summary of active hours
  Future<String> getActiveHoursSummary() async {
    final stats = await estimateDailyNotificationCount();
    final startTime = await _prefsService.getStartTime();
    final endTime = await _prefsService.getEndTime();
    final selectedDays = await _prefsService.getNotificationDays();

    final dayNames = _getDayNames(selectedDays);
    
    return 'Active ${_formatTime(startTime)} - ${_formatTime(endTime)} '
           'on $dayNames\n'
           '${stats['streak_reminders']} streak reminders/day '
           '(${stats['active_hours']} hour window)';
  }

  String _getDayNames(String days) {
    if (days.length == 7) return 'all days';
    
    final dayMap = {
      '1': 'Mon',
      '2': 'Tue',
      '3': 'Wed',
      '4': 'Thu',
      '5': 'Fri',
      '6': 'Sat',
      '7': 'Sun',
    };
    
    final names = days.split('').map((d) => dayMap[d] ?? '').where((n) => n.isNotEmpty).toList();
    return names.join(', ');
  }
}
