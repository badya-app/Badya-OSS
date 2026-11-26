import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:Badya/services/notification_service.dart';
import 'package:Badya/utils/topic_action_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression tests for the notification tap pipeline:
///
///  - Task 1: cold-start launch payload is dispatched exactly once, even when
///    [checkAppLaunchNotification] is invoked concurrently (constructor chain +
///    AppInitializer's deferred callback).
///  - Task 3: payloads arriving while the navigator is detached are stashed
///    and flushed exactly once later (FCM cold-start path included).
///  - Task 2: the auth-restore wait resolves when a session appears and gives
///    up (returning null) on timeout.
///  - Task 4: [TopicActionHelper.showTopicSheetById] fails silently for stale
///    notification topics when [silentOnError] is set.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Value returned by the (mocked) local-notifications plugin when asked for
  /// launch details. Shape mirrors flutter_local_notifications' platform
  /// contract (see AndroidMethodChannelFlutterLocalNotificationsPlugin).
  Map<dynamic, dynamic>? launchDetailsResult;

  const localNotificationsChannel =
      MethodChannel('dexterous.com/flutter/local_notifications');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(localNotificationsChannel,
          (MethodCall methodCall) async {
    if (methodCall.method == 'initialize') return true;
    if (methodCall.method == 'getNotificationAppLaunchDetails') {
      return launchDetailsResult;
    }
    if (methodCall.method == 'requestPermission' ||
        methodCall.method == 'requestPermissions' ||
        methodCall.method == 'requestExactAlarmsPermission') {
      return true;
    }
    return null;
  });

  const customNotificationChannel = MethodChannel('com.badya.app/notifications');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(customNotificationChannel,
          (MethodCall methodCall) async {
    if (methodCall.method == 'getLocalTimezone') return 'UTC';
    return null;
  });

  /// Constructs the singleton and waits until its internal init chain
  /// (including its own checkAppLaunchNotification call) has fully settled,
  /// so tests can safely reset dispatch state afterwards.
  Future<NotificationService> quiescedService(WidgetTester tester) async {
    final service = NotificationService();
    // Drain microtasks/frames until initialization and its internal
    // launch-check have completed.
    var spins = 0;
    while ((!service.isInitialized || service.pendingLaunchCheckInFlight) &&
        spins < 50) {
      await tester.pump(const Duration(milliseconds: 10));
      spins++;
    }
    await tester.pump();
    await tester.pump();
    return service;
  }

  Map<dynamic, dynamic> launchDetailsWith(String payload) => {
        'notificationLaunchedApp': true,
        'notificationResponse': {
          'notificationId': 1,
          'actionId': null,
          'input': null,
          'notificationResponseType':
              0, // NotificationResponseType.selectedNotification
          'payload': payload,
        },
      };

  Widget appWithNavigator() => MaterialApp(
        navigatorKey: NotificationService.navigatorKey,
        home: const Scaffold(body: SizedBox.shrink()),
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    launchDetailsResult = null;
  });

  group('cold-start dispatch-once guard (Task 1)', () {
    testWidgets('concurrent checkAppLaunchNotification calls dispatch the '
        'launch payload exactly once', (tester) async {
      final service = await quiescedService(tester);
      service.debugResetDispatchState();

      // Detach the navigator after this test so state doesn't leak.
      addTearDown(() => tester.pumpWidget(const SizedBox()));

      // Simulate an app launched by tapping a local notification.
      launchDetailsResult = launchDetailsWith(
        '{"source":"local","route":"home","notification_type":"streak_reminder"}',
      );

      await tester.pumpWidget(appWithNavigator());

      // Fire two checks without awaiting the first — mirrors the race between
      // the singleton's constructor chain and AppInitializer's callback.
      final f1 = service.checkAppLaunchNotification();
      final f2 = service.checkAppLaunchNotification();
      await Future.wait([f1, f2]);
      await tester.pump();

      expect(NotificationService.debugDispatchedTapCount, 1);

      // Further calls must not re-dispatch the same payload either.
      await service.checkAppLaunchNotification();
      await tester.pump();
      expect(NotificationService.debugDispatchedTapCount, 1);
    });
  });

  group('pending payload stash / flush (Task 3)', () {
    testWidgets('payload stashed while navigator is absent is flushed exactly '
        'once once the navigator attaches', (tester) async {
      final service = await quiescedService(tester);
      service.debugResetDispatchState();

      // Detach the navigator after this test so state doesn't leak.
      addTearDown(() => tester.pumpWidget(const SizedBox()));

      // No MaterialApp pumped yet -> navigatorKey.currentState is null.
      expect(NotificationService.navigatorKey.currentState, isNull);

      service.handleNotificationPayload(
        '{"source":"fcm","route":"home","notification_type":"topic_suggestion",'
        '"topic_id":"topic-123"}',
      );
      await tester.pump();
      // Stashed, NOT dispatched.
      expect(NotificationService.debugDispatchedTapCount, 0);

      // Navigator attaches.
      await tester.pumpWidget(appWithNavigator());

      await service.checkAppLaunchNotification();
      await tester.pump();
      expect(NotificationService.debugDispatchedTapCount, 1);

      // Repeated/concurrent calls must not double-flush.
      await service.checkAppLaunchNotification();
      await tester.pump();
      expect(NotificationService.debugDispatchedTapCount, 1);
    });
  });

  group('auth-restore wait (Task 2)', () {
    test('waitForUserIdFrom resolves once a session appears', () async {
      final controller = StreamController<String?>();

      final future = TopicActionHelper.waitForUserIdFrom(
        controller.stream,
        timeout: const Duration(seconds: 5),
      );

      // Session is still restoring…
      controller.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // …then Firebase emits the restored user.
      controller.add('user-42');

      expect(await future, 'user-42');
      await controller.close();
    });

    test('waitForUserIdFrom returns null when the session never restores',
        () async {
      final controller = StreamController<String?>();

      final result = await TopicActionHelper.waitForUserIdFrom(
        controller.stream,
        timeout: const Duration(milliseconds: 50),
      );

      expect(result, isNull);
      await controller.close();
    });
  });

  group('silent error handling (Task 4)', () {
    testWidgets('showTopicSheetById with silentOnError fails quietly for a '
        'missing topic', (tester) async {
      final service = NotificationService();
      service.debugResetDispatchState();

      late BuildContext capturedContext;
      final contextKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: NotificationService.navigatorKey,
          home: Builder(
            key: contextKey,
            builder: (context) {
              capturedContext = context;
              return const Scaffold(body: SizedBox.shrink());
            },
          ),
        ),
      );
      expect(capturedContext.mounted, isTrue);

      // Firestore is unavailable in this environment, so content lookup fails.
      // With silentOnError the helper must swallow the failure (no toast) and
      // simply return false.
      final result = await TopicActionHelper.showTopicSheetById(
        context: capturedContext,
        contentId: 'stale-topic-id',
        silentOnError: true,
      );
      expect(result, isFalse);
    });
  });
}