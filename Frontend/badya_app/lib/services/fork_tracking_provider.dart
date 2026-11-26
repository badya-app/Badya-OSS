import 'dart:async';
import 'package:Badya/config/local_mode.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:Badya/models/user_content.dart';
import 'package:Badya/services/content_service.dart';

/// Shared provider that fetches the user's fork tracking data once per session
/// and makes it available to all UI screens (HomePage, LibraryPage, etc.).
///
/// This eliminates the duplicate ~200 document reads that previously occurred
/// when both pages independently called `_loadForkTracking()`.
class ForkTrackingProvider extends ChangeNotifier {
  final ContentService _contentService = ContentService();

  /// Maps canonical content IDs to the set of languages the user has forked them in.
  Map<String, Set<String>> _forkedLanguages = {};
  Map<String, Set<String>> get forkedLanguages => _forkedLanguages;

  /// Maps canonical content IDs to the user's fork document ID.
  Map<String, String> _forkIdByCanonicalId = {};
  Map<String, String> get forkIdByCanonicalId => _forkIdByCanonicalId;

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _loadedUid;

  /// Load fork tracking data. Only fetches once per uid; subsequent calls
  /// are no-ops unless the user changes (uid differs).
  Future<void> loadData({String? forceUid}) async {
    if (LocalMode.enabled) return;
    final uid = forceUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Already loaded for this user — skip duplicate fetches.
    if (_isLoaded && _loadedUid == uid) return;
    if (_isLoading) return;

    _isLoading = true;
    _loadedUid = uid;

    try {
      final snapshot = await _contentService
          .getMyContent(userId: uid, limit: 200)
          .first
          .timeout(const Duration(seconds: 10));

      final newForkedLanguages = <String, Set<String>>{};
      final newForkIdByCanonicalId = <String, String>{};

      for (final c in snapshot) {
        if (c.canonicalContentId != null) {
          newForkedLanguages.putIfAbsent(
            c.canonicalContentId!,
            () => <String>{},
          );
          newForkedLanguages[c.canonicalContentId]!.addAll(c.assignedLanguages);
          newForkIdByCanonicalId[c.canonicalContentId!] = c.id;
        }
      }

      _forkedLanguages = newForkedLanguages;
      _forkIdByCanonicalId = newForkIdByCanonicalId;
      _isLoaded = true;
    } catch (_) {
      // Silently fail — fork detection just won't work.
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Immediately update local state after a new fork is created.
  /// Called by TopicActionHelper.onForkUpdated so the UI reflects the
  /// new fork without a re-fetch.
  void updateFork({
    required String canonicalContentId,
    required Set<String> assignedLanguages,
    String? forkId,
  }) {
    _forkedLanguages.putIfAbsent(canonicalContentId, () => <String>{});
    _forkedLanguages[canonicalContentId]!.addAll(assignedLanguages);
    if (forkId != null) {
      _forkIdByCanonicalId[canonicalContentId] = forkId;
    }
    notifyListeners();
  }

  /// Get the pre-assigned languages for a content item.
  List<String> getPreAssignedLanguages(UserContent content) {
    return _forkedLanguages[content.id]?.toList() ?? [];
  }

  /// Get the user's existing fork ID for this content.
  String? getExistingForkId(UserContent content) {
    return _forkIdByCanonicalId[content.id];
  }

  /// Whether the content has been forked in the given language.
  bool isForkedInLanguage(UserContent content, String language) {
    return _forkedLanguages[content.id]?.contains(language) ?? false;
  }

  /// Reset state (e.g. on sign-out).
  void reset() {
    _forkedLanguages = {};
    _forkIdByCanonicalId = {};
    _isLoaded = false;
    _loadedUid = null;
    notifyListeners();
  }
}
