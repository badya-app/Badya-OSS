import 'dart:math';

import 'package:Badya/services/block_service.dart';
import 'package:Badya/services/content_service.dart';
import 'package:Badya/services/language_manager.dart';
import 'package:Badya/models/user_content.dart';
import 'package:Badya/utils/logger.dart';

class TopicSuggestionService {
  final ContentService _contentService = ContentService();
  final LanguageManager _languageManager;

  TopicSuggestionService({LanguageManager? languageManager})
    : _languageManager = languageManager ?? LanguageManager();

  Future<UserContent?> pickTopic(String userId) async {
    final langs = _languageManager.myLanguages;
    if (langs.isEmpty) return null;

    final language = langs[Random().nextInt(langs.length)];

    final ownedIds = await _fetchOwnedContentIds(userId);

    List<UserContent> candidates;
    if (Random().nextDouble() < 0.7) {
      try {
        candidates = await _contentService.getRecommendations(
          userId: userId,
          language: language,
          limit: 5,
        );
      } catch (e) {
        Logger.error('TopicSuggestion: RS failed', e);
        candidates = [];
      }
    } else {
      try {
        final feedResult = await _contentService.getPublicFeedPage(
          language: language,
          limit: 20,
        );
        candidates = feedResult.items;
        candidates.shuffle();
      } catch (e) {
        Logger.error('TopicSuggestion: library feed failed', e);
        candidates = [];
      }
    }

    candidates = candidates.where((c) => !ownedIds.contains(c.id)).toList();

    // Exclude content authored by users the user has blocked.
    try {
      final blockedUids = await BlockService().getBlockedUids(userId);
      candidates = BlockService.filterByBlocked(
        candidates,
        blockedUids,
        (c) => c.userId,
      ).toList();
    } catch (e) {
      Logger.error('TopicSuggestion: block list failed', e);
    }

    if (candidates.isEmpty) return null;

    candidates.shuffle();
    return candidates.first;
  }

  Future<Set<String>> _fetchOwnedContentIds(String userId) async {
    final ids = <String>{};
    try {
      final snapshot = await _contentService
          .getMyContent(userId: userId, limit: 200)
          .first
          .timeout(const Duration(seconds: 10));
      for (final c in snapshot) {
        ids.add(c.id);
        if (c.canonicalContentId != null) {
          ids.add(c.canonicalContentId!);
        }
      }
    } catch (_) {}
    return ids;
  }
}
