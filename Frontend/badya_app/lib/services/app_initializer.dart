import 'package:Badya/config/local_mode.dart';
import 'package:Badya/services/cache_service.dart';
import 'package:Badya/services/content_service.dart';
import 'package:Badya/services/engagement_notification_scheduler.dart';
import 'package:Badya/services/fcm_service.dart';
import 'package:Badya/services/migration_service.dart';
import 'package:Badya/services/notification_preferences_service.dart';
import 'package:Badya/services/notification_service.dart';
import 'package:Badya/services/notification_pool_service.dart';
import 'package:Badya/services/streak_completion_handler.dart';
import 'package:Badya/services/streak_reminder_manager.dart';
import 'package:Badya/utils/logger.dart';
import 'package:Badya/utils/score_service.dart';
import 'package:Badya/widgets/notification_primer_sheet.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppInitializer {
  static Future<void> initializeServices(String uid) async {
    try {
      Logger.info('Initializing services for user: $uid');

      // 1. Migration (fast, critical)
      await MigrationService().migrateIfNeeded();

      // 2. Register a shared CacheService with ContentService so the
      //    `metadata/tag_counts` and recommendations caches are usable from
      //    every `ContentService()` call site (not just the one that has
      //    explicit DI in tests). Idempotent — safe to call from here and
      //    also from main(); the second call simply re-registers the same
      //    instance.
      try {
        final prefs = await SharedPreferences.getInstance();
        final cache = CacheService(prefs);
        await cache.clearExpired();
        ContentService.registerSharedCacheService(cache);
      } catch (e) {
        Logger.warn('Failed to register shared CacheService: $e');
      }

      Logger.info('Core services initialized');

      // 3. Defer everything else to after first frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initializeDeferredServices(uid);
      });
    } catch (e) {
      Logger.error('Core service initialization failed', e);
    }
  }

  static Future<void> _initializeDeferredServices(String uid) async {
    try {
      Logger.info('Initializing deferred services...');

      final notificationService = NotificationService();

      // Check if launched via notification response (cold start).
      // Runs FIRST and unconditionally: this both dispatches the cold-start
      // launch payload and flushes anything stashed while the navigator was
      // attaching. Doing it before the (awaited) primer sheet prevents a
      // tapped-notification action from being stuck behind that modal.
      await notificationService.checkAppLaunchNotification();

      // Show notification primer if user is onboarded and hasn't seen it yet
      await _showNotificationPrimerIfNeeded(uid);

      // Notification pool
      final poolService = NotificationPoolService();
      await poolService.initialize();

      // Keep the stored streak fresh on every app launch — a missed day
      // zeroes it even when the user opens the app without completing a
      // lesson (otherwise the profile/home would keep showing the stale
      // Firestore value).
      await ScoreService.refreshStreak();

      // Streak management
      final streakReminderManager = StreakReminderManager(
        notificationService: notificationService,
      );
      await streakReminderManager.initialize();
      StreakCompletionHandler.initialize(streakReminderManager);

      // Engagement scheduling
      final preferencesService = NotificationPreferencesService();
      final engagementScheduler = EngagementNotificationScheduler(
        notificationService: notificationService,
        preferencesService: preferencesService,
      );
      await engagementScheduler.initialize();

      // Push notifications (FCM) — pass local notifications plugin for
      // foreground handling. FCMService is a singleton: on account switches /
      // repeated initializeServices calls this returns the existing instance,
      // so listeners are not registered twice.
      if (!LocalMode.enabled) {
        FCMService(
          localNotifications:
              notificationService.flutterLocalNotificationsPlugin,
        );
      }

      Logger.info('Deferred services initialized successfully');
    } catch (e) {
      Logger.error('Deferred service initialization failed', e);
    }
  }

  static Future<void> _showNotificationPrimerIfNeeded(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final onboarded = prefs.getBool('is_onboarded_$uid') ?? false;
      final primerShown =
          prefs.getBool('has_shown_notification_primer') ?? false;
      if (!onboarded || primerShown) return;

      // Mark the primer as shown BEFORE displaying it. The sheet can be
      // dismissed by swiping down or tapping outside (which skips its
      // Allow / Not Now buttons), so saving the flag only on button taps
      // made the primer reappear at every login.
      await prefs.setBool('has_shown_notification_primer', true);

      final context = NotificationService.navigatorKey.currentContext;
      if (context == null || !context.mounted) return;

      await showModalBottomSheet(
        context: context,
        backgroundColor: Theme.of(context).cardTheme.color,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        isScrollControlled: true,
        builder: (_) => const NotificationPrimerSheet(),
      );
    } catch (e) {
      Logger.error('Failed to show notification primer', e);
    }
  }

  static Future<bool> checkOnboardingStatus(String uid) async {
    final prefs = await SharedPreferences.getInstance();

    // Check local cache first
    final localFlag = prefs.getBool('is_onboarded_$uid') ?? false;
    if (localFlag || LocalMode.enabled) return localFlag;

    // Check Firestore (source of truth)
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (userDoc.exists && userDoc.data()?['is_onboarded'] == true) {
        await prefs.setBool('is_onboarded_$uid', true);
        return true;
      }
    } catch (e) {
      Logger.error('Error checking onboarding status', e);
    }

    return false;
  }
}
