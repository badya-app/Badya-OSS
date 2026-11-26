import 'package:Badya/config/app_constants.dart';
import 'package:Badya/services/app_review_prompt_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppReviewPromptService.prefsOverride =
        await SharedPreferences.getInstance();
    AppReviewPromptService.instance.resetForTests();
  });

  tearDown(() {
    AppReviewPromptService.prefsOverride = null;
  });

  test('crossedReviewPromptThreshold detects crossing at 20', () {
    expect(AppConstants.crossedReviewPromptThreshold(20, 21), isTrue);
    expect(AppConstants.crossedReviewPromptThreshold(15, 25), isTrue);
    expect(AppConstants.crossedReviewPromptThreshold(0, 10), isFalse);
    expect(AppConstants.crossedReviewPromptThreshold(25, 30), isFalse);
  });

  test('noteReviewThresholdCrossed sets pending when not completed', () async {
    await AppReviewPromptService.instance.noteReviewThresholdCrossed(true);
    expect(AppReviewPromptService.instance.hasPendingPrompt, isTrue);
    expect(await AppReviewPromptService.instance.hasCompletedPrompt, isFalse);
  });

  test('noteReviewThresholdCrossed ignored after markCompleted', () async {
    await AppReviewPromptService.instance.markCompleted();
    await AppReviewPromptService.instance.noteReviewThresholdCrossed(true);
    expect(AppReviewPromptService.instance.hasPendingPrompt, isFalse);
  });

  test('markCompleted clears pending', () async {
    await AppReviewPromptService.instance.noteReviewThresholdCrossed(true);
    await AppReviewPromptService.instance.markCompleted();
    expect(AppReviewPromptService.instance.hasPendingPrompt, isFalse);
    expect(await AppReviewPromptService.instance.hasCompletedPrompt, isTrue);
  });

  test('noteReviewThresholdCrossed false does not set pending', () async {
    await AppReviewPromptService.instance.noteReviewThresholdCrossed(false);
    expect(AppReviewPromptService.instance.hasPendingPrompt, isFalse);
  });
}
