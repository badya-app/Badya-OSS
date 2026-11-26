import 'package:Badya/models/review_stats.dart';
import 'package:Badya/models/word_review_state.dart';
import 'package:Badya/services/vocab_review_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────────
  // Pure logic tests: WordReviewState SM-2 algorithm
  // ─────────────────────────────────────────────────────────────────────
  group('WordReviewState SM-2 Algorithm', () {
    test(
      'Rating 0 (Forgot) resets repetitions and uses 10-minute interval',
      () {
        final state = WordReviewState(word: 'test').applyRating(0);

        expect(state.repetitions, 0);
        expect(state.lastRating, 0);
        expect(state.totalReviews, 1);
        expect(state.forgottenCount, 1);
        expect(state.easyCount, 0);
        // 10 minutes in days = 10 / (24 * 60) ≈ 0.00694
        expect(state.interval, closeTo(10.0 / (24 * 60), 0.0001));
        expect(state.nextReviewAt, isNotNull);
      },
    );

    test(
      'Rating 1 (Hard) resets repetitions and applies Hard penalty (×0.5), then clamped to 10min',
      () {
        final state = WordReviewState(
          word: 'test',
          interval: 10.0,
        ).applyRating(1);

        expect(state.repetitions, 0);
        expect(state.lastRating, 1);
        expect(state.totalReviews, 1);
        // Hard penalty: interval *= 0.5 → 0.00347 days, but clamped back to 10 min min
        expect(state.interval, closeTo(10.0 / (24 * 60), 0.0001));
      },
    );

    test('Rating 2 (Good) on first review sets interval to 1 day', () {
      final state = WordReviewState(word: 'test').applyRating(2);

      expect(state.repetitions, 1);
      expect(state.lastRating, 2);
      expect(state.totalReviews, 1);
      expect(state.interval, 1.0); // 1 day
    });

    test('Rating 3 (Easy) on first review applies Easy bonus (×1.3)', () {
      final state = WordReviewState(word: 'test').applyRating(3);

      expect(state.repetitions, 1);
      expect(state.lastRating, 3);
      expect(state.totalReviews, 1);
      expect(state.easyCount, 1);
      expect(state.interval, closeTo(1.3, 0.001)); // 1 day × 1.3
    });

    test('Rating 2 on second review sets interval to 3 days', () {
      // Simulate a word that has been reviewed once
      final state = WordReviewState(
        word: 'test',
        repetitions: 1,
        interval: 1.0,
        easinessFactor: 2.5,
        totalReviews: 1,
      ).applyRating(2);

      expect(state.repetitions, 2);
      expect(state.interval, 3.0); // 3 days
    });

    test('Rating 2 on third+ review uses recalculated EF as multiplier', () {
      final state = WordReviewState(
        word: 'test',
        repetitions: 2,
        interval: 3.0,
        easinessFactor: 2.5,
        totalReviews: 2,
      ).applyRating(2);

      expect(state.repetitions, 3);
      // EF is recalculated: 2.5 + (0.1 - 3*(0.08+3*0.02)) = 2.18
      // newInterval = 3.0 * 2.18 = 6.54
      expect(state.interval, closeTo(6.54, 0.01));
      expect(state.easinessFactor, closeTo(2.18, 0.01));
    });

    test('EF increases on Easy (rating 3)', () {
      final state = WordReviewState(
        word: 'test',
        easinessFactor: 2.5,
      ).applyRating(3);

      // EF_new = 2.5 + (0.1 - (5-3) * (0.08 + (5-3) * 0.02))
      // EF_new = 2.5 + (0.1 - 2 * (0.08 + 2 * 0.02))
      // EF_new = 2.5 + (0.1 - 2 * (0.08 + 0.04))
      // EF_new = 2.5 + (0.1 - 2 * 0.12)
      // EF_new = 2.5 + (0.1 - 0.24)
      // EF_new = 2.5 + (-0.14) = 2.36
      expect(state.easinessFactor, closeTo(2.36, 0.001));
    });

    test('EF decreases on Forgot (rating 0)', () {
      final state = WordReviewState(
        word: 'test',
        easinessFactor: 2.5,
      ).applyRating(0);

      // EF_new = 2.5 + (0.1 - 5 * (0.08 + 5 * 0.02))
      // EF_new = 2.5 + (0.1 - 5 * (0.08 + 0.10))
      // EF_new = 2.5 + (0.1 - 5 * 0.18)
      // EF_new = 2.5 + (0.1 - 0.9)
      // EF_new = 2.5 - 0.8 = 1.7
      expect(state.easinessFactor, closeTo(1.7, 0.001));
    });

    test('EF is clamped to minimum 1.3', () {
      final state = WordReviewState(
        word: 'test',
        easinessFactor: 1.3,
      ).applyRating(0); // Forgot decreases EF further

      expect(state.easinessFactor, greaterThanOrEqualTo(1.3));
    });

    test('EF is clamped to maximum 3.0', () {
      final state = WordReviewState(
        word: 'test',
        easinessFactor: 3.0,
      ).applyRating(3); // Easy increases EF

      expect(state.easinessFactor, lessThanOrEqualTo(3.0));
    });

    test('Interval is clamped to minimum 10 minutes', () {
      final state = WordReviewState(
        word: 'test',
      ).applyRating(1); // Hard: reset + penalty

      // 10 minutes / (24*60) ≈ 0.00694 days; * 0.5 = 0.00347. Clamped to 0.00694.
      expect(state.interval, greaterThanOrEqualTo(10.0 / (24 * 60)));
    });

    test('Interval is clamped to maximum 365 days', () {
      final state = WordReviewState(
        word: 'test',
        easinessFactor: 3.0,
        repetitions: 100,
        interval: 300.0,
      ).applyRating(3); // Easy: 300 * 1.3 = 390, clamped to 365

      expect(state.interval, 365.0);
    });

    test('nextReviewAt is set to now + interval (1 day for first Good)', () {
      final before = DateTime.now();
      final state = WordReviewState(word: 'test').applyRating(2);

      expect(state.nextReviewAt, isNotNull);
      // nextReviewAt should be ~1 day in the future
      expect(
        state.nextReviewAt!.isAfter(
          before.subtract(const Duration(seconds: 1)),
        ),
        isTrue,
      );
      expect(
        state.nextReviewAt!.isBefore(before.add(const Duration(hours: 26))),
        isTrue,
      );
    });

    test('lastReviewedAt is set to now', () {
      final before = DateTime.now();
      final state = WordReviewState(word: 'test').applyRating(2);
      final after = DateTime.now();

      expect(state.lastReviewedAt, isNotNull);
      expect(
        state.lastReviewedAt!.isAfter(
          before.subtract(const Duration(seconds: 1)),
        ),
        isTrue,
      );
      expect(
        state.lastReviewedAt!.isBefore(after.add(const Duration(seconds: 2))),
        isTrue,
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // WordReviewState helper properties
  // ─────────────────────────────────────────────────────────────────────
  group('WordReviewState helper properties', () {
    test('isNew returns true when nextReviewAt is null', () {
      final state = WordReviewState(word: 'test');
      expect(state.isNew, isTrue);
    });

    test('isNew returns false when nextReviewAt is not null', () {
      final state = WordReviewState(
        word: 'test',
        nextReviewAt: DateTime.now().add(const Duration(days: 1)),
      );
      expect(state.isNew, isFalse);
    });

    test('isDue returns true when nextReviewAt is null (new word)', () {
      final state = WordReviewState(word: 'test');
      expect(state.isDue, isTrue);
    });

    test('isDue returns true when nextReviewAt is in the past', () {
      final state = WordReviewState(
        word: 'test',
        nextReviewAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(state.isDue, isTrue);
    });

    test('isDue returns false when nextReviewAt is in the future', () {
      final state = WordReviewState(
        word: 'test',
        nextReviewAt: DateTime.now().add(const Duration(hours: 25)),
      );
      expect(state.isDue, isFalse);
    });

    test('isMastered returns true when interval >= 21', () {
      final state = WordReviewState(word: 'test', interval: 21.0);
      expect(state.isMastered, isTrue);
    });

    test('isMastered returns true when interval > 21', () {
      final state = WordReviewState(word: 'test', interval: 30.0);
      expect(state.isMastered, isTrue);
    });

    test('isMastered returns false when interval < 21', () {
      final state = WordReviewState(word: 'test', interval: 20.0);
      expect(state.isMastered, isFalse);
    });

    test('isSoon returns true when due within 24 hours (but not overdue)', () {
      final state = WordReviewState(
        word: 'test',
        nextReviewAt: DateTime.now().add(const Duration(hours: 12)),
      );
      expect(state.isSoon, isTrue);
    });

    test('isSoon returns false when nextReviewAt is null', () {
      final state = WordReviewState(word: 'test');
      expect(state.isSoon, isFalse);
    });

    test('isSoon returns false when overdue (nextReviewAt in the past)', () {
      final state = WordReviewState(
        word: 'test',
        nextReviewAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      expect(state.isSoon, isFalse);
    });

    test('isSoon returns false when far in the future', () {
      final state = WordReviewState(
        word: 'test',
        nextReviewAt: DateTime.now().add(const Duration(hours: 48)),
      );
      expect(state.isSoon, isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // WordReviewState serialization
  // ─────────────────────────────────────────────────────────────────────
  group('WordReviewState serialization', () {
    test('toFirestore and fromFirestore round-trip', () {
      final now = DateTime.now();
      final original = WordReviewState(
        word: 'hello',
        score: 75,
        easinessFactor: 2.5,
        interval: 3.0,
        repetitions: 2,
        nextReviewAt: now,
        lastReviewedAt: now,
        lastRating: 2,
        totalReviews: 5,
        forgottenCount: 1,
        easyCount: 2,
        addedAt: now,
        definition: 'a greeting',
        exampleSentence: 'Hello, world!',
      );

      final firestoreMap = original.toFirestore();
      final restored = WordReviewState.fromFirestore('hello', firestoreMap);

      expect(restored.word, original.word);
      expect(restored.score, original.score);
      expect(restored.easinessFactor, original.easinessFactor);
      expect(restored.interval, original.interval);
      expect(restored.repetitions, original.repetitions);
      expect(restored.lastRating, original.lastRating);
      expect(restored.totalReviews, original.totalReviews);
      expect(restored.forgottenCount, original.forgottenCount);
      expect(restored.easyCount, original.easyCount);
      expect(restored.definition, original.definition);
      expect(restored.exampleSentence, original.exampleSentence);
    });

    test('toJson and fromJson round-trip', () {
      final now = DateTime.now();
      final original = WordReviewState(
        word: 'hello',
        score: 75,
        easinessFactor: 2.5,
        interval: 3.0,
        repetitions: 2,
        nextReviewAt: now,
        lastReviewedAt: now,
        lastRating: 2,
        totalReviews: 5,
        forgottenCount: 1,
        easyCount: 2,
        addedAt: now,
        definition: 'a greeting',
        exampleSentence: 'Hello, world!',
      );

      final json = original.toJson();
      final restored = WordReviewState.fromJson(json);

      expect(restored.word, original.word);
      expect(restored.score, original.score);
      expect(restored.easinessFactor, original.easinessFactor);
      expect(restored.interval, original.interval);
      expect(restored.repetitions, original.repetitions);
      expect(restored.lastRating, original.lastRating);
      expect(restored.totalReviews, original.totalReviews);
      expect(restored.forgottenCount, original.forgottenCount);
      expect(restored.easyCount, original.easyCount);
    });

    test('listToJson and listFromJson round-trip', () {
      final words = [
        WordReviewState(word: 'hello', score: 80),
        WordReviewState(word: 'world', score: 50),
      ];

      final jsonStr = WordReviewState.listToJson(words);
      final restored = WordReviewState.listFromJson(jsonStr);

      expect(restored.length, 2);
      expect(restored[0].word, 'hello');
      expect(restored[0].score, 80);
      expect(restored[1].word, 'world');
      expect(restored[1].score, 50);
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // WordReviewState copyWith
  // ─────────────────────────────────────────────────────────────────────
  group('WordReviewState copyWith', () {
    test('copyWith overrides specified fields', () {
      final original = WordReviewState(word: 'test', score: 50, interval: 5.0);
      final copied = original.copyWith(score: 100, interval: 10.0);

      expect(copied.word, 'test');
      expect(copied.score, 100);
      expect(copied.interval, 10.0);
    });

    test('copyWith preserves unspecified fields', () {
      final original = WordReviewState(
        word: 'test',
        easinessFactor: 2.5,
        totalReviews: 5,
      );
      final copied = original.copyWith(score: 80);

      expect(copied.word, 'test');
      expect(copied.easinessFactor, 2.5);
      expect(copied.totalReviews, 5);
      expect(copied.score, 80);
    });

    test('copyWith clear flags set nullable fields to null', () {
      final original = WordReviewState(
        word: 'test',
        nextReviewAt: DateTime.now(),
        lastReviewedAt: DateTime.now(),
        lastRating: 2,
      );
      final copied = original.copyWith(
        clearNextReviewAt: true,
        clearLastReviewedAt: true,
        clearLastRating: true,
      );

      expect(copied.nextReviewAt, isNull);
      expect(copied.lastReviewedAt, isNull);
      expect(copied.lastRating, isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // ReviewStats
  // ─────────────────────────────────────────────────────────────────────
  group('ReviewStats', () {
    test('fromWordList with empty list returns zeros', () {
      final stats = ReviewStats.fromWordList([]);
      expect(stats.totalWords, 0);
      expect(stats.dueCount, 0);
      expect(stats.masteredCount, 0);
      expect(stats.newCount, 0);
      expect(stats.recallRate, 1.0);
    });

    test('fromWordList counts new words correctly', () {
      final words = [
        WordReviewState(word: 'new1'), // isNew=true, isDue=true
        WordReviewState(word: 'new2'), // isNew=true, isDue=true
        WordReviewState(word: 'new3'), // isNew=true, isDue=true
      ];

      final stats = ReviewStats.fromWordList(words);
      expect(stats.totalWords, 3);
      expect(stats.newCount, 3);
      expect(stats.dueCount, 3);
      expect(stats.masteredCount, 0);
    });

    test('fromWordList counts mastered words correctly', () {
      final words = [
        WordReviewState(
          word: 'mastered1',
          interval: 21.0,
          nextReviewAt: DateTime.now().add(const Duration(days: 21)),
        ),
        WordReviewState(
          word: 'mastered2',
          interval: 30.0,
          nextReviewAt: DateTime.now().add(const Duration(days: 30)),
        ),
        WordReviewState(word: 'new_word'), // New word
      ];

      final stats = ReviewStats.fromWordList(words);
      expect(stats.totalWords, 3);
      expect(stats.masteredCount, 2);
      expect(stats.newCount, 1);
      expect(stats.dueCount, 1); // Only the new word is due
    });

    test('fromWordList counts overdue words correctly', () {
      final words = [
        WordReviewState(
          word: 'overdue',
          nextReviewAt: DateTime.now().subtract(const Duration(days: 1)),
          interval: 1.0,
        ),
        WordReviewState(word: 'new_word'), // New word
      ];

      final stats = ReviewStats.fromWordList(words);
      expect(stats.totalWords, 2);
      expect(stats.dueCount, 2); // Both are due
      expect(stats.newCount, 1);
      expect(stats.overdueCount, 1);
    });

    test('fromWordList counts soon words correctly', () {
      final words = [
        WordReviewState(
          word: 'soon_word',
          nextReviewAt: DateTime.now().add(const Duration(hours: 6)),
          interval: 1.0,
        ),
        WordReviewState(word: 'new_word'), // New word (due)
      ];

      final stats = ReviewStats.fromWordList(words);
      expect(stats.totalWords, 2);
      expect(stats.soonCount, 1);
      expect(
        stats.dueCount,
        1,
      ); // Only the new word is due (soon is not overdue)
      expect(stats.newCount, 1);
    });

    test('fromWordList computes recall rate correctly', () {
      final words = [
        WordReviewState(word: 'word1', totalReviews: 10, forgottenCount: 2),
        WordReviewState(word: 'word2', totalReviews: 5, forgottenCount: 0),
      ];

      final stats = ReviewStats.fromWordList(words);
      // totalReviews = 15, totalForgotten = 2
      // recallRate = (15 - 2) / 15 = 13/15 ≈ 0.867
      expect(stats.recallRate, closeTo(13 / 15, 0.001));
    });

    test('fromWordList handles mixed states correctly', () {
      final words = [
        WordReviewState(word: 'new1'),
        WordReviewState(word: 'new2'),
        WordReviewState(
          word: 'mastered',
          interval: 25.0,
          nextReviewAt: DateTime.now().add(const Duration(days: 25)),
          totalReviews: 20,
          forgottenCount: 1,
        ),
        WordReviewState(
          word: 'overdue',
          nextReviewAt: DateTime.now().subtract(const Duration(hours: 5)),
          interval: 1.0,
          totalReviews: 5,
          forgottenCount: 3,
        ),
        WordReviewState(
          word: 'soon',
          nextReviewAt: DateTime.now().add(const Duration(hours: 8)),
          interval: 0.5,
        ),
      ];

      final stats = ReviewStats.fromWordList(words);
      expect(stats.totalWords, 5);
      expect(stats.newCount, 2);
      expect(stats.masteredCount, 1);
      expect(stats.overdueCount, 1);
      expect(stats.soonCount, 1);
      expect(stats.dueCount, 3); // 2 new + 1 overdue
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // VocabReviewService — Scope & Doc Helpers
  // ─────────────────────────────────────────────────────────────────────
  group('VocabReviewService scope helpers', () {
    test('topicScopeId concatenates topicId and language', () {
      expect(
        VocabReviewService.topicScopeId('Travel', 'English'),
        'Travel_English',
      );
      expect(
        VocabReviewService.topicScopeId('myTopic', 'French'),
        'myTopic_French',
      );
    });

    test(
      'getDueStrangeWords returns empty for non-existent document',
      () async {
        SharedPreferences.setMockInitialValues({});
        final fakeFirestore = FakeFirebaseFirestore();
        final mockAuth = MockFirebaseAuth(signedIn: true);

        final service = VocabReviewService(
          firestore: fakeFirestore,
          auth: mockAuth,
        );

        final words = await service.getDueStrangeWords('English');
        expect(words, isEmpty);
      },
    );

    test('getDueWords returns empty for empty words list', () async {
      SharedPreferences.setMockInitialValues({});
      final fakeFirestore = FakeFirebaseFirestore();
      final mockAuth = MockFirebaseAuth(signedIn: true);

      // Set up empty strange_words document
      await fakeFirestore
          .collection('users')
          .doc(mockAuth.currentUser!.uid)
          .collection('strange_words')
          .doc('English')
          .set({'words': <String, dynamic>{}});

      final service = VocabReviewService(
        firestore: fakeFirestore,
        auth: mockAuth,
      );

      final words = await service.getDueStrangeWords('English');
      expect(words, isEmpty);
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // VocabReviewService — Word Selection (getDueWords)
  // ─────────────────────────────────────────────────────────────────────
  group('VocabReviewService getDueWords', () {
    late FakeFirebaseFirestore fakeFirestore;
    late MockFirebaseAuth mockAuth;
    late VocabReviewService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      fakeFirestore = FakeFirebaseFirestore();
      mockAuth = MockFirebaseAuth(signedIn: true);
      service = VocabReviewService(firestore: fakeFirestore, auth: mockAuth);

      // Seed with a mix of words
      await fakeFirestore
          .collection('users')
          .doc(mockAuth.currentUser!.uid)
          .collection('strange_words')
          .doc('English')
          .set({
            'words': {
              'new_word1': {
                'score': 0,
                'ef': 2.5,
                'interval': 0.0,
                'repetitions': 0,
                'total_reviews': 0,
                'forgotten_count': 0,
                'easy_count': 0,
              },
              'new_word2': {
                'score': 0,
                'ef': 2.5,
                'interval': 0.0,
                'repetitions': 0,
                'total_reviews': 0,
                'forgotten_count': 0,
                'easy_count': 0,
              },
              'due_word': {
                'score': 60,
                'ef': 2.5,
                'interval': 1.0,
                'repetitions': 1,
                'next_review_at': Timestamp.fromDate(
                  DateTime.now().subtract(const Duration(hours: 2)),
                ),
                'last_rating': 2,
                'total_reviews': 1,
                'forgotten_count': 0,
                'easy_count': 0,
              },
              'soon_word': {
                'score': 75,
                'ef': 2.5,
                'interval': 3.0,
                'repetitions': 2,
                'next_review_at': Timestamp.fromDate(
                  DateTime.now().add(const Duration(hours: 6)),
                ),
                'last_rating': 2,
                'total_reviews': 2,
                'forgotten_count': 0,
                'easy_count': 0,
              },
              'future_word': {
                'score': 90,
                'ef': 2.5,
                'interval': 10.0,
                'repetitions': 3,
                'next_review_at': Timestamp.fromDate(
                  DateTime.now().add(const Duration(days: 5)),
                ),
                'last_rating': 3,
                'total_reviews': 3,
                'forgotten_count': 0,
                'easy_count': 1,
              },
              'forgotten_word': {
                'score': 15,
                'ef': 1.5,
                'interval': 0.01,
                'repetitions': 0,
                'next_review_at': Timestamp.fromDate(
                  DateTime.now().subtract(const Duration(hours: 1)),
                ),
                'last_rating': 0,
                'total_reviews': 3,
                'forgotten_count': 2,
                'easy_count': 0,
              },
              'mastered_word': {
                'score': 95,
                'ef': 2.8,
                'interval': 30.0,
                'repetitions': 10,
                'next_review_at': Timestamp.fromDate(
                  DateTime.now().add(const Duration(days: 30)),
                ),
                'last_rating': 3,
                'total_reviews': 10,
                'forgotten_count': 0,
                'easy_count': 5,
              },
            },
            'last_updated': Timestamp.now(),
          });
    });

    test(
      'getDueWords returns new and due words, excludes future and mastered',
      () async {
        final words = await service.getDueWords(
          scope: VocabReviewService.scopeStrangeWords,
          scopeId: 'English',
          maxCards: 10,
        );

        // Should include: forgotten_word, due_word, new_word1, new_word2, soon_word
        // Should exclude: future_word, mastered_word
        expect(words.length, greaterThanOrEqualTo(4));
        expect(words.length, lessThanOrEqualTo(6));

        final wordNames = words.map((w) => w.word).toSet();
        expect(wordNames, contains('forgotten_word'));
        expect(wordNames, contains('due_word'));
        expect(wordNames, contains('new_word1'));
        expect(wordNames, contains('new_word2'));
        expect(wordNames, contains('soon_word'));
        expect(wordNames, isNot(contains('future_word')));
        expect(wordNames, isNot(contains('mastered_word')));
      },
    );

    test(
      'getDueWords returns forgotten words first (highest priority)',
      () async {
        final words = await service.getDueWords(
          scope: VocabReviewService.scopeStrangeWords,
          scopeId: 'English',
          maxCards: 10,
        );

        // The first word(s) should be the forgotten word(s)
        final firstWord = words.first;
        expect(firstWord.word, 'forgotten_word');
        expect(firstWord.lastRating, 0);
      },
    );

    test('getDueWords respects maxCards limit', () async {
      final words = await service.getDueWords(
        scope: VocabReviewService.scopeStrangeWords,
        scopeId: 'English',
        maxCards: 2,
      );

      expect(words.length, lessThanOrEqualTo(2));
    });

    test('getDueStrangeWords convenience method works', () async {
      final words = await service.getDueStrangeWords('English', maxCards: 10);
      expect(words, isNotEmpty);
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // VocabReviewService — Legacy List Format
  // ─────────────────────────────────────────────────────────────────────
  group('VocabReviewService legacy List format', () {
    late FakeFirebaseFirestore fakeFirestore;
    late MockFirebaseAuth mockAuth;
    late VocabReviewService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      fakeFirestore = FakeFirebaseFirestore();
      mockAuth = MockFirebaseAuth(signedIn: true);
      service = VocabReviewService(firestore: fakeFirestore, auth: mockAuth);

      // Seed with legacy List format
      await fakeFirestore
          .collection('users')
          .doc(mockAuth.currentUser!.uid)
          .collection('strange_words')
          .doc('English')
          .set({
            'words': ['hello', 'world', 'bonjour'],
          });
    });

    test('getAllWords handles legacy List<String> format', () async {
      final words = await service.getAllWords(
        scope: VocabReviewService.scopeStrangeWords,
        scopeId: 'English',
      );

      expect(words.length, 3);
      expect(words.map((w) => w.word).toSet(), {'hello', 'world', 'bonjour'});
      // All should have default SRS state (new words)
      for (final w in words) {
        expect(w.isNew, isTrue);
        expect(w.easinessFactor, 2.5);
        expect(w.interval, 0.0);
      }
    });

    test(
      'getDueWords returns all words from legacy List format as due',
      () async {
        final words = await service.getDueWords(
          scope: VocabReviewService.scopeStrangeWords,
          scopeId: 'English',
        );

        expect(words.length, 3);
        for (final w in words) {
          expect(w.isNew || w.isDue, isTrue);
        }
      },
    );
  });

  // ─────────────────────────────────────────────────────────────────────
  // VocabReviewService — Write Operations
  // ─────────────────────────────────────────────────────────────────────
  group('VocabReviewService write operations', () {
    late FakeFirebaseFirestore fakeFirestore;
    late MockFirebaseAuth mockAuth;
    late VocabReviewService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      fakeFirestore = FakeFirebaseFirestore();
      mockAuth = MockFirebaseAuth(signedIn: true);
      service = VocabReviewService(firestore: fakeFirestore, auth: mockAuth);
    });

    test('addWord creates word with default SRS state', () async {
      await service.addWord(word: 'hello', language: 'English');

      final doc = await fakeFirestore
          .collection('users')
          .doc(mockAuth.currentUser!.uid)
          .collection('strange_words')
          .doc('English')
          .get();

      expect(doc.exists, isTrue);
      final words = doc.data()!['words'] as Map<String, dynamic>;
      expect(words, containsPair('hello', isNotNull));

      final wordData = words['hello'] as Map<String, dynamic>;
      expect(wordData['ef'], 2.5);
      expect(wordData['score'], 0);
      expect(wordData['interval'], 0.0);
      expect(wordData['repetitions'], 0);
    });

    test('addWord is idempotent (no-op for existing word)', () async {
      await service.addWord(word: 'hello', language: 'English');
      await service.addWord(word: 'hello', language: 'English');
      await service.addWord(word: 'world', language: 'English');

      final doc = await fakeFirestore
          .collection('users')
          .doc(mockAuth.currentUser!.uid)
          .collection('strange_words')
          .doc('English')
          .get();

      final words = doc.data()!['words'] as Map<String, dynamic>;
      expect(words.length, 2);
    });

    test('deleteWord removes a word and its SRS state', () async {
      // First add
      await service.addWord(word: 'hello', language: 'English');
      await service.addWord(word: 'world', language: 'English');

      // Then delete
      await service.deleteWord('hello', 'English');

      final doc = await fakeFirestore
          .collection('users')
          .doc(mockAuth.currentUser!.uid)
          .collection('strange_words')
          .doc('English')
          .get();

      final words = doc.data()!['words'] as Map<String, dynamic>;
      expect(words, isNot(contains('hello')));
      expect(words, contains('world'));
    });

    test('editWord renames a word preserving SRS state', () async {
      await service.addWord(word: 'hello', language: 'English');
      await service.addWord(word: 'world', language: 'English');

      // Rename 'hello' → 'hola'
      await service.editWord(
        oldWord: 'hello',
        newWord: 'hola',
        language: 'English',
      );

      final doc = await fakeFirestore
          .collection('users')
          .doc(mockAuth.currentUser!.uid)
          .collection('strange_words')
          .doc('English')
          .get();

      final words = doc.data()!['words'] as Map<String, dynamic>;
      expect(words, isNot(contains('hello')));
      expect(words, contains('hola'));
      expect(words, contains('world'));

      // SRS state should be preserved (default score=0, ef=2.5)
      final holaData = words['hola'] as Map<String, dynamic>;
      expect(holaData['score'], 0);
      expect(holaData['ef'], 2.5);
    });

    test('editWord is no-op for same word', () async {
      await service.addWord(word: 'hello', language: 'English');
      await service.editWord(
        oldWord: 'hello',
        newWord: 'hello',
        language: 'English',
      );

      final doc = await fakeFirestore
          .collection('users')
          .doc(mockAuth.currentUser!.uid)
          .collection('strange_words')
          .doc('English')
          .get();

      final words = doc.data()!['words'] as Map<String, dynamic>;
      expect(words, contains('hello'));
      expect(words.length, 1);
    });

    test('submitSessionRatings applies SM-2 ratings and persists', () async {
      // Add two words with default state
      await service.addWord(word: 'cat', language: 'English');
      await service.addWord(word: 'dog', language: 'English');

      // Submit ratings: cat = Easy (3), dog = Forgot (0)
      await service.submitSessionRatings(
        language: 'English',
        wordRatings: {'cat': 3, 'dog': 0},
      );

      final doc = await fakeFirestore
          .collection('users')
          .doc(mockAuth.currentUser!.uid)
          .collection('strange_words')
          .doc('English')
          .get();

      final words = doc.data()!['words'] as Map<String, dynamic>;
      final catData = words['cat'] as Map<String, dynamic>;
      final dogData = words['dog'] as Map<String, dynamic>;

      // Cat (Easy, rating 3): repetitions = 1, interval ≈ 1.3, easy_count = 1
      expect(catData['repetitions'], 1);
      expect((catData['interval'] as num).toDouble(), closeTo(1.3, 0.01));
      expect(catData['easy_count'], 1);
      expect(catData['total_reviews'], 1);

      // Dog (Forgot, rating 0): repetitions = 0, forgotten_count = 1
      expect(dogData['repetitions'], 0);
      expect(dogData['forgotten_count'], 1);
      expect(dogData['total_reviews'], 1);
    });

    test('markAsLearned sets interval to 365 days', () async {
      await service.addWord(word: 'hello', language: 'English');
      await service.markAsLearned('hello', 'English');

      final doc = await fakeFirestore
          .collection('users')
          .doc(mockAuth.currentUser!.uid)
          .collection('strange_words')
          .doc('English')
          .get();

      final words = doc.data()!['words'] as Map<String, dynamic>;
      final wordData = words['hello'] as Map<String, dynamic>;
      expect((wordData['interval'] as num).toDouble(), 365.0);
    });

    test('resetProgress resets SRS to defaults', () async {
      await service.addWord(word: 'hello', language: 'English');
      await service.markAsLearned('hello', 'English');
      await service.resetProgress('hello', 'English');

      final doc = await fakeFirestore
          .collection('users')
          .doc(mockAuth.currentUser!.uid)
          .collection('strange_words')
          .doc('English')
          .get();

      final words = doc.data()!['words'] as Map<String, dynamic>;
      final wordData = words['hello'] as Map<String, dynamic>;

      expect(wordData['repetitions'], 0);
      expect((wordData['interval'] as num).toDouble(), 0.0);
      expect(wordData['ef'], 2.5);
      expect(wordData['total_reviews'], 0);
    });

    test('submitTopicSessionRatings writes to topic scope', () async {
      // Set up a topic document
      await fakeFirestore
          .collection('users')
          .doc(mockAuth.currentUser!.uid)
          .collection('topics')
          .doc('Travel_English')
          .set({
            'words': {
              'passport': {
                'score': 0,
                'ef': 2.5,
                'interval': 0.0,
                'repetitions': 0,
                'total_reviews': 0,
                'forgotten_count': 0,
                'easy_count': 0,
              },
            },
          });

      await service.submitTopicSessionRatings(
        topicScopeId: 'Travel_English',
        wordRatings: {'passport': 2},
      );

      final doc = await fakeFirestore
          .collection('users')
          .doc(mockAuth.currentUser!.uid)
          .collection('topics')
          .doc('Travel_English')
          .get();

      expect(doc.exists, isTrue);
      final words = doc.data()!['words'] as Map<String, dynamic>;
      final passportData = words['passport'] as Map<String, dynamic>;
      expect(passportData['repetitions'], 1);
    });

    test('addWordsToTopic adds new words with default SRS state', () async {
      await service.addWordsToTopic(
        topicId: 'Travel',
        language: 'English',
        words: ['passport', 'visa'],
      );

      final doc = await fakeFirestore
          .collection('users')
          .doc(mockAuth.currentUser!.uid)
          .collection('topics')
          .doc('Travel_English')
          .get();

      expect(doc.exists, isTrue);
      final words = doc.data()!['words'] as Map<String, dynamic>;
      expect(words, contains('passport'));
      expect(words, contains('visa'));

      final passportData = words['passport'] as Map<String, dynamic>;
      expect(passportData['ef'], 2.5);
      expect(passportData['score'], 0);
      expect(passportData['interval'], 0.0);
      expect(passportData['repetitions'], 0);
    });

    test('addWordsToTopic preserves existing SRS state', () async {
      // Seed with an existing word that has SRS data
      await fakeFirestore
          .collection('users')
          .doc(mockAuth.currentUser!.uid)
          .collection('topics')
          .doc('Travel_English')
          .set({
            'words': {
              'passport': {
                'score': 75,
                'ef': 2.8,
                'interval': 3.0,
                'repetitions': 2,
                'total_reviews': 3,
                'forgotten_count': 0,
                'easy_count': 1,
              },
            },
          });

      // Add new word while passport already exists
      await service.addWordsToTopic(
        topicId: 'Travel',
        language: 'English',
        words: ['passport', 'visa'],
      );

      final doc = await fakeFirestore
          .collection('users')
          .doc(mockAuth.currentUser!.uid)
          .collection('topics')
          .doc('Travel_English')
          .get();

      final words = doc.data()!['words'] as Map<String, dynamic>;

      // Existing word preserves its SRS state
      final passportData = words['passport'] as Map<String, dynamic>;
      expect(passportData['score'], 75);
      expect(passportData['ef'], 2.8);
      expect(passportData['interval'], 3.0);
      expect(passportData['repetitions'], 2);

      // New word gets default SRS state
      final visaData = words['visa'] as Map<String, dynamic>;
      expect(visaData['ef'], 2.5);
      expect(visaData['score'], 0);
    });

    test('addWordsToTopic is idempotent for duplicates', () async {
      await service.addWordsToTopic(
        topicId: 'Travel',
        language: 'English',
        words: ['hello', 'hello', 'world'],
      );

      final doc = await fakeFirestore
          .collection('users')
          .doc(mockAuth.currentUser!.uid)
          .collection('topics')
          .doc('Travel_English')
          .get();

      final words = doc.data()!['words'] as Map<String, dynamic>;
      expect(words.length, 2);
    });

    test('syncTopicWords replaces the full word list preserving SRS', () async {
      // Seed with existing words
      await fakeFirestore
          .collection('users')
          .doc(mockAuth.currentUser!.uid)
          .collection('topics')
          .doc('Travel_English')
          .set({
            'words': {
              'passport': {
                'score': 75,
                'ef': 2.8,
                'interval': 3.0,
                'repetitions': 2,
                'total_reviews': 3,
                'forgotten_count': 0,
                'easy_count': 1,
              },
              'visa': {
                'score': 50,
                'ef': 2.5,
                'interval': 0.0,
                'repetitions': 0,
                'total_reviews': 0,
                'forgotten_count': 0,
                'easy_count': 0,
              },
              'luggage': {
                'score': 90,
                'ef': 2.9,
                'interval': 7.0,
                'repetitions': 4,
                'total_reviews': 5,
                'forgotten_count': 0,
                'easy_count': 2,
              },
            },
          });

      // Sync: keep 'passport', add 'ticket', remove 'visa' and 'luggage'
      await service.syncTopicWords(
        topicId: 'Travel',
        language: 'English',
        words: ['passport', 'ticket'],
      );

      final doc = await fakeFirestore
          .collection('users')
          .doc(mockAuth.currentUser!.uid)
          .collection('topics')
          .doc('Travel_English')
          .get();

      final words = doc.data()!['words'] as Map<String, dynamic>;

      // Words not in the new list are removed
      expect(words, isNot(contains('visa')));
      expect(words, isNot(contains('luggage')));

      // Existing word preserves SRS state
      expect(words, contains('passport'));
      final passportData = words['passport'] as Map<String, dynamic>;
      expect(passportData['score'], 75);
      expect(passportData['ef'], 2.8);

      // New word gets default SRS state
      expect(words, contains('ticket'));
      final ticketData = words['ticket'] as Map<String, dynamic>;
      expect(ticketData['ef'], 2.5);
      expect(ticketData['score'], 0);
    });

    test('syncTopicWords handles empty word list by clearing all', () async {
      await fakeFirestore
          .collection('users')
          .doc(mockAuth.currentUser!.uid)
          .collection('topics')
          .doc('Travel_English')
          .set({
            'words': {
              'passport': {
                'score': 75,
                'ef': 2.8,
                'interval': 3.0,
                'repetitions': 2,
                'total_reviews': 3,
                'forgotten_count': 0,
                'easy_count': 1,
              },
            },
          });

      await service.syncTopicWords(
        topicId: 'Travel',
        language: 'English',
        words: [],
      );

      final doc = await fakeFirestore
          .collection('users')
          .doc(mockAuth.currentUser!.uid)
          .collection('topics')
          .doc('Travel_English')
          .get();

      final words = doc.data()!['words'] as Map<String, dynamic>;
      expect(words, isEmpty);
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // VocabReviewService — Migration
  // ─────────────────────────────────────────────────────────────────────
  group('VocabReviewService migration', () {
    late FakeFirebaseFirestore fakeFirestore;
    late MockFirebaseAuth mockAuth;
    late VocabReviewService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      fakeFirestore = FakeFirebaseFirestore();
      mockAuth = MockFirebaseAuth(signedIn: true);
      service = VocabReviewService(firestore: fakeFirestore, auth: mockAuth);
    });

    test('needsMigration returns true for List format', () async {
      await fakeFirestore
          .collection('users')
          .doc(mockAuth.currentUser!.uid)
          .collection('strange_words')
          .doc('English')
          .set({
            'words': ['hello', 'world'],
          });

      final needs = await service.needsMigration('English');
      expect(needs, isTrue);
    });

    test('needsMigration returns false for Map format', () async {
      await fakeFirestore
          .collection('users')
          .doc(mockAuth.currentUser!.uid)
          .collection('strange_words')
          .doc('English')
          .set({
            'words': {
              'hello': {'score': 75},
            },
          });

      final needs = await service.needsMigration('English');
      expect(needs, isFalse);
    });

    test('migrateListToMap converts List to Map format', () async {
      await fakeFirestore
          .collection('users')
          .doc(mockAuth.currentUser!.uid)
          .collection('strange_words')
          .doc('English')
          .set({
            'words': ['hello', 'world'],
          });

      await service.migrateListToMap(language: 'English');

      final doc = await fakeFirestore
          .collection('users')
          .doc(mockAuth.currentUser!.uid)
          .collection('strange_words')
          .doc('English')
          .get();

      final words = doc.data()!['words'];
      expect(words, isA<Map>());

      final wordMap = words as Map<String, dynamic>;
      expect(wordMap, contains('hello'));
      expect(wordMap, contains('world'));

      final helloData = wordMap['hello'] as Map<String, dynamic>;
      expect(helloData['ef'], 2.5);
      expect(helloData['score'], 0);
    });

    test('needsMigration returns false for non-existent document', () async {
      final needs = await service.needsMigration('NonExistent');
      expect(needs, isFalse);
    });
  });
}
