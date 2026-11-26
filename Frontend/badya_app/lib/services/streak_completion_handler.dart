import 'package:Badya/services/streak_reminder_manager.dart';
import 'package:Badya/utils/logger.dart';

/// Handles streak completion events and manages reminder lifecycle
class StreakCompletionHandler {
  static StreakReminderManager? _reminderManager;

  /// Initialize the handler with a reference to the reminder manager
  static void initialize(StreakReminderManager reminderManager) {
    _reminderManager = reminderManager;
  }

  /// Call this when user completes their daily practice/streak
  /// This will cancel all remaining reminders for today
  static Future<void> onStreakCompleted() async {
    try {
      if (_reminderManager == null) {
        return;
      }

      await _reminderManager!.cancelRemainingReminders();
    } catch (e) {
      Logger.error('Error in onStreakCompleted', e);
    }
  }

  /// Get reminder manager instance
  static StreakReminderManager? getReminderManager() {
    return _reminderManager;
  }
}
