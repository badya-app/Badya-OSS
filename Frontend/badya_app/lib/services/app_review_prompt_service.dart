import 'package:Badya/config/app_constants.dart';
import 'package:Badya/services/user_preferences_service.dart';
import 'package:Badya/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/review_prompt_dialog.dart';

/// Shows a one-time store-review pre-prompt after total XP crosses 20.
class AppReviewPromptService {
  AppReviewPromptService._();

  static final AppReviewPromptService instance = AppReviewPromptService._();

  static const _completedKey = 'review_prompt_completed';

  bool _sessionPending = false;
  bool _dialogShowing = false;

  @visibleForTesting
  void resetForTests() {
    _sessionPending = false;
    _dialogShowing = false;
  }

  @visibleForTesting
  static SharedPreferences? prefsOverride;

  Future<SharedPreferences> _prefs() async {
    return prefsOverride ?? SharedPreferences.getInstance();
  }

  /// Call when [LevelService.addXP] reports crossing [AppConstants.reviewPromptXpThreshold].
  Future<void> noteReviewThresholdCrossed(bool crossed) async {
    if (!crossed) return;
    final prefs = await _prefs();
    if (prefs.getBool(_completedKey) == true) return;
    _sessionPending = true;
  }

  bool get hasPendingPrompt => _sessionPending;

  Future<bool> get hasCompletedPrompt async {
    final prefs = await _prefs();
    return prefs.getBool(_completedKey) == true;
  }

  Future<void> markCompleted() async {
    _sessionPending = false;
    final prefs = await _prefs();
    await prefs.setBool(_completedKey, true);
  }

  Future<void> maybeShow(
    BuildContext context, {
    bool thresholdCrossedOnThisScreen = false,
  }) async {
    if (_dialogShowing) return;

    final prefs = await _prefs();
    if (prefs.getBool(_completedKey) == true) {
      _sessionPending = false;
      return;
    }

    if (!_sessionPending && !thresholdCrossedOnThisScreen) return;
    if (!context.mounted) return;

    _dialogShowing = true;
    try {
      await ReviewPromptDialog.show(context, service: this);
      _sessionPending = false;
    } finally {
      _dialogShowing = false;
    }
  }

  Future<void> requestStoreReview() async {
    final review = InAppReview.instance;
    try {
      if (await review.isAvailable()) {
        await review.requestReview();
        return;
      }
    } catch (e) {
      Logger.error('In-app review request failed', e);
    }
    await _openPlayStoreListing();
  }

  Future<void> _openPlayStoreListing() async {
    final uri = AppConstants.playStoreListingUri;
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        Logger.warn('Could not open Play Store listing: $uri');
      }
    } catch (e) {
      Logger.error('Error opening Play Store listing', e);
    }
  }

  Future<void> submitLowRatingFeedback(String text) async {
    await UserPreferencesService().submitIssueReport('App feedback', text);
  }
}
