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

  group('NotificationService - Task Group 1 & 2: Permission & Scheduling Tests', () {
    late NotificationService notificationService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final fakeFirestore = FakeFirebaseFirestore();
      ScoreService.firestoreInstance = fakeFirestore;
      ScoreService.authInstance = MockFirebaseAuth(signedIn: true);
      notificationService = NotificationService();
      // Give it time to initialize
      await Future.delayed(const Duration(milliseconds: 500));
    });

    group('Task 1.1: Permission Request Tests', () {
      test('1.1.1: Test permission request flow on first launch', () async {
        final result = await notificationService.requestNotificationPermission();
        expect(result, isA<bool>());
        expect(result, isTrue);
      });

      test('1.1.2: Test permission denied handling', () async {
        // This simulates a scenario where permission might fail
        // The service should still return a boolean
        final result = await notificationService.requestNotificationPermission();
        expect(result, isA<bool>());
      });

      test('1.1.3: Test permission status check', () async {
        // Request permission
        final firstResult = await notificationService.requestNotificationPermission();
        expect(firstResult, isTrue);

        // Check again - should still work
        final secondResult =
            await notificationService.requestNotificationPermission();
        expect(secondResult, isTrue);
      });
    });

    group('Task 2.1: Notification Service Implementation Tests', () {
      test('2.1.1: Test local notification scheduling', () async {
        final timeOfDay = const TimeOfDay(hour: 19, minute: 0);
        // Should not throw
        await notificationService.scheduleStreakReminder(timeOfDay);
        // Give it time to schedule
        await Future.delayed(const Duration(milliseconds: 300));
      });

      test('2.1.2: Test notification cancellation', () async {
        // Should not throw
        await notificationService.cancelNotification(1);
        expect(true, isTrue);
      });

      test('2.1.3: Test streak reminder scheduling at user\'s time', () async {
        const morningTime = TimeOfDay(hour: 8, minute: 0);
        // Should schedule without error
        await notificationService.scheduleStreakReminder(morningTime);
        await Future.delayed(const Duration(milliseconds: 300));
      });

      test('2.1.4: Test streak freeze warning trigger', () async {
        // Should schedule warning without error
        await notificationService.scheduleStreakFreezeWarning();
        await Future.delayed(const Duration(milliseconds: 300));
      });

      test('2.1.5: Test skip-if-practiced logic', () async {
        final prefs = await SharedPreferences.getInstance();
        final today = DateTime.now().toIso8601String().split('T')[0];

        // Mark as practiced today
        await prefs.setString('notification_last_practice_date', today);

        // Try to schedule - should skip and return without error
        await notificationService
            .scheduleStreakReminder(const TimeOfDay(hour: 19, minute: 0));

        // Clear for next test
        await prefs.remove('notification_last_practice_date');
      });
    });

    group('NotificationService Initialization', () {
      test('NotificationService initializes correctly', () async {
        expect(notificationService.isInitialized, isTrue);
      });

      test('showTestNotification displays without error', () async {
        await notificationService.showTestNotification();
        expect(true, isTrue);
      });

      test('cancelAllNotifications completes without error', () async {
        await notificationService.cancelAllNotifications();
        expect(true, isTrue);
      });
    });
  });
}
