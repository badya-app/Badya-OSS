import 'dart:convert';

import 'package:Badya/config/local_mode.dart';
import 'package:Badya/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:Badya/utils/score_service.dart';
import 'package:Badya/utils/topic_action_helper.dart';
import 'package:Badya/video_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:Badya/services/lesson_session_service.dart';
import 'package:Badya/config/content_types.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService extends ChangeNotifier {
  static const String _lastPracticeDateKey = 'notification_last_practice_date';
  static const int _testScheduledNotificationId = 99;
  static const MethodChannel _notificationChannel = MethodChannel(
    'com.badya.app/notifications',
  );

  /// Global navigator key for deep linking from notification taps.
  /// Must be passed to MaterialApp's navigatorKey in main.dart.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal() {
    _initialize();
  }

  bool get isInitialized => _isInitialized;

  // --- Test hooks (@visibleForTesting) ---

  /// Number of payloads handed to [_handleNotificationTap]. Used by
  /// regression tests to assert payloads are dispatched exactly once.
  @visibleForTesting
  static int debugDispatchedTapCount = 0;

  /// Whether a cold-start launch check is currently in flight (test hook).
  @visibleForTesting
  bool get pendingLaunchCheckInFlight => _inFlightLaunchCheck != null;

  /// Resets all dispatch state so tests start from a clean slate.
  @visibleForTesting
  void debugResetDispatchState() {
    debugDispatchedTapCount = 0;
    _pendingPayload = null;
    _launchPayloadConsumed = false;
    _pendingRetryScheduled = false;
    _inFlightLaunchCheck = null;
  }

  // Expose plugin for engagement notification scheduler
  FlutterLocalNotificationsPlugin get flutterLocalNotificationsPlugin =>
      _flutterLocalNotificationsPlugin;

  Future<void> _initialize() async {
    // Initialize timezone data
    tz_data.initializeTimeZones();
    await _configureLocalTimezone();

    // Android settings
    const AndroidInitializationSettings androidInitializationSettings =
        AndroidInitializationSettings('@drawable/ic_notification');

    // iOS settings
    final DarwinInitializationSettings iosInitializationSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
          onDidReceiveLocalNotification: _onDidReceiveLocalNotification,
        );

    final InitializationSettings initializationSettings =
        InitializationSettings(
          android: androidInitializationSettings,
          iOS: iosInitializationSettings,
        );

    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onDidReceiveNotificationResponse,
    );

    _isInitialized = true;
    notifyListeners();

    // Check if launched via notification response
    await checkAppLaunchNotification();
  }

  String? _pendingPayload;

  /// Guards against re-processing the cold-start launch payload.
  /// [getNotificationAppLaunchDetails] keeps reporting "launched from
  /// notification" for the entire session, so this must only be handled once.
  bool _launchPayloadConsumed = false;

  /// In-flight dedupe for [checkAppLaunchNotification]. The constructor chain
  /// and AppInitializer's deferred callback can invoke it concurrently; both
  /// must not run the launch detection at once or the same payload gets
  /// dispatched twice.
  Future<void>? _inFlightLaunchCheck;

  /// Check if the app was launched by tapping a local notification (cold start),
  /// then flush any pending (stashed) tap payload once the navigator is ready.
  /// Safe to call multiple times, even concurrently — each payload is
  /// dispatched at most once.
  Future<void> checkAppLaunchNotification() {
    final inFlight = _inFlightLaunchCheck;
    if (inFlight != null) {
      // Another caller is detecting the launch payload — wait for it, then
      // flush anything it stashed while no navigator was attached yet.
      return inFlight.then((_) => _flushPendingPayload());
    }
    final future = _detectAndDispatchLaunchPayload();
    _inFlightLaunchCheck = future;
    return future.whenComplete(() => _inFlightLaunchCheck = null);
  }

  Future<void> _detectAndDispatchLaunchPayload() async {
    try {
      // NOTE: the consumed flag is only ever written inside this method, which
      // runs at most once at a time thanks to [_inFlightLaunchCheck] — so the
      // check-then-set below cannot race.
      if (!_launchPayloadConsumed) {
        final launchDetails = await _flutterLocalNotificationsPlugin
            .getNotificationAppLaunchDetails();
        if (launchDetails != null &&
            launchDetails.didNotificationLaunchApp &&
            launchDetails.notificationResponse?.payload != null) {
          _launchPayloadConsumed = true;
          // The launch payload supersedes anything stashed earlier for the
          // same launch — clear it to prevent a duplicate dispatch below.
          _pendingPayload = null;
          final payload = launchDetails.notificationResponse!.payload!;
          Logger.info('App launched from notification with payload: $payload');
          handleNotificationPayload(payload);
          return;
        }
        // Not a notification launch — never check again this session.
        _launchPayloadConsumed = true;
      }

      _flushPendingPayload();
    } catch (e) {
      Logger.error('Failed to check app launch notification', e);
    }
  }

  /// Dispatch and clear the stashed tap payload, if any.
  void _flushPendingPayload() {
    final payload = _pendingPayload;
    if (payload == null) return;
    _pendingPayload = null;
    handleNotificationPayload(payload);
  }

  /// Whether a post-frame retry has been scheduled for the pending stash
  /// (prevents scheduling one per frame if the navigator stays detached).
  bool _pendingRetryScheduled = false;

  /// Handle notification payload map directly (e.g. from FCM).
  void handleNotificationData(Map<String, dynamic> data) {
    handleNotificationPayload(jsonEncode(data));
  }

  /// Public handler for notification tap / deep linking payload.
  void handleNotificationPayload(String payload) {
    _handleNotificationTap(payload);
  }

  Future<void> _onDidReceiveLocalNotification(
    int id,
    String? title,
    String? body,
    String? payload,
  ) async {
    // iOS-specific handler for older iOS versions
    if (payload != null) {
      _handleNotificationTap(payload);
    }
  }

  /// Handle notification tap — parse payload and navigate accordingly.
  void _handleNotificationTap(String payload) {
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final String? source = data['source'] as String?;
      final String? route = data['route'] as String?;
      final String? notificationType = data['notification_type'] as String?;
      final String? topicId =
          (data['topic_id'] ?? data['content_id']) as String?;

      final navigatorState = navigatorKey.currentState;
      if (navigatorState == null) {
        Logger.warn(
          'navigatorKey not attached yet; stashing pending notification payload',
        );
        _pendingPayload = payload;
        // Self-healing retry: once the first frame attaches the navigator,
        // flush the stash even if nobody calls checkAppLaunchNotification
        // again (e.g. an FCM cold-start message arriving after that flush).
        if (!_pendingRetryScheduled) {
          _pendingRetryScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _pendingRetryScheduled = false;
            _flushPendingPayload();
          });
        }
        return;
      }

      // Dispatched for real — count it (test hook below the stash branch so
      // stashed-but-not-yet-navigable payloads aren't counted).
      debugDispatchedTapCount++;

      // Determine where to navigate based on payload
      if (notificationType == 'video_ready') {
        if (topicId != null && VideoPage.activeTopicId == topicId) {
          Logger.info('User is already viewing VideoPage for topic $topicId; ignoring notification tap.');
          return;
        }

        navigatorState.popUntil((route) => route.isFirst);

        if (topicId != null && topicId.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            final context = navigatorKey.currentContext;
            if (context == null || !context.mounted) return;

            final String uid = LocalMode.enabled
                ? LocalMode.guestUid
                : (FirebaseAuth.instance.currentUser?.uid ?? 'default_user');
            final String title = data['topic_title'] as String? ?? 'Video Lesson';
            final String description = data['description'] as String? ?? '';
            final String language = data['language'] as String? ?? 'English';
            final String? nativeLanguage = data['native_language'] as String?;
            final List<String>? wordsList = (data['words_list'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList();

            final sessionId = (data['session_id'] as String?) ??
                LessonSessionService().getSession(
                  topicId: topicId,
                  lessonType: LessonTypes.echoChamber,
                ).sessionId;

            navigatorState.push(
              MaterialPageRoute(
                builder: (context) => VideoPage(
                  subjectTitle: title,
                  description: description,
                  topicId: topicId,
                  sessionId: sessionId,
                  userId: uid,
                  appName: 'video_agent',
                  language: language,
                  nativeLanguage: nativeLanguage,
                  wordsList: wordsList,
                ),
              ),
            );
          });
        }
      } else if (route != null && route == 'profile') {
        navigatorState.popUntil((route) => route.isFirst);
      } else {
        // Default: pop to root home
        navigatorState.popUntil((route) => route.isFirst);
      }

      // If this is a topic suggestion, present the AddToCollectionSheet
      if (notificationType == 'topic_suggestion' &&
          topicId != null &&
          topicId.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          final context = navigatorKey.currentContext;
          if (context != null && context.mounted) {
            await TopicActionHelper.showTopicSheetById(
              context: context,
              contentId: topicId,
              source: source == 'fcm' ? 'push_notification' : 'topic_notification',
              // Notification topics can be stale/expired — fail quietly.
              silentOnError: true,
            );
          }
        });
      }

      Logger.info(
        'Notification tap handled: source=$source, route=$route, type=$notificationType, topicId=$topicId',
      );
    } catch (e) {
      Logger.error('Failed to handle notification tap', e);
    }
  }

  Future<void> _onDidReceiveNotificationResponse(
    NotificationResponse notificationResponse,
  ) async {
    final String? payload = notificationResponse.payload;
    if (payload != null && payload.isNotEmpty) {
      _handleNotificationTap(payload);
    }
  }

  /// Request notification permissions on Android 13+
  Future<bool> requestNotificationPermission() async {
    try {
      // Request POST_NOTIFICATIONS permission on Android 13+
      final PermissionStatus status = await Permission.notification.request();

      if (status.isDenied) {
        return false;
      } else if (status.isGranted) {
        return true;
      } else if (status.isPermanentlyDenied) {
        // Don't open app settings — this is jarring and can cause a loop
        // where the user keeps getting redirected. Just return false and
        // let the user enable notifications from the app's settings if they
        // want to.
        Logger.warn('Notification permission permanently denied');
        return false;
      }
      return false;
    } catch (e) {
      Logger.error('Failed to request notification permission', e);
      return false;
    }
  }

  /// Request exact alarm permission on Android 12+
  Future<bool> _requestExactAlarmPermission() async {
    try {
      final bool granted =
          await _notificationChannel.invokeMethod<bool>(
            'requestExactAlarmPermission',
          ) ??
          false;
      if (granted) {
        Logger.info('Exact alarm permission granted');
      } else {
        Logger.warn('Exact alarm permission denied');
      }
      return granted;
    } catch (e) {
      // Continue anyway, might work without explicit permission on some devices
      return true;
    }
  }

  Future<void> _configureLocalTimezone() async {
    try {
      final String? timeZoneName = await _notificationChannel
          .invokeMethod<String>('getLocalTimezone');
      if (timeZoneName == null || timeZoneName.isEmpty) {
        return;
      }
      tz.setLocalLocation(tz.getLocation(timeZoneName));
    } catch (e) {
      Logger.error('Failed to configure local timezone', e);
    }
  }

  /// Schedule a daily streak reminder at specified time
  Future<void> scheduleStreakReminder(TimeOfDay time) async {
    if (!_isInitialized) {
      return;
    }

    try {
      // Request exact alarm permission on Android
      await _requestExactAlarmPermission();

      // Check if user has already practiced today
      final bool practicedToday = await _hasPracticedToday();
      if (practicedToday) {
        return;
      }

      final now = tz.TZDateTime.now(tz.local);
      var scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        time.hour,
        time.minute,
      );

      // If the time has already passed today, schedule for tomorrow
      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      // Get current streak (assuming ScoreService has this info)
      final streak = await _getCurrentStreak();

      const AndroidNotificationDetails androidNotificationDetails =
          AndroidNotificationDetails(
            'streak_reminder',
            'Streak Reminders',
            channelDescription:
                'Daily reminders to maintain your learning streak',
            importance: Importance.max,
            priority: Priority.high,
            showWhen: true,
            icon: 'ic_notification',
          );

      const DarwinNotificationDetails darwinNotificationDetails =
          DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          );

      final NotificationDetails notificationDetails = NotificationDetails(
        android: androidNotificationDetails,
        iOS: darwinNotificationDetails,
      );

      final String payload = jsonEncode({
        'source': 'local',
        'route': 'home',
        'notification_type': 'streak_reminder',
      });

      await _flutterLocalNotificationsPlugin.zonedSchedule(
        1, // Notification ID for streak reminder
        '🔥 Keep Your Streak Alive!',
        'You have a $streak-day streak. Practice now to keep it going!',
        scheduledDate,
        notificationDetails,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
      );
    } catch (e) {
      Logger.error('Failed to schedule streak reminder', e);
    }
  }

  /// Schedule a streak freeze warning 2 hours before midnight
  Future<void> scheduleStreakFreezeWarning() async {
    if (!_isInitialized) {
      return;
    }

    try {
      // Check if user has already practiced today
      final bool practicedToday = await _hasPracticedToday();
      if (practicedToday) {
        return;
      }

      final now = tz.TZDateTime.now(tz.local);
      // Schedule for 2 hours before midnight (10:00 PM)
      var scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        22, // 10 PM
        0,
      );

      // If the time has already passed today, schedule for tomorrow
      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      final streak = await _getCurrentStreak();

      const AndroidNotificationDetails androidNotificationDetails =
          AndroidNotificationDetails(
            'streak_freeze_warning',
            'Streak Freeze Warnings',
            channelDescription: 'Warning when your streak is about to end',
            importance: Importance.high,
            priority: Priority.high,
            showWhen: true,
            icon: 'ic_notification',
          );

      const DarwinNotificationDetails darwinNotificationDetails =
          DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          );

      final NotificationDetails notificationDetails = NotificationDetails(
        android: androidNotificationDetails,
        iOS: darwinNotificationDetails,
      );

      final String payload = jsonEncode({
        'source': 'local',
        'route': 'home',
        'notification_type': 'streak_freeze',
      });

      await _flutterLocalNotificationsPlugin.zonedSchedule(
        2, // Notification ID for freeze warning
        '⚠️ Streak Ending Soon!',
        'Your $streak-day streak ends in 2 hours. Practice now to save it!',
        scheduledDate,
        notificationDetails,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: payload,
      );
    } catch (e) {
      Logger.error('Failed to schedule streak freeze warning', e);
    }
  }

  /// Cancel all scheduled notifications
  Future<void> cancelAllNotifications() async {
    try {
      await _flutterLocalNotificationsPlugin.cancelAll();
    } catch (e) {
      Logger.error('Failed to cancel all notifications', e);
    }
  }

  /// Cancel specific notification by ID
  Future<void> cancelNotification(int id) async {
    try {
      await _flutterLocalNotificationsPlugin.cancel(id);
    } catch (e) {
      Logger.error('Failed to cancel notification with id: $id', e);
    }
  }

  /// Check if user has already practiced today
  Future<bool> _hasPracticedToday() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastPracticeDate = prefs.getString(_lastPracticeDateKey);

      final today = DateTime.now().toIso8601String().split('T')[0];

      // Check if we've recorded practice for today
      if (lastPracticeDate == today) {
        return true;
      }

      return false;
    } catch (e) {
      Logger.error('Failed to check if practiced today', e);
      return false;
    }
  }

  /// Get current streak from ScoreService
  Future<int> _getCurrentStreak() async {
    try {
      final streak = await ScoreService.getStreak();
      return streak;
    } catch (e) {
      Logger.error('Failed to get current streak', e);
      return 0;
    }
  }

  /// Show a test notification (for debugging)
  Future<void> showTestNotification() async {
    const AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
          'test_channel',
          'Test Notifications',
          channelDescription: 'Test notification channel',
          importance: Importance.max,
          priority: Priority.high,
          icon: 'ic_notification',
        );

    const DarwinNotificationDetails darwinNotificationDetails =
        DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
      iOS: darwinNotificationDetails,
    );

    await _flutterLocalNotificationsPlugin.show(
      0,
      'Test Notification',
      'This is a test notification from Badya',
      notificationDetails,
    );
  }

  /// Schedule a test notification after a short delay
  Future<void> scheduleTestNotification({
    Duration delay = const Duration(seconds: 10),
  }) async {
    if (!_isInitialized) {
      return;
    }

    try {
      final bool exactAlarmGranted = await _requestExactAlarmPermission();
      final scheduledDate = tz.TZDateTime.now(tz.local).add(delay);

      const AndroidNotificationDetails androidNotificationDetails =
          AndroidNotificationDetails(
            'test_channel',
            'Test Notifications',
            channelDescription: 'Test notification channel',
            importance: Importance.max,
            priority: Priority.high,
            icon: 'ic_notification',
          );

      const DarwinNotificationDetails darwinNotificationDetails =
          DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          );

      final NotificationDetails notificationDetails = NotificationDetails(
        android: androidNotificationDetails,
        iOS: darwinNotificationDetails,
      );

      if (exactAlarmGranted) {
        await _flutterLocalNotificationsPlugin.zonedSchedule(
          _testScheduledNotificationId,
          'Scheduled Test Notification',
          'This is a scheduled test notification from Badya',
          scheduledDate,
          notificationDetails,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      } else {
        try {
          await _flutterLocalNotificationsPlugin.zonedSchedule(
            _testScheduledNotificationId,
            'Scheduled Test Notification',
            'This is a scheduled test notification from Badya',
            scheduledDate,
            notificationDetails,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            androidScheduleMode: AndroidScheduleMode.alarmClock,
          );
        } on PlatformException {
          await _flutterLocalNotificationsPlugin.zonedSchedule(
            _testScheduledNotificationId,
            'Scheduled Test Notification',
            'This is a scheduled test notification from Badya',
            scheduledDate,
            notificationDetails,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
        }
      }
    } catch (e) {
      Logger.error('Failed to schedule test notification', e);
    }
  }

  /// Cancel the scheduled test notification
  Future<void> cancelScheduledTestNotification() async {
    await cancelNotification(_testScheduledNotificationId);
  }

  /// Show a video-ready notification immediately (not scheduled).
  Future<void> showVideoReadyNotification({
    required String topicTitle,
    required String topicId,
    String? description,
    String? language,
    String? nativeLanguage,
    List<String>? wordsList,
    String? sessionId,
  }) async {
    if (!_isInitialized) return;

    try {
      final notificationId = topicId.hashCode;

      const AndroidNotificationDetails androidNotificationDetails =
          AndroidNotificationDetails(
            'video_ready',
            'Video Ready',
            channelDescription: 'Alert when long video generation completes',
            importance: Importance.high,
            priority: Priority.high,
            showWhen: true,
            icon: 'ic_notification',
          );

      const DarwinNotificationDetails darwinNotificationDetails =
          DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          );

      final NotificationDetails notificationDetails = NotificationDetails(
        android: androidNotificationDetails,
        iOS: darwinNotificationDetails,
      );

      final String payload = jsonEncode({
        'source': 'local',
        'route': 'video',
        'notification_type': 'video_ready',
        'topic_id': topicId,
        'topic_title': topicTitle,
        if (description != null) 'description': description,
        if (language != null) 'language': language,
        if (nativeLanguage != null) 'native_language': nativeLanguage,
        if (wordsList != null) 'words_list': wordsList,
        if (sessionId != null) 'session_id': sessionId,
      });

      await _flutterLocalNotificationsPlugin.show(
        notificationId,
        '🎬 Your Video is Ready!',
        '$topicTitle — start watching now',
        notificationDetails,
        payload: payload,
      );
    } catch (e) {
      Logger.error('Failed to show video-ready notification', e);
    }
  }

  /// Schedule a streak reminder with smart streak checking
  /// - Only sends if user hasn't completed daily streak (XP >= 10)
  /// - Includes streak count in message
  /// - Repeats daily at specified time
  Future<void> zonedScheduleStreakReminder(
    int notificationId,
    tz.TZDateTime scheduledDate,
    int reminderNumber, {
    String? customMessage,
  }) async {
    if (!_isInitialized) {
      return;
    }

    try {
      await _requestExactAlarmPermission();

      String message;
      if (customMessage != null) {
        message = customMessage;
      } else {
        // Fallback for backward compatibility
        final streak = await _getCurrentStreak();
        message =
            '🔥 Keep Your Streak Alive!\nYou have a $streak-day streak. Start learning now!';
      }

      const AndroidNotificationDetails androidNotificationDetails =
          AndroidNotificationDetails(
            'streak_reminders',
            'Streak Reminders',
            channelDescription:
                'Multiple daily reminders to maintain your learning streak',
            importance: Importance.high,
            priority: Priority.high,
            showWhen: true,
            icon: 'ic_notification',
          );

      const DarwinNotificationDetails darwinNotificationDetails =
          DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          );

      final NotificationDetails notificationDetails = NotificationDetails(
        android: androidNotificationDetails,
        iOS: darwinNotificationDetails,
      );

      final String payload = jsonEncode({
        'source': 'local',
        'route': 'home',
        'notification_type': 'streak_reminder',
        'reminder_number': reminderNumber,
      });

      await _flutterLocalNotificationsPlugin.zonedSchedule(
        notificationId,
        '🔥 Streak Reminder #$reminderNumber',
        message,
        scheduledDate,
        notificationDetails,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
      );
    } catch (e) {
      Logger.error(
        'Failed to zoned schedule streak reminder (id=$notificationId)',
        e,
      );
    }
  }
}
