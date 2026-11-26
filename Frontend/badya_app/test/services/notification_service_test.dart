import 'package:flutter_test/flutter_test.dart';
import 'package:Badya/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:Badya/utils/score_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
    if (methodCall.method == 'initialize') return true;
    if (methodCall.method == 'requestPermission' ||
        methodCall.method == 'requestPermissions' ||
        methodCall.method == 'requestExactAlarmsPermission') return true;
    if (methodCall.method == 'show') return null;
    if (methodCall.method == 'cancel') return null;
    if (methodCall.method == 'cancelAll') return null;
    if (methodCall.method == 'zonedSchedule' || methodCall.method == 'periodicallyShow') return null;
    if (methodCall.method == 'pendingNotificationRequests') return <dynamic>[];
    if (methodCall.method == 'getActiveNotifications') return <dynamic>[];
    return null;
  });

  const permissionChannel = MethodChannel('flutter.baseflow.com/permissions/methods');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(permissionChannel, (MethodCall methodCall) async {
    return <int, int>{
      0: 1,
      1: 1,
      17: 1,
    };
  });

  const customNotificationChannel = MethodChannel('com.badya.app/notifications');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(customNotificationChannel, (MethodCall methodCall) async {
    if (methodCall.method == 'getLocalTimezone') return 'UTC';
    return null;
  });

  group('NotificationService Tests', () {
    late NotificationService notificationService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final fakeFirestore = FakeFirebaseFirestore();
      ScoreService.firestoreInstance = fakeFirestore;
      ScoreService.authInstance = MockFirebaseAuth(signedIn: true);
      notificationService = NotificationService();
    });

    test('NotificationService initializes correctly', () async {
      // Give it a moment to initialize
      await Future.delayed(const Duration(milliseconds: 500));
      expect(notificationService.isInitialized, isTrue);
    });

    test('requestNotificationPermission returns a boolean on Android', () async {
      final result = await notificationService.requestNotificationPermission();
      expect(result, isA<bool>());
    });

    test('scheduleStreakReminder schedules without error', () async {
      final timeOfDay = const TimeOfDay(hour: 19, minute: 0); // 7 PM
      
      // This should not throw
      await notificationService.scheduleStreakReminder(timeOfDay);
      
      // Give it time to schedule
      await Future.delayed(const Duration(milliseconds: 500));
    });

    test('scheduleStreakFreezeWarning schedules without error', () async {
      // This should not throw
      await notificationService.scheduleStreakFreezeWarning();
      
      // Give it time to schedule
      await Future.delayed(const Duration(milliseconds: 500));
    });

    test('cancelAllNotifications completes without error', () async {
      await notificationService.cancelAllNotifications();
      
      // Should complete successfully
      expect(true, isTrue);
    });

    test('cancelNotification with valid ID completes without error', () async {
      await notificationService.cancelNotification(1);
      
      // Should complete successfully
      expect(true, isTrue);
    });

    test('showTestNotification displays without error', () async {
      await notificationService.showTestNotification();
      
      // Should complete successfully
      expect(true, isTrue);
    });

    test('handleNotificationPayload handles topic suggestion payload gracefully', () async {
      final payload = '{"source":"local","route":"home","notification_type":"topic_suggestion","topic_id":"topic-123"}';
      // Should not throw even without navigator attached
      expect(() => notificationService.handleNotificationPayload(payload), returnsNormally);
    });

    test('handleNotificationPayload handles video_ready payload gracefully', () async {
      final payload = '{"source":"local","route":"video","notification_type":"video_ready","topic_id":"topic-123","topic_title":"Sample Video"}';
      expect(() => notificationService.handleNotificationPayload(payload), returnsNormally);
    });
  });
}
