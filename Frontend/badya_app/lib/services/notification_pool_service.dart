import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:Badya/models/notification_message.dart';
import 'package:Badya/utils/score_service.dart';
import 'package:Badya/config/local_mode.dart';
import 'package:Badya/utils/logger.dart';

/// Manages a pool of notification messages from Firestore.
/// Features:
/// - Context-aware selection (streak, weak words, performance)
/// - Auto-seeding of initial 30+ messages
/// - Weight-based random selection
/// - Template placeholder replacement
class NotificationPoolService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;

  // Cache the pool in-memory for the session to minimize reads
  List<NotificationMessage>? _cachedPool;

  // Cache streak and summary to avoid redundant users/{uid} reads
  int? _cachedStreak;
  String? _cachedSummary;
  String? _cachedUserId;

  static final NotificationPoolService _instance =
      NotificationPoolService._internal();
  factory NotificationPoolService() => _instance;
  NotificationPoolService._internal();

  /// Initialize the service — fetches messages from Firestore (source of truth).
  /// No auto-seeding: messages are managed directly in Firebase Console.
  Future<void> initialize() async {
    if (LocalMode.enabled) return;
    Logger.info('--- Initializing NotificationPoolService ---');
    await _fetchPool();
    if (_cachedPool == null || _cachedPool!.isEmpty) {
      Logger.warn(
        'Notification pool is EMPTY. Add messages via Firebase Console → Firestore → notification_messages collection.',
      );
    } else {
      Logger.info(
        'Notification pool initialized with ${_cachedPool!.length} messages.',
      );
    }
  }

  /// Fetches messages from the root collection 'notification_messages'.
  /// Limited to 100 — enough for weighted random selection; prevents unbounded
  /// downloads if the pool grows large over time.
  Future<void> _fetchPool() async {
    try {
      final snapshot = await _firestore
          .collection('notification_messages')
          .withConverter<NotificationMessage>(
            fromFirestore: NotificationMessage.fromFirestore,
            toFirestore: (msg, _) => msg.toFirestore(),
          )
          .limit(100)
          .get();

      _cachedPool = snapshot.docs.map((doc) => doc.data()).toList();
      Logger.info(
        'Fetched ${_cachedPool?.length} notification messages from pool',
      );
    } catch (e) {
      Logger.error('Failed to fetch notification pool', e);
    }
  }

  /// Picks the best message from the pool based on user context
  Future<String> getBestMessage({required String category}) async {
    if (_cachedPool == null || _cachedPool!.isEmpty) {
      return _getHardcodedFallback(category);
    }

    // 1. Gather context (cached per session; streak/summary don't change mid-session)
    final uid = _auth.currentUser?.uid ?? '';
    if (uid != _cachedUserId) {
      _cachedStreak = null;
      _cachedSummary = null;
      _cachedUserId = uid;
    }
    final streak = _cachedStreak ??= await ScoreService.getStreak();
    final summary = _cachedSummary ??=
        await ScoreService.getLatestPerformanceSummary(uid, '');
    final userName = _auth.currentUser?.displayName ?? 'Learner';

    // 2. Filter pool by category
    var candidates = _cachedPool!.where((m) => m.category == category).toList();
    if (candidates.isEmpty) {
      candidates = _cachedPool!
          .where((m) => m.category == 'engagement')
          .toList();
    }

    // 3. Filter by streak constraints
    candidates = candidates.where((m) {
      final minMatch = m.minStreak == null || streak >= m.minStreak!;
      final maxMatch = m.maxStreak == null || streak <= m.maxStreak!;
      return minMatch && maxMatch;
    }).toList();

    if (candidates.isEmpty) return _getHardcodedFallback(category);

    // 5. Weighted Random Selection
    final totalWeight = candidates.fold<double>(
      0,
      (sum, m) => sum + m.priority,
    );
    final randomValue = Random().nextDouble() * totalWeight;

    double currentSum = 0;
    NotificationMessage selected = candidates.first;
    for (final m in candidates) {
      currentSum += m.priority;
      if (randomValue <= currentSum) {
        selected = m;
        break;
      }
    }

    // 6. Template Placeholder Replacement
    return _processTemplate(selected.text, {
      'streak': streak.toString(),
      'next_streak': (streak + 1).toString(),
      'username': userName,
      'summary': summary ?? 'doing great',
    });
  }

  String _processTemplate(String template, Map<String, String> values) {
    String result = template;
    values.forEach((key, value) {
      result = result.replaceAll('{$key}', value);
    });
    return result;
  }

  /// Hardcoded fallback in case of network failure or empty pool
  String _getHardcodedFallback(String category) {
    switch (category) {
      case 'streak':
        return 'Keep your streak alive! 🔥';
      case 'engagement':
        return 'Time for a quick learning session! 🚀';
      default:
        return 'Ready to level up your knowledge? 🎯';
    }
  }
}
