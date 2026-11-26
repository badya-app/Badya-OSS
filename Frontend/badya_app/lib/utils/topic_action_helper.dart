import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:Badya/config/content_types.dart';
import 'package:Badya/models/user_content.dart';
import 'package:Badya/services/adk_service.dart';
import 'package:Badya/services/content_service.dart';
import 'package:Badya/services/language_manager.dart';
import 'package:Badya/widgets/add_to_collection_sheet.dart';
import 'package:Badya/utils/logger.dart';
import 'package:Badya/utils/ui_utils.dart';

/// Helper utility to show the "Add to Collection" topic sheet and manage fork
/// creation, language assignment, word list generation, and feedback toast from
/// anywhere in the app (e.g. Library, Home, or Notification tap).
class TopicActionHelper {
  /// How long to wait for the auth session to restore on cold start before
  /// giving up (e.g. app opened from a terminated state via notification tap).
  static const Duration _authRestoreTimeout = Duration(seconds: 10);

  /// Fetches content by [contentId] and opens the Add-to-Collection sheet.
  ///
  /// When [silentOnError] is true (e.g. the sheet was triggered by tapping a
  /// notification whose topic may be stale/expired), lookup failures are only
  /// logged — no error toast is shown to the user.
  static Future<bool> showTopicSheetById({
    required BuildContext context,
    required String contentId,
    String source = 'notification',
    bool silentOnError = false,
  }) async {
    try {
      final contentService = ContentService();
      final content = await contentService.getContent(contentId);
      if (content == null) {
        Logger.warn('TopicActionHelper: Content not found for id $contentId');
        if (!silentOnError && context.mounted) {
          UiUtils.showTopNotification(
            context,
            'Topic could not be found or has been removed',
            type: NotificationType.error,
          );
        }
        return false;
      }

      if (!context.mounted) return false;
      return await showTopicSheet(
        context: context,
        content: content,
        source: source,
      );
    } catch (e) {
      Logger.error('TopicActionHelper: Failed to show topic sheet by id', e);
      if (!silentOnError && context.mounted) {
        UiUtils.showTopNotification(
          context,
          'Failed to open topic',
          type: NotificationType.error,
        );
      }
      return false;
    }
  }

  /// Returns the current user id, briefly waiting for the Firebase session to
  /// restore if needed (it is often still null right after a cold start).
  static Future<String?> _waitForUserId() async {
    FirebaseAuth auth;
    try {
      auth = FirebaseAuth.instance;
    } catch (_) {
      // Firebase not initialized (e.g. widget tests) — no session to restore.
      return null;
    }

    try {
      final user = auth.currentUser;
      if (user != null) return user.uid;

      return await waitForUserIdFrom(
        auth.authStateChanges().map((u) => u?.uid),
      );
    } catch (e) {
      Logger.warn('TopicActionHelper: Failed to resolve user id: $e');
      return null;
    }
  }

  /// Waits for a non-null user id on [userIdStream], giving up after the
  /// auth-restore timeout. Extracted from [_waitForUserId] so the
  /// cold-start auth-race behavior can be unit-tested without Firebase.
  @visibleForTesting
  static Future<String?> waitForUserIdFrom(
    Stream<String?> userIdStream, {
    Duration timeout = _authRestoreTimeout,
  }) async {
    try {
      return await userIdStream.firstWhere((id) => id != null).timeout(timeout);
    } catch (e) {
      Logger.warn(
        'TopicActionHelper: Auth session did not restore in time: $e',
      );
      return null;
    }
  }

  /// Opens the Add-to-Collection bottom sheet for [content], fetches existing fork
  /// info (unless locally cached state is supplied), and executes the collection
  /// update upon user submission.
  ///
  /// Pass [cachedPreAssignedLanguages] / [cachedExistingForkId] when the caller
  /// already knows the fork state from its own local maps (e.g. Library and Home
  /// pages) — this skips the Firestore lookup entirely.
  ///
  /// [onForkUpdated] is invoked with the assigned languages and the fork id
  /// after a successful backend update (the existing id on update, the freshly
  /// created one otherwise — null only if creation failed), so callers can
  /// refresh their local state maps.
  /// Set [logRecommendationClick] to false if the caller already logged the
  /// click itself (e.g. Library logs it on card tap before opening the sheet).
  static Future<bool> showTopicSheet({
    required BuildContext context,
    required UserContent content,
    String source = 'library',
    bool logRecommendationClick = true,
    List<String>? cachedPreAssignedLanguages,
    String? cachedExistingForkId,
    void Function(List<String> assignedLanguages, String? forkId)?
    onForkUpdated,
  }) async {
    final uid = await _waitForUserId();
    if (uid == null) {
      Logger.warn('TopicActionHelper: User is not logged in');
      return false;
    }

    final contentService = ContentService();

    // Log the click for CTR / engagement metrics
    if (logRecommendationClick) {
      contentService.logRecommendationClick(
        userId: uid,
        contentId: content.id,
        source: source,
      );
    }

    // Existing fork info — either supplied by the caller or fetched.
    List<String> preAssignedLanguages = [];
    String? existingForkId;

    if (cachedPreAssignedLanguages != null) {
      preAssignedLanguages = List.from(cachedPreAssignedLanguages);
      existingForkId = cachedExistingForkId;
    } else {
      try {
        final userContents = await contentService
            .getMyContent(userId: uid, limit: 200)
            .first
            .timeout(const Duration(seconds: 5));

        for (final c in userContents) {
          if (c.canonicalContentId == content.id || c.id == content.id) {
            preAssignedLanguages = List.from(c.assignedLanguages);
            existingForkId = c.id;
            break;
          }
        }
      } catch (e) {
        Logger.warn('TopicActionHelper: Could not load existing fork info: $e');
      }
    }

    if (!context.mounted) return false;

    final languageManager = context.read<LanguageManager>();
    final availableLanguages = languageManager.myLanguages;

    final result = await AddToCollectionSheet.show(
      context: context,
      content: content,
      availableLanguages: availableLanguages,
      preAssignedLanguages: preAssignedLanguages,
    );

    if (result == null || !context.mounted) return false;

    try {
      String? createdForkId;
      if (existingForkId != null) {
        // Already has a fork — update its languages with the new ones
        final newLanguages = result.assignedLanguages
            .where((l) => !preAssignedLanguages.contains(l))
            .toList();
        if (newLanguages.isNotEmpty) {
          await contentService.addLanguagesToFork(
            forkId: existingForkId,
            newLanguages: newLanguages,
          );
        }
        // Update difficulty on existing fork if changed. This writes only
        // `metadata.difficulty`, so the fork's segmentation fields
        // (`segment_by`, `segment_value`, `lesson_count`) stay untouched.
        final currentDifficulty = content.metadata?['difficulty'] as String? ?? 'intermediate';
        if (result.difficulty != currentDifficulty) {
          await contentService.updateContent(existingForkId, metadata: {'difficulty': result.difficulty});
        }
      } else {
        // No fork yet — create one
        final forkedId = await contentService.addSuggestionToUser(
          userId: uid,
          suggestionId: content.id,
          assignedLanguages: result.assignedLanguages,
          additionalTags: result.additionalTags.isNotEmpty
              ? result.additionalTags
              : null,
          source: source,
        );
        createdForkId = forkedId;

        // Update difficulty on the newly created fork. Only the difficulty
        // key is sent: `addSuggestionToUser` already copies the full
        // metadata map (chapters, source_url, duration, transcript, …) and
        // the top-level segmentation fields (`segment_by`, `segment_value`,
        // `lesson_count`) are preserved because metadata updates only touch
        // `metadata.*` keys.
        if (forkedId != null) {
          await contentService.updateContent(
            forkedId,
            metadata: {'difficulty': result.difficulty},
          );
        }

        // If the content is AI-generated, generate its word list for the fork.
        // This runs after the sheet closes with a transient loading indicator;
        // if it fails the user can retry from the lesson page's Generate button.
        if (forkedId != null && content.type == ContentType.aiGenerated) {
          _generateWordsWithLoadingIndicator(
            context: context,
            topicId: forkedId,
            subject: content.title,
            description: content.description,
            language: content.language,
            difficulty: result.difficulty,
            userId: uid,
          );
        }
      }

      // Let the caller refresh its local fork-state maps before toasting.
      onForkUpdated?.call(
        result.assignedLanguages,
        existingForkId ?? createdForkId,
      );

      if (context.mounted) {
        UiUtils.showTopNotification(
          context,
          '"${content.title}" added to your collection',
          type: NotificationType.success,
        );
      }

      return true;
    } catch (e) {
      Logger.error('TopicActionHelper: Failed to add topic to collection', e);
      if (context.mounted) {
        UiUtils.showTopNotification(
          context,
          'Failed to add topic to collection',
          type: NotificationType.error,
        );
      }
      return false;
    }
  }

  /// Generates vocab for an AI-generated topic and shows a persistent
  /// loading notification while it runs so the user knows to wait.
  /// On completion the notification is replaced with a success message.
  /// Non-fatal on failure — the lesson page's Generate button remains
  /// available as a fallback.
  static Future<void> _generateWordsWithLoadingIndicator({
    required BuildContext context,
    required String topicId,
    required String subject,
    required String description,
    required String language,
    required String difficulty,
    required String userId,
  }) async {
    // Show a transient loading toast so the user knows vocab is being generated.
    if (!context.mounted) return;
    UiUtils.showTopNotification(
      context,
      'Building your lesson content…',
      type: NotificationType.info,
    );

    try {
      await AdkService().generateAndCacheWords(
        topicId: topicId,
        subject: subject,
        description: description,
        language: language,
        difficulty: difficulty,
        userId: userId,
      );
      if (context.mounted) {
        UiUtils.showTopNotification(
          context,
          'You’re all set to start learning',
          type: NotificationType.success,
        );
      }
    } catch (e) {
      Logger.warn('TopicActionHelper: Background word generation failed: $e');
      if (context.mounted) {
        UiUtils.showTopNotification(
          context,
          'Word generation failed — tap Generate on the lesson page',
          type: NotificationType.info,
        );
      }
    }
  }
}
