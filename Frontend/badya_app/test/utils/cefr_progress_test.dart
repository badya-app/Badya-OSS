import 'package:Badya/utils/cefr_progress.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseCefrCode', () {
    test('extracts code from prose', () {
      expect(parseCefrCode('Working at B1 — upper elementary'), 'B1');
      expect(parseCefrCode('a2'), 'A2');
    });

    test('returns null when missing', () {
      expect(parseCefrCode(null), isNull);
      expect(parseCefrCode('beginner'), isNull);
    });
  });

  group('daysToNextCefrLevelLine', () {
    test('returns one line with day count and next level', () {
      final line = daysToNextCefrLevelLine('Currently B1');
      expect(line, '~200 days to B2');
    });

    test('no line at C2', () {
      expect(daysToNextCefrLevelLine('C2 mastery'), isNull);
      expect(isTopCefrLevel('C2 mastery'), isTrue);
    });
  });
}
