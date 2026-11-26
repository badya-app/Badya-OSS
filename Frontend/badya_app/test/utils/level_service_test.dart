import 'package:Badya/utils/level_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LevelService math utilities', () {
    test('xpForLevel follows 50 × (N-1)^2 formula', () {
      expect(LevelService.xpForLevel(1), 0);
      expect(LevelService.xpForLevel(2), 50);
      expect(LevelService.xpForLevel(3), 200);
      expect(LevelService.xpForLevel(10), 50 * 9 * 9); // 4050
    });

    test('levelForXp inverts xpForLevel correctly for sample values', () {
      expect(LevelService.levelForXp(0), 1);
      expect(LevelService.levelForXp(1), 1);
      expect(LevelService.levelForXp(49), 1);
      expect(LevelService.levelForXp(50), 2);
      expect(LevelService.levelForXp(199), 2);
      expect(LevelService.levelForXp(200), 3);
      expect(LevelService.levelForXp(4050), 10);
    });

    test('xpProgress returns consistent current/next/remaining values', () {
      final progress = LevelService.xpProgress(275);

      // For 275 XP the user should be Level 3:
      // Level 3 threshold = 200, Level 4 threshold = 450.
      expect(progress.xpForCurrentLevel, 200);
      expect(progress.xpForNextLevel, 450);
      expect(progress.xpToNextLevel, 450 - 275);

      final maxedProgress = LevelService.xpProgress(0);
      expect(maxedProgress.xpForCurrentLevel, 0);
      expect(maxedProgress.xpForNextLevel, greaterThan(0));
      expect(maxedProgress.xpToNextLevel, maxedProgress.xpForNextLevel);
    });
  });
}





