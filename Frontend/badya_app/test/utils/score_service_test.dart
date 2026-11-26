import 'package:flutter_test/flutter_test.dart';
import 'package:Badya/utils/score_service.dart';

void main() {
  group('ScoreService Calculation Tests', () {
    // The real calculateLessonScore formula is per-lesson-type:
    //   rolePlay:     communication×0.50 + expression×0.30 + understanding×0.20
    //   storyWeaver:  understanding×0.50 + expression×0.30 + communication×0.20
    //   echoChamber:  expression×0.40   + understanding×0.30 + communication×0.30
    //   wordSmith:    average of wordScores

    test('rolePlay formula: communication×0.50 + expression×0.30 + understanding×0.20', () {
      // communication=80, expression=50, understanding=50
      // score = (80×0.50) + (50×0.30) + (50×0.20) = 40 + 15 + 10 = 65
      final analysisResult = AnalysisResult(
        userPerformanceSummary: 'Good',
        languageLevel: '',
        understandingPercentage: 50,
        expressionPercentage: 50,
        communicationPercentage: 80,
        wordScores: {'hello': 100},
      );

      final score = ScoreService.calculateLessonScore(
        analysisResult,
        LessonType.rolePlay,
      );
      expect(score, 65);
    });

    test('storyWeaver formula: understanding×0.50 + expression×0.30 + communication×0.20', () {
      // understanding=80, expression=60, communication=0
      // score = (80×0.50) + (60×0.30) + (0×0.20) = 40 + 18 + 0 = 58
      final analysisResult = AnalysisResult(
        userPerformanceSummary: 'Good',
        languageLevel: '',
        understandingPercentage: 80,
        expressionPercentage: 60,
        communicationPercentage: 0,
        wordScores: {'a': 100, 'b': 50},
      );

      final score = ScoreService.calculateLessonScore(
        analysisResult,
        LessonType.storyWeaver,
      );
      expect(score, 58);
    });

    test('echoChamber with empty wordScores returns analyzer-weighted result', () {
      // expression=100, understanding=100, communication=0
      // score = (100×0.40) + (100×0.30) + (0×0.30) = 40 + 30 + 0 = 70
      final analysisResult = AnalysisResult(
        userPerformanceSummary: 'Good',
        languageLevel: '',
        understandingPercentage: 100,
        expressionPercentage: 100,
        communicationPercentage: 0,
        wordScores: {},
      );

      final score = ScoreService.calculateLessonScore(
        analysisResult,
        LessonType.echoChamber,
      );
      expect(score, 70);
    });

    test('storyWeaver with empty wordScores uses analyzer formula', () {
      // understanding=80, expression=70, communication=90
      // score = (80×0.50) + (70×0.30) + (90×0.20) = 40 + 21 + 18 = 79
      final analysisResult = AnalysisResult(
        userPerformanceSummary: 'Good',
        languageLevel: '',
        understandingPercentage: 80,
        expressionPercentage: 70,
        communicationPercentage: 90,
        wordScores: {},
        score: 1, // Non-zero to bypass early return
      );

      final score = ScoreService.calculateLessonScore(
        analysisResult,
        LessonType.storyWeaver,
      );
      expect(score, 79);
    });

    test('All zeros returns 0', () {
      // wordScores: {'a': 0}, avg = 0; all analyzer metrics = 0
      // wordSmith uses wordScoreAvg = 0
      final analysisResult = AnalysisResult(
        userPerformanceSummary: 'Bad',
        languageLevel: '',
        understandingPercentage: 0,
        expressionPercentage: 0,
        communicationPercentage: 0,
        wordScores: {'a': 0},
      );

      final score = ScoreService.calculateLessonScore(
        analysisResult,
        LessonType.wordSmith,
      );
      expect(score, 0);
    });

    test('wordSmith formula: average of wordScores', () {
      // wordScores: {'a': 100, 'b': 60} → avg = 80
      final analysisResult = AnalysisResult(
        userPerformanceSummary: 'Good',
        languageLevel: '',
        understandingPercentage: 50,
        expressionPercentage: 50,
        communicationPercentage: 50,
        wordScores: {'a': 100, 'b': 60},
      );

      final score = ScoreService.calculateLessonScore(
        analysisResult,
        LessonType.wordSmith,
      );
      expect(score, 80);
    });

    test('calculateCombinedProgressScore formula', () {
      // partProgress = 0.85, lessonScore = 78
      // (0.85 × 50) + (78 × 0.5) = 42.5 + 39 = 81.5 → rounds to 82
      final combined = ScoreService.calculateCombinedProgressScore(
        partProgress: 0.85,
        lessonScore: 78,
      );
      expect(combined, 82);
    });
  });
}
