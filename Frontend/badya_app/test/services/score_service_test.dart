import 'package:Badya/utils/score_service.dart';
import 'package:Badya/utils/level_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ScoreService', () {
    late FakeFirebaseFirestore fakeFirestore;

    setUp(() async {
      fakeFirestore = FakeFirebaseFirestore();
      ScoreService.firestoreInstance = fakeFirestore;
      LevelService.firestoreInstance = fakeFirestore;
      final mockAuth = MockFirebaseAuth(signedIn: true);
      ScoreService.authInstance = mockAuth;
      LevelService.enableCoinAwards = false;
      SharedPreferences.setMockInitialValues({});

      // Initialize user document
      await fakeFirestore.collection('users').doc('user1').set({
        'language_xp': {},
        'total_xp': 0,
      });
    });

    test('saveLessonScore saves to progress collection', () async {
      await ScoreService.saveLessonScore(
        'user1',
        'topic1',
        'English',
        'rolePlay',
        85,
        wordScores: {'hello': 90},
      );

      final doc = await fakeFirestore
          .collection('users')
          .doc('user1')
          .collection('progress')
          .doc('topic1_English')
          .get();

      expect(doc.exists, true);
      expect(doc.data()!['lessons']['rolePlay'], 85);
      expect(doc.data()!['word_scores']['hello'], 90);
    });    test('updateWordPriority is deprecated and is now a no-op',
      () async {
        await ScoreService.updateWordPriority(
          'user1',
          'topic1',
          'English',
          {
            'hard_word': 40,
            'easy_word': 90,
          },
        );

        // The method is now a no-op, so the document should NOT exist.
        final doc = await fakeFirestore
            .collection('users')
            .doc('user1')
            .collection('topics')
            .doc('topic1_English')
            .get();

        expect(doc.exists, false);
      },
    );

    test(
      'getRecentVocabulary returns empty list (vocabulary collection deprecated)',
      () async {
        final vocabWords = await ScoreService.getRecentVocabulary(
          'user1',
          'English',
        );

        expect(vocabWords, isEmpty);
      },
    );

    test('saveAnalysisResult updates user document', () async {
      final result = AnalysisResult(
        userPerformanceSummary: 'Great job!',
        languageLevel: '',
        understandingPercentage: 80,
        expressionPercentage: 90,
        communicationPercentage: 85,
        wordScores: {},
      );

      await ScoreService.saveAnalysisResult(
        'user1',
        'topic1',
        'English',
        result,
      );

      final userDoc = await fakeFirestore
          .collection('users')
          .doc('user1')
          .get();
      // Per-language storage: stored under the language key
      expect(
        (userDoc.data()!['last_performance_summary'] as Map)['English'],
        'Great job!',
      );
    });

    test(
      'new scoring logic: lesson avg words, topic avg lessons, language sum topics',
      () async {
        // 1. Initial lesson: hello=100, world=50 -> Lesson avg = 75
        final result1 = AnalysisResult(
          userPerformanceSummary: 'Good',
          languageLevel: '',
          understandingPercentage: 100,
          expressionPercentage: 100,
          communicationPercentage: 100,
          wordScores: {'hello': 100, 'world': 50},
        );

        final lessonScore1 = ScoreService.calculateLessonScore(
          result1,
          LessonType.storyWeaver,
        );
        // Formula for storyWeaver: understanding*0.50 + expression*0.30 + communication*0.20
        // = 100*0.50 + 100*0.30 + 100*0.20 = 50 + 30 + 20 = 100
        expect(lessonScore1, 100);

        await ScoreService.saveLessonScore(
          'user1',
          'topic1',
          'English',
          'story_weaver',
          lessonScore1,
          wordScores: result1.wordScores,
        );

        // Topic1 score should be 25 (100 / 4.0 = 25.0 -> 25)
        final topic1Doc = await fakeFirestore
            .collection('users')
            .doc('user1')
            .collection('progress')
            .doc('topic1_English')
            .get();
        expect(topic1Doc.data()!['topic_score'], 25);

        // XP awarded via _updateLanguageXp, stored in language_xp bucket
        final userDoc = await fakeFirestore
            .collection('users')
            .doc('user1')
            .get();
        // XP awarded via _updateLanguageXp, stored in language_xp bucket
        expect(userDoc.data()!['language_xp']['English'], greaterThan(0));

        // 2. Second lesson in same topic: role_master=25 -> Topic1 avg = (100 + 25 + 0 + 0) / 4 = 31.25 -> 31
        await ScoreService.saveLessonScore(
          'user1',
          'topic1',
          'English',
          'role_master',
          25,
        );

        final topic1DocUpdated = await fakeFirestore
            .collection('users')
            .doc('user1')
            .collection('progress')
            .doc('topic1_English')
            .get();
        expect(topic1DocUpdated.data()!['topic_score'], 31);
        expect(topic1DocUpdated.data()!['lessons']['story_weaver'], 100);
        expect(topic1DocUpdated.data()!['lessons']['role_master'], 25);

        // 3. Different topic: topic2 score = 25 (100 / 4) -> Language score English = 29 + 25 = 54
        await ScoreService.saveLessonScore(
          'user1',
          'topic2',
          'English',
          'story_weaver',
          100,
        );

        final userDocFinal = await fakeFirestore
            .collection('users')
            .doc('user1')
            .get();
        // XP is now stored in language_xp buckets, not language_scores
        expect(userDocFinal.data()!['language_xp']['English'], greaterThan(0));

        // total_xp is now driven by LevelService and XP multipliers, not just
        // the raw sum of language scores, so we only assert that it exists
        // and is positive.
        expect(
          (userDocFinal.data()!['total_xp'] as num?)?.toInt() ?? 0,
          greaterThan(0),
        );
      },
    );

    test('awardMiniGameXp updates total, per-language, and daily XP',
        () async {
      await ScoreService.awardMiniGameXp('English', 5, userId: 'user1');

      final userDoc =
          await fakeFirestore.collection('users').doc('user1').get();
      expect(userDoc.data()!['total_xp'], 5);
      expect(userDoc.data()!['language_xp']['English'], 5);

      // Daily activity should reflect the earned XP for today (UTC).
      final nowUtc = DateTime.now().toUtc();
      final id =
          '${nowUtc.year.toString().padLeft(4, '0')}-${nowUtc.month.toString().padLeft(2, '0')}-${nowUtc.day.toString().padLeft(2, '0')}';
      final activityDoc = await fakeFirestore
          .collection('users')
          .doc('user1')
          .collection('daily_activity')
          .doc(id)
          .get();
      expect(activityDoc.exists, true);
      expect(activityDoc.data()!['xp_earned'], 5);
      expect(activityDoc.data()!['by_language']['English']['xp_earned'], 5);
    });

    test('awardMiniGameXp ignores non-positive deltas', () async {
      await ScoreService.awardMiniGameXp('English', 0, userId: 'user1');
      await ScoreService.awardMiniGameXp('English', -3, userId: 'user1');

      final userDoc =
          await fakeFirestore.collection('users').doc('user1').get();
      expect(userDoc.data()!['total_xp'], 0);
      expect(userDoc.data()!['language_xp'], isEmpty);
    });

    test('xpSnapshotStream reflects XP the moment it is awarded', () async {
      final initial = await ScoreService.xpSnapshotStream('user1').first;
      expect(initial.totalXp, 0);
      expect(initial.streak, 0);
      expect(initial.languageXp, isEmpty);

      await ScoreService.awardMiniGameXp('English', 5, userId: 'user1');

      // A new subscriber immediately sees the updated values — this is how
      // Home/Profile pick up game XP without a manual refresh.
      final updated = await ScoreService.xpSnapshotStream('user1').first;
      expect(updated.totalXp, 5);
      expect(updated.languageXp['English'], 5);
      expect(updated.streak, 0);
    });

    test('getLatestFullAnalysis uses per-language profile fields only', () async {
      await fakeFirestore.collection('users').doc('user1').set({
        'last_performance_summary': {
          'English': 'Strong in English.',
          'French': 'Bon progrès en français.',
        },
        'last_language_level': {
          'English': 'B1',
          'French': 'A2',
        },
      });

      final english =
          await ScoreService.getLatestFullAnalysis('user1', 'English');
      final french = await ScoreService.getLatestFullAnalysis('user1', 'French');
      final spanish =
          await ScoreService.getLatestFullAnalysis('user1', 'Spanish');

      expect(english?['user_performance_summary'], 'Strong in English.');
      expect(english?['language_level'], 'B1');
      expect(french?['user_performance_summary'], 'Bon progrès en français.');
      expect(french?['language_level'], 'A2');
      expect(spanish, isNull);
    });

    test(
      'getLatestFullAnalysis ignores legacy global summary for other languages',
      () async {
        await fakeFirestore.collection('users').doc('user1').set({
          'last_performance_summary': 'Only English analysis (legacy)',
          'last_language_level': 'B1 (legacy)',
        });

        final french =
            await ScoreService.getLatestFullAnalysis('user1', 'French');

        expect(french, isNull);
      },
    );

    test('getLatestFullAnalysis falls back to progress for language', () async {
      await fakeFirestore
          .collection('users')
          .doc('user1')
          .collection('progress')
          .doc('topic1_German')
          .set({
        'language': 'German',
        'user_performance_summary': 'Gute Arbeit!',
        'language_level': 'A2',
        'last_updated': Timestamp.fromDate(DateTime.utc(2026, 1, 10)),
      });
      await fakeFirestore
          .collection('users')
          .doc('user1')
          .collection('progress')
          .doc('topic2_German')
          .set({
        'language': 'German',
        'user_performance_summary': 'Neueste Analyse',
        'language_level': 'B1',
        'last_updated': Timestamp.fromDate(DateTime.utc(2026, 2, 1)),
      });

      final analysis =
          await ScoreService.getLatestFullAnalysis('user1', 'German');

      expect(analysis?['user_performance_summary'], 'Neueste Analyse');
      expect(analysis?['language_level'], 'B1');
    });
  });

  group('Streak logic (grace period)', () {
    late FakeFirebaseFirestore fakeFirestore;

    setUp(() async {
      fakeFirestore = FakeFirebaseFirestore();
      ScoreService.firestoreInstance = fakeFirestore;
      final mockAuth = MockFirebaseAuth(signedIn: true);
      ScoreService.authInstance = mockAuth;
      await fakeFirestore.collection('users').doc('user1').set({
        'language_xp': {},
      });
    });

    String dateId(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    DateTime todayUtc() {
      final now = DateTime.now().toUtc();
      return DateTime.utc(now.year, now.month, now.day);
    }

    Future<void> seedDailyActivity(
      String userId,
      DateTime dateUtc, {
      required int xpEarned,
    }) async {
      final midnightUtc = DateTime.utc(
        dateUtc.year,
        dateUtc.month,
        dateUtc.day,
      );
      await fakeFirestore
          .collection('users')
          .doc(userId)
          .collection('daily_activity')
          .doc(dateId(midnightUtc))
          .set({
            'date': Timestamp.fromDate(midnightUtc),
            'xp_earned': xpEarned,
            'lessons_completed': 1,
            'by_language': {
              'English': {
                'xp_earned': xpEarned,
                'lessons_completed': 1,
              },
            },
          });
    }

    test('refreshStreak resets to 0 when both today and yesterday are inactive',
        () async {
      // Only a stale qualifying day 2 days ago — today & yesterday are empty.
      await seedDailyActivity(
        'user1',
        todayUtc().subtract(const Duration(days: 2)),
        xpEarned: 25,
      );
      // Simulate a stale stored streak.
      await fakeFirestore.collection('users').doc('user1').set({'streak': 10});

      final streak = await ScoreService.refreshStreak(userId: 'user1');

      expect(streak, 0);
      final userDoc = await fakeFirestore
          .collection('users')
          .doc('user1')
          .get();
      expect(userDoc.data()!['streak'], 0);
    });

    test(
      'refreshStreak keeps the streak when only yesterday qualifies (grace '
      'period)',
      () async {
        await seedDailyActivity(
          'user1',
          todayUtc().subtract(const Duration(days: 1)),
          xpEarned: 30,
        );

        final streak = await ScoreService.refreshStreak(userId: 'user1');

        // Yesterday qualified; today is still empty — streak must survive.
        expect(streak, 1);
      },
    );

    test('refreshStreak counts consecutive qualifying days and stops at a gap',
        () async {
      for (int i = 0; i < 3; i++) {
        await seedDailyActivity(
          'user1',
          todayUtc().subtract(Duration(days: i)),
          xpEarned: 25,
        );
      }
      // 4 days ago does NOT qualify (below the 20 XP goal).
      await seedDailyActivity(
        'user1',
        todayUtc().subtract(const Duration(days: 3)),
        xpEarned: 5,
      );

      final streak = await ScoreService.refreshStreak(userId: 'user1');

      expect(streak, 3);
    });

    test('refreshStreak cache is isolated per user', () async {
      // user1 has an active streak (yesterday qualifies under grace period).
      await seedDailyActivity(
        'user1',
        todayUtc().subtract(const Duration(days: 1)),
        xpEarned: 30,
      );
      final streak1 = await ScoreService.refreshStreak(userId: 'user1');
      expect(streak1, 1);

      // user2 has no activity — must recompute to 0, not reuse user1's
      // cached/single-flighted result.
      await fakeFirestore.collection('users').doc('user2').set({
        'language_xp': {},
      });
      final streak2 = await ScoreService.refreshStreak(userId: 'user2');
      expect(streak2, 0);
    });

    test('getActiveActivityDaysForCurrentMonth returns only qualifying days',
        () async {
      final now = DateTime.now();
      await seedDailyActivity(
        'user1',
        DateTime.utc(now.year, now.month, 1),
        xpEarned: 50,
      );
      await seedDailyActivity(
        'user1',
        DateTime.utc(now.year, now.month, 2),
        xpEarned: 5, // below the goal — must be excluded
      );
      await seedDailyActivity(
        'user1',
        DateTime.utc(now.year, now.month, 3),
        xpEarned: 20, // exactly the goal — must be included
      );

      final activeDays =
          await ScoreService.getActiveActivityDaysForCurrentMonth('user1');

      expect(activeDays, {1, 3});
    });
  });
}
