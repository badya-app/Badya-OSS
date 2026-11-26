import 'dart:convert';

import 'package:Badya/config/local_mode.dart';
import 'package:Badya/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:Badya/services/notification_service.dart';
import 'package:Badya/services/notification_preferences_service.dart';
import 'package:Badya/services/notification_pool_service.dart';
import 'package:Badya/services/topic_suggestion_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EngagementNotificationScheduler {
  static const int _motivationBaseId = 300;
  static const int _topicSuggestionBaseId = 400;
  static const String _topicToggleKey = 'notification_toggle_topic_suggestions';
  static const String _motivationToggleKey = 'notification_toggle_motivation';

  final NotificationService _notificationService;
  final NotificationPreferencesService _prefsService;
  final NotificationPoolService _poolService = NotificationPoolService();
  final TopicSuggestionService _topicService = TopicSuggestionService();

  EngagementNotificationScheduler({
    required NotificationService notificationService,
    required NotificationPreferencesService preferencesService,
  }) : _notificationService = notificationService,
       _prefsService = preferencesService;

  Future<void> initialize() async {
    await scheduleAllNotifications();
  }

  Future<void> scheduleAllNotifications() async {
    if (!_notificationService.isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final topicToggle = prefs.getBool(_topicToggleKey) ?? true;
      final motivationToggle = prefs.getBool(_motivationToggleKey) ?? true;
      final masterToggle = await _prefsService.getMasterToggle();

      if (!masterToggle || (!topicToggle && !motivationToggle)) {
        await _cancelAllNotifications();
        return;
      }

      final startTime = await _prefsService.getStartTime();
      final endTime = await _prefsService.getEndTime();
      final selectedDays = await _prefsService.getNotificationDays();

      await _cancelAllNotifications();

      final times = _distributeTimesAcrossWindow(startTime, endTime, 2);
      if (times.length < 2) return;

      final userId = LocalMode.enabled
          ? LocalMode.guestUid
          : (FirebaseAuth.instance.currentUser?.uid ?? '');

      for (int day = 1; day <= 7; day++) {
        if (!selectedDays.contains(day.toString())) continue;

        if (topicToggle) {
          await _scheduleTopicSuggestion(userId, day, times[0]);
        }

        if (motivationToggle) {
          await _scheduleMotivation(day, times[1]);
        }
      }
    } catch (e) {
      Logger.error('Failed to schedule all notifications', e);
    }
  }

  Future<void> _scheduleTopicSuggestion(
    String userId,
    int dayOfWeek,
    TimeOfDay time,
  ) async {
    try {
      final topic = await _topicService.pickTopic(userId);
      if (topic == null) return;

      final notificationId = _topicSuggestionBaseId + (dayOfWeek - 1);
      final scheduledDate = _nextInstanceOfDayAndTime(dayOfWeek, time);

      final androidNotificationDetails = AndroidNotificationDetails(
        'topic_suggestions',
        'Topic Suggestions',
        channelDescription: 'Daily suggestions of relevant topics to learn',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        icon: 'ic_notification',
      );

      final darwinNotificationDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final notificationDetails = NotificationDetails(
        android: androidNotificationDetails,
        iOS: darwinNotificationDetails,
      );

      final body = topic.description.isNotEmpty
          ? topic.description
          : 'Check out this recommended topic';

      final payload = jsonEncode({
        'source': 'local',
        'route': 'home',
        'notification_type': 'topic_suggestion',
        'topic_id': topic.id,
        'content_id': topic.id,
      });

      await _notificationService.flutterLocalNotificationsPlugin.zonedSchedule(
        notificationId,
        '📖 Learn About ${topic.title}',
        body,
        scheduledDate,
        notificationDetails,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: payload,
      );
    } catch (e) {
      Logger.error('Failed to schedule topic suggestion (day=$dayOfWeek)', e);
    }
  }

  Future<void> _scheduleMotivation(int dayOfWeek, TimeOfDay time) async {
    try {
      final notificationId = _motivationBaseId + (dayOfWeek - 1);
      final scheduledDate = _nextInstanceOfDayAndTime(dayOfWeek, time);

      final message = await _poolService.getBestMessage(category: 'engagement');

      final androidNotificationDetails = AndroidNotificationDetails(
        'engagement_notifications',
        'Learning Reminders',
        channelDescription:
            'Periodic reminders to stay engaged with your learning',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        icon: 'ic_notification',
      );

      final darwinNotificationDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final notificationDetails = NotificationDetails(
        android: androidNotificationDetails,
        iOS: darwinNotificationDetails,
      );

      final payload = jsonEncode({
        'source': 'local',
        'route': 'home',
        'notification_type': 'motivation',
      });

      await _notificationService.flutterLocalNotificationsPlugin.zonedSchedule(
        notificationId,
        '🚀 Time for a Quick Lesson!',
        message,
        scheduledDate,
        notificationDetails,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: payload,
      );
    } catch (e) {
      Logger.error('Failed to schedule motivation (day=$dayOfWeek)', e);
    }
  }

  List<TimeOfDay> _distributeTimesAcrossWindow(
    TimeOfDay start,
    TimeOfDay end,
    int count,
  ) {
    if (count <= 0) return [];

    final times = <TimeOfDay>[];

    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;

    int windowMinutes;
    if (startMinutes <= endMinutes) {
      windowMinutes = endMinutes - startMinutes;
    } else {
      windowMinutes = (24 * 60 - startMinutes) + endMinutes;
    }

    if (count == 1) {
      final midMinutes = (startMinutes + (windowMinutes ~/ 2)) % (24 * 60);
      times.add(TimeOfDay(hour: midMinutes ~/ 60, minute: midMinutes % 60));
    } else {
      final interval = windowMinutes ~/ count;

      for (int i = 0; i < count; i++) {
        final offsetMinutes =
            (startMinutes + (interval * i) + (interval ~/ 2)) % (24 * 60);
        times.add(
          TimeOfDay(hour: offsetMinutes ~/ 60, minute: offsetMinutes % 60),
        );
      }
    }

    return times;
  }

  tz.TZDateTime _nextInstanceOfDayAndTime(int dayOfWeek, TimeOfDay time) {
    final now = tz.TZDateTime.now(tz.local);

    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );

    while (scheduledDate.weekday != dayOfWeek) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    if (scheduledDate.isBefore(now) || scheduledDate.isAtSameMomentAs(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 7));
    }

    return scheduledDate;
  }

  Future<void> _cancelAllNotifications() async {
    try {
      for (int i = 0; i < 70; i++) {
        await _notificationService.cancelNotification(300 + i);
      }
      for (int i = 0; i < 7; i++) {
        await _notificationService.cancelNotification(
          _topicSuggestionBaseId + i,
        );
      }
    } catch (e) {
      Logger.error('Failed to cancel engagement notifications', e);
    }
  }
}
