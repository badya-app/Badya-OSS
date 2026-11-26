import 'dart:async';
import 'dart:convert';

import 'package:Badya/config/local_mode.dart';
import 'package:Badya/config/notification_constants.dart';
import 'package:Badya/utils/logger.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:Badya/services/notification_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Firebase Cloud Messaging Service for push notifications
///
/// Singleton: repeated constructions (e.g. account switches or repeated
/// AppInitializer.initializeServices calls) return the same instance so
/// message/token listeners are never registered more than once.
class FCMService extends ChangeNotifier {
  final FirebaseMessaging _firebaseMessaging;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FlutterLocalNotificationsPlugin? _localNotifications;

  static FCMService? _instance;

  /// Returns the shared [FCMService] instance, creating it on the first call.
  ///
  /// Dependencies given to the FIRST call are used; later calls return the
  /// existing instance and ignore their arguments, so account switches or
  /// repeated initializeServices calls never double-register listeners.
  factory FCMService({
    FirebaseMessaging? firebaseMessaging,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FlutterLocalNotificationsPlugin? localNotifications,
  }) {
    final existing = _instance;
    if (existing != null) {
      return existing;
    }
    return _instance = FCMService._internal(
      firebaseMessaging: firebaseMessaging,
      firestore: firestore,
      auth: auth,
      localNotifications: localNotifications,
    );
  }

  FCMService._internal({
    FirebaseMessaging? firebaseMessaging,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FlutterLocalNotificationsPlugin? localNotifications,
  }) : _firebaseMessaging = firebaseMessaging ?? FirebaseMessaging.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _localNotifications = localNotifications {
    _initialize();
  }

  String? _fcmToken;
  bool _isInitialized = false;

  /// Reentrancy guard so concurrent/duplicate init calls can't
  /// double-register listeners while the first init is still in flight.
  bool _isInitializing = false;

  String? get fcmToken => _fcmToken;
  bool get isInitialized => _isInitialized;

  /// Initialize FCM and set up message handlers
  Future<void> _initialize() async {
    if (LocalMode.enabled) return;
    // Singleton + guard: never register listeners twice.
    if (_isInitialized || _isInitializing) return;
    _isInitializing = true;
    try {
      // Request notification permission — but only if the user hasn't
      // explicitly dismissed the notification primer ("Not Now"). Requesting
      // unconditionally bypasses the primer's purpose and, on repeated denials,
      // can trigger openAppSettings on some Android devices.
      final prefs = await SharedPreferences.getInstance();
      final userAllowed = prefs.getBool('notifications_allowed') ?? false;
      if (userAllowed) {
        final status = await Permission.notification.status;
        if (status.isDenied || status.isPermanentlyDenied) {
          await _firebaseMessaging.requestPermission(
            alert: true,
            announcement: false,
            badge: true,
            carPlay: false,
            criticalAlert: false,
            provisional: false,
            sound: true,
          );
        }
      }

      // Get FCM token
      _fcmToken = await _firebaseMessaging.getToken();

      // Save token to Firestore
      if (_fcmToken != null) {
        await _saveTokenToFirestore(_fcmToken!);
      }

      // Handle token refresh
      _firebaseMessaging.onTokenRefresh.listen((newToken) async {
        _fcmToken = newToken;
        await _saveTokenToFirestore(newToken);
        notifyListeners();
      });

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle notification tap when app opened from background/terminated via FCM
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        if (message.data.isNotEmpty) {
          NotificationService().handleNotificationData(message.data);
        }
      });

      _firebaseMessaging.getInitialMessage().then((RemoteMessage? message) {
        if (message != null && message.data.isNotEmpty) {
          NotificationService().handleNotificationData(message.data);
        }
      });

      // Handle background message (needs to be a top-level function)
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      Logger.error('FCM initialization failed', e);
    } finally {
      _isInitializing = false;
    }
  }

  /// Save FCM token to Firestore under user's profile
  Future<void> _saveTokenToFirestore(String token) async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) {
        return;
      }

      final deviceInfo = DeviceInfoPlugin();
      String deviceName = 'Unknown Device';

      try {
        final androidInfo = await deviceInfo.androidInfo;
        deviceName = '${androidInfo.model} (${androidInfo.version.release})';
      } catch (e) {
        Logger.warn('Failed to get Android device info: $e');
      }

      await _firestore
          .collection('users')
          .doc(userId)
          .collection('fcmTokens')
          .doc(token)
          .set({
            'token': token,
            'deviceName': deviceName,
            'timestamp': FieldValue.serverTimestamp(),
            'platform': 'Android', // Could be determined dynamically
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      Logger.error('Failed to save FCM token to Firestore', e);
    }
  }

  /// Handle foreground messages
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    if (message.notification != null) {
      // You can show a local notification or navigate based on the message
      _showForegroundNotification(
        message.notification!.title ?? 'Badya',
        message.notification!.body ?? '',
        message.data,
      );
    }
  }

  /// Show a local notification for foreground messages
  Future<void> _showForegroundNotification(
    String title,
    String body,
    Map<String, dynamic> data,
  ) async {
    final localNotifications = _localNotifications;
    if (localNotifications == null) {
      Logger.warn('Local notifications plugin not available - cannot show foreground notification');
      return;
    }

    try {
      final String? route = data['route'] as String?;
      final String? notificationId = data['notification_id'] as String?;

      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'push_notifications',
        'Push Notifications',
        channelDescription: 'Push notifications from the server',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        icon: 'ic_notification',
      );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Encode route and all data info in payload for tap handling
      final String payload = jsonEncode({
        'source': 'fcm',
        ...data,
        if (route != null) 'route': route,
        if (notificationId != null) 'notification_id': notificationId,
      });

      await localNotifications.show(
        NotificationConstants.foregroundPushId,
        title,
        body,
        details,
        payload: payload,
      );

      Logger.info('Foreground push notification shown: $title');
    } catch (e) {
      Logger.error('Failed to show foreground notification', e);
    }
  }

  /// Get all stored FCM tokens for current user
  Future<List<String>> getStoredTokens() async {
    try {
      final userId = _auth.currentUser?.uid;
      if (userId == null) return [];

      final snapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('fcmTokens')
          .get();

      return snapshot.docs.map((doc) => doc.data()['token'] as String).toList();
    } catch (e) {
      Logger.error('Failed to get stored FCM tokens', e);
      return [];
    }
  }

  /// Manually refresh FCM token
  Future<String?> refreshToken() async {
    try {
      _fcmToken = await _firebaseMessaging.getToken();
      if (_fcmToken != null) {
        await _saveTokenToFirestore(_fcmToken!);
      }
      notifyListeners();
      return _fcmToken;
    } catch (e) {
      Logger.error('Failed to refresh FCM token', e);
      return null;
    }
  }

  /// Send a test message (for testing/debugging)
  Future<void> sendTestNotification({
    required String title,
    required String body,
  }) async {
    // This would typically be called from the backend
    // For testing, you can use Firebase Console or Cloud Functions
  }

  /// Subscribe to a topic for targeted notifications
  Future<void> subscribeToTopic(String topicName) async {
    try {
      await _firebaseMessaging.subscribeToTopic(topicName);
      notifyListeners();
    } catch (e) {
      Logger.error('Failed to subscribe to topic $topicName', e);
    }
  }

  /// Unsubscribe from a topic
  Future<void> unsubscribeFromTopic(String topicName) async {
    try {
      await _firebaseMessaging.unsubscribeFromTopic(topicName);
      notifyListeners();
    } catch (e) {
      Logger.error('Failed to unsubscribe from topic $topicName', e);
    }
  }

  /// Clean up resources
  @override
  void dispose() {
    super.dispose();
  }
}

/// Background message handler (must be a top-level function)
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (message.notification != null) {
    // FCM will automatically display the notification on Android
    // You can also trigger a local notification here if needed
  }
}
