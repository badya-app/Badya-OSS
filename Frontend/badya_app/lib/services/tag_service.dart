import 'package:Badya/config/local_mode.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:Badya/utils/logger.dart';

/// Service for tag management, suggestions, and filtering.
/// Tags are stored as flat string arrays on user_content documents.
class TagService {
  final FirebaseFirestore? _firestore;
  final FirebaseAuth? _auth;

  TagService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = LocalMode.enabled
            ? firestore
            : (firestore ?? FirebaseFirestore.instance),
        _auth = LocalMode.enabled ? auth : (auth ?? FirebaseAuth.instance);

  String? get _uid => _auth.currentUser?.uid;

  /// Predefined set of common language-learning tags.
  static const List<String> predefinedTags = [
    'Grammar',
    'Vocabulary',
    'Travel',
    'Food',
    'Conversation',
    'Pronunciation',
    'Listening',
    'Writing',
    'Greetings',
    'Business',
    'Culture',
    'Idioms',
    'Slang',
    'News',
    'Technology',
    'Education',
    'Health',
    'Entertainment',
    'Science',
    'History',
  ];

  /// Get the most frequent tags used by the current user.
  /// Scans the user's own content and aggregates tag frequencies.
  Future<List<MapEntry<String, int>>> getUserTopTags({
    int limit = 10,
    String? language,
  }) async {
    if (_uid == null) return [];

    Query query = _firestore
        .collection('user_content')
        .where('user_id', isEqualTo: _uid);

    if (language != null) {
      query = query.where('language', isEqualTo: language);
    }

    try {
      final snapshot = await query.get();
      final tagCounts = <String, int>{};

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final tags = data['tags'] as List<dynamic>?;
        if (tags == null) continue;
        for (final tag in tags) {
          final tagStr = tag.toString().trim().toLowerCase();
          if (tagStr.isNotEmpty) {
            tagCounts[tagStr] = (tagCounts[tagStr] ?? 0) + 1;
          }
        }
      }

      final sorted = tagCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      return sorted.take(limit).toList();
    } catch (e) {
      Logger.error('Error fetching user top tags', e);
      return [];
    }
  }

  /// Get the most frequent tags globally (across all public content).
  Future<List<MapEntry<String, int>>> getGlobalTopTags({
    int limit = 10,
    String? language,
  }) async {
    Query query = _firestore
        .collection('user_content')
        .where('is_public', isEqualTo: true);

    if (language != null) {
      query = query.where('language', isEqualTo: language);
    }

    try {
      final snapshot = await query.get();
      final tagCounts = <String, int>{};

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final tags = data['tags'] as List<dynamic>?;
        if (tags == null) continue;
        for (final tag in tags) {
          final tagStr = tag.toString().trim().toLowerCase();
          if (tagStr.isNotEmpty) {
            tagCounts[tagStr] = (tagCounts[tagStr] ?? 0) + 1;
          }
        }
      }

      final sorted = tagCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      return sorted.take(limit).toList();
    } catch (e) {
      Logger.error('Error fetching global top tags', e);
      return [];
    }
  }

  /// Get tag suggestions for the search bar.
  /// - If user has content: returns user's most frequent tags
  /// - If user has no content: returns predefined tags + global popular tags
  Future<List<String>> getTagSuggestions({
    int limit = 10,
    String? language,
    String? query,
  }) async {
    // Get user's top tags first
    final userTags = await getUserTopTags(limit: limit, language: language);

    if (userTags.isNotEmpty) {
      var suggestions = userTags.map((e) => e.key).toList();
      if (query != null && query.isNotEmpty) {
        suggestions = suggestions
            .where((t) => t.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
      return suggestions;
    }

    // Fallback: global popular tags from public content
    final globalTags = await getGlobalTopTags(
      limit: limit,
      language: language,
    );
    final globalTagNames = globalTags.map((e) => e.key).toSet();

    var suggestions = globalTagNames.toList()..sort();
    if (query != null && query.isNotEmpty) {
      suggestions = suggestions
          .where((t) => t.toLowerCase().contains(query.toLowerCase()))
          .toList();
    }

    return suggestions.take(limit).toList();
  }

  /// Extract unique tags from a list of user_content maps.
  static List<String> extractUniqueTags(List<Map<String, dynamic>> items) {
    final tagSet = <String>{};
    for (final item in items) {
      final tags = item['tags'] as List<dynamic>?;
      if (tags != null) {
        for (final tag in tags) {
          final tagStr = tag.toString().trim().toLowerCase();
          if (tagStr.isNotEmpty) {
            tagSet.add(tagStr);
          }
        }
      }
    }
    return tagSet.toList()..sort();
  }

  /// Filter a list of user_content items by tags (any match).
  static List<Map<String, dynamic>> filterByTags(
    List<Map<String, dynamic>> items,
    List<String> filterTags,
  ) {
    if (filterTags.isEmpty) return items;
    final lowerFilter = filterTags.map((t) => t.toLowerCase()).toSet();
    return items.where((item) {
      final tags = item['tags'] as List<dynamic>?;
      if (tags == null) return false;
      return tags.any(
        (t) => lowerFilter.contains(t.toString().trim().toLowerCase()),
      );
    }).toList();
  }

  /// Filter a list of user_content items by content type.
  static List<Map<String, dynamic>> filterByType(
    List<Map<String, dynamic>> items,
    String? type,
  ) {
    if (type == null || type.isEmpty || type == 'all') return items;
    return items.where((item) {
      final itemType = item['type'] as String? ?? '';
      return itemType == type;
    }).toList();
  }

  /// Filter a list of user_content items by ownership (mine vs public).
  static List<Map<String, dynamic>> filterByOwnership(
    List<Map<String, dynamic>> items,
    String userId, {
    bool? isMine,
    bool? isPublic,
  }) {
    if (isMine == true) {
      return items.where((item) => item['user_id'] == userId).toList();
    }
    if (isPublic == true) {
      return items.where((item) => item['is_public'] == true).toList();
    }
    return items;
  }

  /// Search items by title, description, or tags.
  static List<Map<String, dynamic>> searchItems(
    List<Map<String, dynamic>> items,
    String query,
  ) {
    if (query.isEmpty) return items;
    final lowerQuery = query.toLowerCase();
    return items.where((item) {
      final title =
          (item['title'] as String? ?? '').toLowerCase();
      final description =
          (item['description'] as String? ?? '').toLowerCase();
      final tags = item['tags'] as List<dynamic>? ?? [];

      if (title.contains(lowerQuery)) return true;
      if (description.contains(lowerQuery)) return true;
      if (tags.any(
        (t) => t.toString().toLowerCase().contains(lowerQuery),
      )) {
        return true;
      }
      return false;
    }).toList();
  }
}
