import 'package:Badya/utils/logger.dart';
import 'package:Badya/config/local_mode.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage notification preferences with multi-layer caching
/// (In-memory -> SharedPreferences -> Firestore)
class NotificationPreferencesService extends ChangeNotifier {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final String? _explicitUid;

  // In-memory cache for the current session
  static final Map<String, dynamic> _memoryCache = {};

  // Debounce Firestore sync to avoid redundant reads on rapid getter calls
  DateTime? _lastSyncFromFirestore;
  static const Duration _syncTtl = Duration(seconds: 30);

  // Preference keys
  static const String _reminderTimeKey = 'reminder_time';
  static const String _masterToggleKey = 'master_toggle';
  static const String _lastUpdatedKey = 'last_updated';
  static const String _notificationDaysKey = 'notification_days';
  static const String _startTimeKey = 'start_time';
  static const String _endTimeKey = 'end_time';

  // Default values
  static const String _defaultReminderTime = '19:00'; // 7:00 PM
  static const bool _defaultMasterToggle = true;
  // Days: Monday=1, Tuesday=2, ..., Sunday=7 - Default: all days
  static const String _defaultNotificationDays = '1234567';
  static const String _defaultStartTime = '08:00'; // 8:00 AM
  static const String _defaultEndTime = '22:00'; // 10:00 PM

  NotificationPreferencesService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    String? userId,
  }) : _firestore = LocalMode.enabled
           ? firestore
           : (firestore ?? FirebaseFirestore.instance),
       _auth = LocalMode.enabled ? auth : (auth ?? FirebaseAuth.instance),
       _explicitUid = userId {
    _initializeDefaults();
  }

  String? get _uid => _explicitUid ?? _auth.currentUser?.uid;

  /// Initialize default preferences on first launch
  Future<void> _initializeDefaults() async {
    if (_uid == null) return;

    try {
      // Check if preferences already exist
      final existing = await _getLocal(_masterToggleKey);
      if (existing != null) {
        return; // Already initialized
      }

      // Set defaults
      await _setLocal(_reminderTimeKey, _defaultReminderTime);
      await _setLocal(_masterToggleKey, _defaultMasterToggle);
      await _setLocal(_notificationDaysKey, _defaultNotificationDays);
      await _setLocal(_startTimeKey, _defaultStartTime);
      await _setLocal(_endTimeKey, _defaultEndTime);
      await _setLocal(_lastUpdatedKey, DateTime.now().toIso8601String());

      // Sync to Firestore
      await _syncToFirestore();
    } catch (e) {
      Logger.error('Failed to initialize notification preferences defaults', e);
    }
  }

  // --- Helper Methods for Caching ---

  String _getCacheKey(String key) => '${_uid}_notification_$key';

  Future<void> _setLocal(String key, dynamic value) async {
    if (_uid == null) return;
    final cacheKey = _getCacheKey(key);
    _memoryCache[cacheKey] = value;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (value is String) {
        await prefs.setString(cacheKey, value);
      } else if (value is bool) {
        await prefs.setBool(cacheKey, value);
      }
    } catch (e) {
      Logger.error('Failed to save notification preference locally: $key', e);
    }
  }

  Future<dynamic> _getLocal(String key) async {
    if (_uid == null) return null;
    final cacheKey = _getCacheKey(key);

    // 1. Check Memory
    if (_memoryCache.containsKey(cacheKey)) {
      return _memoryCache[cacheKey];
    }

    // 2. Check SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.get(cacheKey);
      if (value != null) {
        _memoryCache[cacheKey] = value;
        return value;
      }
    } catch (e) {
      Logger.warn(
        'Failed to read notification preference from SharedPrefs: $key',
      );
    }
    return null;
  }

  Future<void> _syncToFirestore() async {
    if (_uid == null) return;

    try {
      final reminderTime = await _getLocal(_reminderTimeKey);
      final masterToggle = await _getLocal(_masterToggleKey);
      final notificationDays = await _getLocal(_notificationDaysKey);
      final startTime = await _getLocal(_startTimeKey);
      final endTime = await _getLocal(_endTimeKey);

      await _firestore
          .collection('users')
          .doc(_uid)
          .collection('preferences')
          .doc('notifications')
          .set({
            _reminderTimeKey: reminderTime ?? _defaultReminderTime,
            _masterToggleKey: masterToggle ?? _defaultMasterToggle,
            _notificationDaysKey: notificationDays ?? _defaultNotificationDays,
            _startTimeKey: startTime ?? _defaultStartTime,
            _endTimeKey: endTime ?? _defaultEndTime,
            _lastUpdatedKey: DateTime.now().toIso8601String(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      Logger.error('Failed to sync preferences to Firestore', e);
    }
  }

  Future<void> _syncFromFirestore() async {
    if (_uid == null) return;

    // Debounce: skip if synced within the last 30 seconds
    if (_lastSyncFromFirestore != null &&
        DateTime.now().difference(_lastSyncFromFirestore!) < _syncTtl) {
      return;
    }
    _lastSyncFromFirestore = DateTime.now();

    try {
      final doc = await _firestore
          .collection('users')
          .doc(_uid)
          .collection('preferences')
          .doc('notifications')
          .get();

      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
          await _setLocal(
            _reminderTimeKey,
            data[_reminderTimeKey] ?? _defaultReminderTime,
          );
          await _setLocal(
            _masterToggleKey,
            data[_masterToggleKey] ?? _defaultMasterToggle,
          );

          await _setLocal(
            _notificationDaysKey,
            data[_notificationDaysKey] ?? _defaultNotificationDays,
          );
          await _setLocal(
            _startTimeKey,
            data[_startTimeKey] ?? _defaultStartTime,
          );
          await _setLocal(_endTimeKey, data[_endTimeKey] ?? _defaultEndTime);
        }
      }
    } catch (e) {
      Logger.warn('Failed to sync preferences from Firestore');
    }
  }

  // --- Reminder Time Methods ---

  /// Get the scheduled reminder time (default: 7:00 PM)
  Future<TimeOfDay> getReminderTime() async {
    final local = await _getLocal(_reminderTimeKey);
    if (local is String) {
      _syncFromFirestore(); // Background sync
      return _parseTimeOfDay(local);
    }

    if (_uid == null)
      return TimeOfDay.fromDateTime(DateTime(2024, 1, 1, 19, 0));

    try {
      await _syncFromFirestore();
      final time = await _getLocal(_reminderTimeKey);
      if (time is String) {
        return _parseTimeOfDay(time);
      }
    } catch (e) {
      Logger.warn(
        'Could not get reminder time from Firestore, using cache/default',
      );
    }

    return TimeOfDay.fromDateTime(DateTime(2024, 1, 1, 19, 0));
  }

  /// Save the reminder time and trigger reschedule
  Future<void> saveReminderTime(TimeOfDay time) async {
    final timeString =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    await _setLocal(_reminderTimeKey, timeString);
    await _setLocal(_lastUpdatedKey, DateTime.now().toIso8601String());
    await _syncToFirestore();
    notifyListeners();
  }

  // --- Master Toggle Methods ---

  /// Get the master toggle for notifications
  Future<bool> getMasterToggle() async {
    final local = await _getLocal(_masterToggleKey);
    if (local is bool) {
      _syncFromFirestore(); // Background sync
      return local;
    }

    if (_uid == null) return _defaultMasterToggle;

    try {
      await _syncFromFirestore();
      final toggle = await _getLocal(_masterToggleKey);
      if (toggle is bool) {
        return toggle;
      }
    } catch (e) {
      Logger.warn(
        'Could not get master toggle from Firestore, using cache/default',
      );
    }

    return _defaultMasterToggle;
  }

  /// Save the master toggle
  Future<void> saveMasterToggle(bool enabled) async {
    await _setLocal(_masterToggleKey, enabled);
    await _setLocal(_lastUpdatedKey, DateTime.now().toIso8601String());
    await _syncToFirestore();
    notifyListeners();
  }

  // --- Helper Methods ---

  TimeOfDay _parseTimeOfDay(String timeString) {
    try {
      final parts = timeString.split(':');
      if (parts.length == 2) {
        return TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        );
      }
    } catch (e) {
      Logger.warn('Could not parse time string, using default');
    }
    return TimeOfDay.fromDateTime(DateTime(2024, 1, 1, 19, 0));
  }

  /// Clear all preferences (for testing or logout)
  Future<void> clearPreferences() async {
    if (_uid == null) return;

    try {
      // Clear memory cache
      final keysToRemove = _memoryCache.keys
          .where((k) => k.startsWith('${_uid}_notification_'))
          .toList();
      for (final key in keysToRemove) {
        _memoryCache.remove(key);
      }

      // Clear SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final keys = keysToRemove.map((k) => k).toList();
      for (final key in keys) {
        await prefs.remove(key);
      }

      // Remove from Firestore
      await _firestore
          .collection('users')
          .doc(_uid)
          .collection('preferences')
          .doc('notifications')
          .delete()
          .timeout(const Duration(seconds: 10));

      notifyListeners();
    } catch (e) {
      Logger.error('Failed to clear notification preferences', e);
    }
  }

  // --- Notification Days Methods ---

  /// Get selected days for notifications (as string of digits: "1234567" = Mon-Sun)
  Future<String> getNotificationDays() async {
    final local = await _getLocal(_notificationDaysKey);
    if (local is String) {
      _syncFromFirestore(); // Background sync
      return local;
    }

    if (_uid == null) return _defaultNotificationDays;

    try {
      await _syncFromFirestore();
      final days = await _getLocal(_notificationDaysKey);
      if (days is String) {
        return days;
      }
    } catch (e) {
      Logger.warn(
        'Could not get notification days from Firestore, using default',
      );
    }

    return _defaultNotificationDays;
  }

  /// Save selected days for notifications
  Future<void> saveNotificationDays(String days) async {
    await _setLocal(_notificationDaysKey, days);
    await _setLocal(_lastUpdatedKey, DateTime.now().toIso8601String());
    await _syncToFirestore();
    notifyListeners();
  }

  /// Get start time for notification window (HH:mm format)
  Future<TimeOfDay> getStartTime() async {
    final local = await _getLocal(_startTimeKey);
    if (local is String) {
      _syncFromFirestore();
      return _parseTimeOfDay(local);
    }

    if (_uid == null) return _parseTimeOfDay(_defaultStartTime);

    try {
      await _syncFromFirestore();
      final time = await _getLocal(_startTimeKey);
      if (time is String) {
        return _parseTimeOfDay(time);
      }
    } catch (e) {
      Logger.warn('Could not get start time from Firestore, using default');
    }

    return _parseTimeOfDay(_defaultStartTime);
  }

  /// Save start time for notification window
  Future<void> saveStartTime(TimeOfDay time) async {
    final timeString =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    await _setLocal(_startTimeKey, timeString);
    await _setLocal(_lastUpdatedKey, DateTime.now().toIso8601String());
    await _syncToFirestore();
    notifyListeners();
  }

  /// Get end time for notification window (HH:mm format)
  Future<TimeOfDay> getEndTime() async {
    final local = await _getLocal(_endTimeKey);
    if (local is String) {
      _syncFromFirestore();
      return _parseTimeOfDay(local);
    }

    if (_uid == null) return _parseTimeOfDay(_defaultEndTime);

    try {
      await _syncFromFirestore();
      final time = await _getLocal(_endTimeKey);
      if (time is String) {
        return _parseTimeOfDay(time);
      }
    } catch (e) {
      Logger.warn('Could not get end time from Firestore, using default');
    }

    return _parseTimeOfDay(_defaultEndTime);
  }

  /// Save end time for notification window
  Future<void> saveEndTime(TimeOfDay time) async {
    final timeString =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    await _setLocal(_endTimeKey, timeString);
    await _setLocal(_lastUpdatedKey, DateTime.now().toIso8601String());
    await _syncToFirestore();
    notifyListeners();
  }

  /// Check if notifications should be sent on given day (1=Mon, 7=Sun)
  Future<bool> isNotificationEnabledForDay(int day) async {
    final days = await getNotificationDays();
    return days.contains(day.toString());
  }

  /// Get list of selected days as integers (1=Mon, 7=Sun)
  Future<List<int>> getSelectedDays() async {
    final days = await getNotificationDays();
    return days.split('').map((d) => int.parse(d)).toList();
  }

  /// Toggle notification for a specific day
  Future<void> toggleNotificationDay(int day) async {
    final current = await getNotificationDays();
    final dayStr = day.toString();

    String updated;
    if (current.contains(dayStr)) {
      // Remove day
      updated = current.replaceAll(dayStr, '');
    } else {
      // Add day and sort
      final daysSet = {...current.split('').map(int.parse), day};
      final daysList = daysSet.toList();
      daysList.sort();
      updated = daysList.map((d) => d.toString()).join();
    }

    await saveNotificationDays(updated);
  }

  /// Check if current time is within notification window
  Future<bool> isWithinNotificationWindow() async {
    final now = TimeOfDay.now();
    final start = await getStartTime();
    final end = await getEndTime();

    final nowMinutes = now.hour * 60 + now.minute;
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;

    return nowMinutes >= startMinutes && nowMinutes <= endMinutes;
  }
}
