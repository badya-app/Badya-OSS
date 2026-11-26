import 'dart:math';

import 'package:Badya/utils/weighted_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('weightedSample', () {
    test('returns all items when take >= length', () {
      final items = ['a', 'b', 'c'];
      final result = weightedSample(items, (_) => 1.0, 5);
      expect(result.toSet(), {'a', 'b', 'c'});
      expect(result.length, 3);
    });

    test('returns empty list when take <= 0', () {
      expect(weightedSample(['a', 'b'], (_) => 1.0, 0), isEmpty);
      expect(weightedSample(['a', 'b'], (_) => 1.0, -3), isEmpty);
    });

    test('returns empty list from empty input', () {
      expect(weightedSample<String>([], (_) => 5.0, 3), isEmpty);
    });

    test('never returns duplicates', () {
      final items = List.generate(50, (i) => 'w$i');
      final result = weightedSample(
        items,
        (_) => 1.0,
        10,
        random: Random(1),
      );
      expect(result.length, 10);
      expect(result.toSet().length, 10);
    });

    test('is deterministic with an injected seed', () {
      final items = List.generate(20, (i) => 'w$i');
      double weight(String w) => (w.hashCode % 7) + 1.0;

      final a = weightedSample(items, weight, 5, random: Random(42));
      final b = weightedSample(items, weight, 5, random: Random(42));
      expect(a, b);
    });

    test('tolerates zero and negative weights without crashing', () {
      final result = weightedSample(
        ['a', 'b', 'c'],
        (w) => w == 'a' ? 0.0 : -2.0,
        2,
        random: Random(5),
      );
      expect(result.length, 2);
      expect(result.toSet().length, 2);
    });

    test('draws favor high-weight items proportionally (6:1 → ~6/7)',
        () async {
      // For take == 1 the A-Res algorithm picks item i with probability
      // weight_i / Σweights, i.e. 6/7 ≈ 0.857 for the "hard" item.
      const draws = 2000;
      var hardWins = 0;
      final rng = Random(123);

      for (var i = 0; i < draws; i++) {
        final pick = weightedSample(
          ['hard', 'easy'],
          (w) => w == 'hard' ? 6.0 : 1.0,
          1,
          random: rng,
        );
        if (pick.single == 'hard') hardWins++;
      }

      final rate = hardWins / draws;
      // Expected 0.857 with std ≈ 0.008 over 2000 draws — allow a wide
      // safety band so the test is stable but still catches a broken sampler.
      expect(rate, inInclusiveRange(0.78, 0.93));
    });
  });
}
