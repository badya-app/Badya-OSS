import 'package:Badya/utils/level_service.dart';
import 'package:Badya/utils/score_service.dart';
import 'package:Badya/services/coin_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Profile Lesson Integration Tests (Task 12.3)', () {
    late FakeFirebaseFirestore fakeFirestore;
    late MockFirebaseAuth mockAuth;
    late String testUserId;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      fakeFirestore = FakeFirebaseFirestore();
      mockAuth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'test_user_integration'),
        signedIn: true,
      );
      testUserId = mockAuth.currentUser!.uid;

      LevelService.firestoreInstance = fakeFirestore;
      LevelService.enableCoinAwards = true;
      ScoreService.firestoreInstance = fakeFirestore;
      ScoreService.authInstance = mockAuth;
      CoinService.firestoreInstance = fakeFirestore;
      CoinService.authInstance = mockAuth;

      // Initialize user document
      await fakeFirestore.collection('users').doc(testUserId).set({
        'total_xp': 0,
        'level': 1,
        'coin_balance': 0,
        'language_xp': {},
      });
    });

    test(
        'Completing a lesson updates XP, level, coins, and daily activity',
        () async {
      // Save a lesson score (this should trigger XP, level, and daily activity updates)
      await ScoreService.saveLessonScore(
        testUserId,
        'topic1',
        'English',
        'story_weaver',
        85,
        wordScores: {'hello': 90, 'world': 80},
      );

      // Wait for async operations
      await Future.delayed(const Duration(milliseconds: 500));

      // Check user document was updated
      final userDoc =
          await fakeFirestore.collection('users').doc(testUserId).get();
      expect(userDoc.exists, true);

      final userData = userDoc.data()!;
      expect(userData['total_xp'], greaterThan(0));
      expect(userData['level'], greaterThan(1));

      // Check progress document was created
      final progressDoc = await fakeFirestore
          .collection('users')
          .doc(testUserId)
          .collection('progress')
          .doc('topic1_English')
          .get();
      expect(progressDoc.exists, true);
      expect(progressDoc.data()!['lessons']['story_weaver'], 85);

      // Check daily activity was created
      final today = DateTime.now().toUtc();
      final dateStr =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final dailyActivityDoc = await fakeFirestore
          .collection('users')
          .doc(testUserId)
          .collection('daily_activity')
          .doc(dateStr)
          .get();
      expect(dailyActivityDoc.exists, true);
      final dailyData = dailyActivityDoc.data()!;
      expect(dailyData['lessons_completed'], greaterThan(0));
      expect(dailyData['xp_earned'], greaterThan(0));
    });

    test('Level-up awards coins correctly', () async {
      // Set user to level 1 with XP just below level 2 threshold
      await fakeFirestore.collection('users').doc(testUserId).update({
        'total_xp': 40, // Just below level 2 (50 XP)
        'level': 1,
      });

      // Add XP to trigger level-up
      await LevelService.addXP(testUserId, 20);

      // Wait for async operations
      await Future.delayed(const Duration(milliseconds: 500));

      // Check level increased
      final userDoc =
          await fakeFirestore.collection('users').doc(testUserId).get();
      final userData = userDoc.data()!;
      expect(userData['level'], greaterThan(1));

      // Check coins were awarded (level 2 = 2 * 15 = 30 coins)
      expect(userData['coin_balance'], greaterThan(0));
    });
  });
}

