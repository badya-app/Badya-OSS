import 'dart:async';
import 'dart:math' as math;

import 'package:Badya/config/local_mode.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:Badya/config/content_types.dart';
import 'package:Badya/models/source_data.dart';
import 'package:Badya/models/user_content.dart';
import 'package:Badya/services/cache_service.dart';
import 'package:Badya/config/api_config.dart';
import 'package:Badya/utils/content_segmenter.dart';
import 'package:Badya/utils/logger.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Result of a paginated public feed request.
class PaginatedFeedResult {
  final List<UserContent> items;
  final DocumentSnapshot? lastAiDoc;
  final DocumentSnapshot? lastNonAiDoc;
  final bool hasMore;

  PaginatedFeedResult({
    required this.items,
    this.lastAiDoc,
    this.lastNonAiDoc,
    required this.hasMore,
  });
}

/// Unified service for all content operations.
/// Replaces TopicService and ImportService.
/// Operates on the `user_content` Firestore collection.
class ContentService {
  final FirebaseFirestore? _firestore;
  final CacheService? _cacheService;
  final _uuid = const Uuid();

  /// Shared cache service used by default for every `ContentService()`
  /// instantiated without an explicit cache. Set once at app startup via
  /// [registerSharedCacheService] — keeps the many existing `ContentService()`
  /// call sites working while enabling the `metadata/tag_counts` and
  /// recommendations caches in production.
  static CacheService? _sharedCacheService;

  /// Register the app-wide [CacheService] used by every default
  /// `ContentService()` constructor. Call once from `main()` after
  /// `SharedPreferences` is available.
  static void registerSharedCacheService(CacheService? cache) {
    _sharedCacheService = cache;
  }

  /// Debounce timers for _syncOverallProgress (keyed by contentId) to avoid
  /// excessive Firestore reads on rapid progress updates (e.g., video playback
  /// ticks). Using a map ensures each content item has its own debounce timer
  /// and switching between content items doesn't lose pending syncs.
  ///
  /// Static so that debounce works across multiple ContentService instances
  /// (e.g., each video tick creates a new instance in _markProgress).
  static final Map<String, Timer> _syncTimers = {};
  static const Duration _syncDebounceDuration = Duration(seconds: 10);

  ContentService({
    FirebaseFirestore? firestore,
    CacheService? cacheService,
  })  : _firestore = LocalMode.enabled
            ? firestore
            : (firestore ?? FirebaseFirestore.instance),
        _cacheService = cacheService ?? _sharedCacheService;

  CollectionReference<Map<String, dynamic>> get _contentRef =>
      _firestore.collection('user_content');

  /// TTL for cached tag aggregations (relatively stable).
  static const Duration _tagsCacheTTL = Duration(hours: 6);

  /// Reference to the aggregated tag-counts document.
  /// A single document at `metadata/tag_counts` that maintains atomic counters
  /// for every tag across the collection, eliminating full-collection scans.
  DocumentReference<Map<String, dynamic>> get _tagCountsRef =>
      _firestore.collection('metadata').doc('tag_counts');

  /// Atomically increment tag counters for a list of tags.
  /// Caller must `await` so a failure (e.g. permission denied) is observable
  /// — fire-and-forget here would let the aggregate drift if the write fails.
  /// Errors are logged and swallowed: tag counts may drift slightly but the
  /// canonical content is the source of truth and can be rebuilt.
  Future<void> _incrementTagCounts(List<String> tags) async {
    if (tags.isEmpty) return;
    final updates = <String, dynamic>{};
    for (final tag in tags) {
      final normalized = tag.trim().toLowerCase();
      if (normalized.isNotEmpty) {
        updates['counts.$normalized'] = FieldValue.increment(1);
      }
    }
    if (updates.isEmpty) return;
    try {
      await _tagCountsRef
          .set(updates, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      Logger.error('Error incrementing tag counts', e);
    }
  }

  /// Atomically decrement tag counters for a list of tags, floored at 0.
/// Uses a transaction so concurrent decrements can't push a count negative.
  /// Caller must `await` — fire-and-forget here would let the aggregate drift
  /// if the write fails (e.g. permission denied).
  Future<void> _decrementTagCounts(List<String> tags) async {
    if (tags.isEmpty) return;
    try {
      await _firestore
          .runTransaction((txn) async {
            final snapshot = await txn.get(_tagCountsRef);
            final data = snapshot.data()?['counts'] as Map<String, dynamic>? ?? {};
            final updates = <String, dynamic>{};
            for (final tag in tags) {
              final normalized = tag.trim().toLowerCase();
              if (normalized.isEmpty) continue;
              final current = (data[normalized] as num?)?.toInt() ?? 0;
              updates['counts.$normalized'] = math.max(0, current - 1);
            }
            if (updates.isNotEmpty) {
              // Use `txn.update` (not `txn.set` + merge) — partial updates are
              // its native form and we already verified the doc exists above.
              txn.update(_tagCountsRef, updates);
            }
          })
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      Logger.error('Error decrementing tag counts', e);
    }
  }

  // ─── CRUD Operations ──────────────────────────────────────────────

  /// Stream user content with optional filters.
  /// Returns a stream of UserContent models.
  /// Note: Tag-based filtering is done client-side via [TagService.filterByTags].
  Stream<List<UserContent>> getUserContent({
    String? userId,
    String? language,
    ContentType? type,
    bool? isPublic,
    ContentStatus? status,
    int limit = 50,
  }) {
    Query query = _contentRef;

    // Build query chain
    if (userId != null) {
      query = query.where('user_id', isEqualTo: userId);
    }
    if (language != null) {
      query = query.where('assigned_languages', arrayContains: language);
    }
    if (type != null) {
      query = query.where('type', isEqualTo: type.value);
    }
    if (isPublic != null) {
      query = query.where('is_public', isEqualTo: isPublic);
    }
    if (status != null) {
      query = query.where('status', isEqualTo: status.value);
    }

    query = query.orderBy('created_at', descending: true).limit(limit);

    return query.snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => UserContent.fromFirestore(doc))
              .toList(),
        );
  }

  /// Get a single content item once.
  /// Note: Firestore's native offline persistence already caches individual
  /// document reads, so we don't add a SharedPreferences layer on top.
  Future<UserContent?> getContent(String contentId) async {
    try {
      final doc = await _contentRef.doc(contentId).get();
      if (!doc.exists) return null;
      return UserContent.fromFirestore(doc);
    } catch (e) {
      Logger.error('Error fetching content', e);
      return null;
    }
  }

  /// Add new content to the user_content collection.
  /// Returns the document ID of the newly created content.
  ///
  /// [incrementTagCounts] — defaults to true. Forks ([canonicalContentId] is
  /// set) MUST pass false: a fork is a duplicate of the canonical content, not
  /// new content, so its tags should not inflate the global tag counters.
  Future<String> addContent({
    required String userId,
    required ContentType type,
    required String title,
    String authorName = '',
    String? authorPhotoUrl,
    String description = '',
    List<String> tags = const [],
    String language = 'English',
    List<String> assignedLanguages = const [],
    bool isPublic = false,
    ContentSource source = ContentSource.manual,
    String? canonicalContentId,
    OriginType originType = OriginType.userCreated,
    ContentStatus status = ContentStatus.ready,
    Map<String, dynamic>? metadata,
    String? aiPrompt,
    int? wordCount,
    int? lessonCount,
    String? segmentBy,
    int? segmentValue,
    bool incrementTagCounts = true,
  }) async {
    final String contentId = _uuid.v4();
    final now = DateTime.now();

    final content = UserContent(
      id: contentId,
      type: type,
      title: title,
      description: description,
      tags: tags,
      language: language,
      assignedLanguages: assignedLanguages.isEmpty ? [language] : assignedLanguages,
      createdAt: now,
      updatedAt: now,
      userId: userId,
      authorName: authorName,
      authorPhotoUrl: authorPhotoUrl,
      isPublic: isPublic,
      source: source,
      canonicalContentId: canonicalContentId,
      originType: originType,
      progress: 0.0,
      status: status,
      metadata: metadata,
      aiPrompt: aiPrompt,
      wordCount: wordCount,
      lessonCount: lessonCount,
      segmentBy: segmentBy,
      segmentValue: segmentValue,
    );

    await _contentRef
        .doc(contentId)
        .set(content.toFirestore())
        .timeout(const Duration(seconds: 10));

    // Update aggregated tag counts for the new content.
    // Awaited (not fire-and-forget) so that if the counter write fails, the
    // caller is aware. The aggregate is allowed to drift on failure — the
    // canonical `user_content` docs are the source of truth and can be rebuilt.
    if (incrementTagCounts) {
      await _incrementTagCounts(tags);
    }

    return contentId;
  }

  /// Update an existing content item.
  ///
  /// When [tags] is provided, the old tags are read inside the same transaction
  /// that performs the update (no extra round-trip) and the aggregated tag
  /// counters are decremented/incremented after the update commits. The counter
  /// writes are awaited so a failure is observable.
  Future<void> updateContent(
    String contentId, {
    String? title,
    String? description,
    List<String>? tags,
    List<String>? assignedLanguages,
    bool? isPublic,
    String? thumbnailUrl,
    bool? removeThumbnail,
    Map<String, dynamic>? metadata,
    String? aiPrompt,
    int? wordCount,
    int? lessonCount,
  }) async {
    final updates = <String, dynamic>{
      'updated_at': FieldValue.serverTimestamp(),
    };

    if (title != null) updates['title'] = title;
    if (description != null) updates['description'] = description;
    if (tags != null) updates['tags'] = tags;
    if (assignedLanguages != null) {
      updates['assigned_languages'] = assignedLanguages;
    }
    if (isPublic != null) updates['is_public'] = isPublic;
    if (thumbnailUrl != null) {
      // Use dot notation to update only the thumbnail_url field within metadata
      updates['metadata.thumbnail_url'] = thumbnailUrl;
    } else if (removeThumbnail == true) {
      // Remove thumbnail from metadata
      updates['metadata.thumbnail_url'] = FieldValue.delete();
    }
    // Merge metadata keys individually via dot-notation so we don't
    // clobber unrelated fields (e.g. thumbnail_url, chapters) that are
    // already stored inside the metadata map.
    if (metadata != null) {
      for (final entry in metadata.entries) {
        updates['metadata.${entry.key}'] = entry.value;
      }
    }
    if (aiPrompt != null) updates['ai_prompt'] = aiPrompt;
    if (wordCount != null) updates['word_count'] = wordCount;
    if (lessonCount != null) updates['lesson_count'] = lessonCount;

    // Read old tags (when changing tags) inside the same transaction as the
    // update — no extra round-trip. If tags are not changing, skip the read.
    List<String> oldTags = const [];
    final contentRef = _contentRef.doc(contentId);

    if (tags != null) {
      try {
        await _firestore
            .runTransaction((txn) async {
              final snapshot = await txn.get(contentRef);
              if (snapshot.exists) {
                oldTags = (snapshot.data()?['tags'] as List<dynamic>?)
                        ?.map((e) => e.toString())
                        .toList() ??
                    const [];
              }
              txn.update(contentRef, updates);
            })
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        Logger.error('Error updating content $contentId', e);
        rethrow;
      }
    } else {
      await contentRef.update(updates).timeout(const Duration(seconds: 10));
    }

    // After a successful update, sync the aggregated tag counters.
    // Awaited (not fire-and-forget) so a failure is observable to the caller
    // and we don't lose track of pending increments on app crash.
    if (tags != null) {
      await _decrementTagCounts(oldTags);
      await _incrementTagCounts(tags!);
    }
  }

  /// Delete a content item and all associated data.
  ///
  /// Cleans up:
  /// - `user_content/{contentId}` (the document itself)
  /// - `user_content/{contentId}/segments/*` (subcollection)
  /// - `user_content/{contentId}/progress/*` (subcollection)
  /// - `user_content/{contentId}/source/raw` (subcollection)
  /// - `users/{ownerId}/progress/{contentId}` (topic's progress row only)
  /// - `metadata/tag_counts.counts.*` (only for canonical documents — forks
  ///   never incremented counters, so deleting them must NOT decrement either)
  /// - `users/{uid}/imports/{legacyImportId}` (legacy import + lessons)
  Future<void> deleteContent(String contentId) async {
    // 1. Read metadata before deleting the doc
    String? userId;
    List<String> tags = [];
    String? canonicalContentId;
    try {
      final doc = await _contentRef.doc(contentId).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        userId = data['user_id'] as String?;
        tags = (data['tags'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            [];
        canonicalContentId = data['canonical_content_id'] as String?;
      }
    } catch (e) {
      Logger.error('Error reading content metadata for cleanup', e);
    }

    // 2. Delete subcollections (Firestore does not auto-delete these)
    await deleteContentSegments(contentId);
    await deleteContentProgress(contentId);
    await deleteSourceData(contentId);

    // 3. Delete the topic's progress rows (one per language, keyed by `id` field)
    if (userId != null && userId.isNotEmpty) {
      try {
        final progressSnapshot = await _firestore
            .collection('users')
            .doc(userId)
            .collection('progress')
            .where('id', isEqualTo: contentId)
            .get();
        if (progressSnapshot.docs.isNotEmpty) {
          final batch = _firestore.batch();
          for (final doc in progressSnapshot.docs) {
            batch.delete(doc.reference);
          }
          await batch.commit().timeout(const Duration(seconds: 10));
        }
      } catch (e) {
        Logger.error('Error deleting progress for $contentId', e);
      }
    }

    // 4. Delete the document itself.
    await _contentRef
        .doc(contentId)
        .delete()
        .timeout(const Duration(seconds: 10));

    // 5. Decrement aggregated tag counts AFTER a successful delete.
    // Only canonical documents (canonicalContentId == null) ever incremented
    // the counters, so only they may decrement them. Doing this after the
    // delete ensures a failed delete leaves counters untouched (no drift).
    if (canonicalContentId == null) {
      await _decrementTagCounts(tags);
    }

    // Note: Legacy `users/{uid}/imports/{legacyImportId}` is intentionally
    // left in place. It is now dormant — all reads/writes go through
    // `user_content/`. The legacy docs can be cleaned up by a migration
    // script later if desired.
  }

  // ─── Progress ─────────────────────────────────────────────────────

  /// Stream progress for a user's content (stored separately).
  Stream<Map<String, double>> getProgress(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('progress')
        .snapshots()
        .map((snapshot) {
          final progressMap = <String, double>{};
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final contentId = data['id'] as String?;
            final progress = (data['topic_score'] as num?)?.toDouble() ?? 0.0;
            if (contentId != null) {
              progressMap[contentId] = (progress / 100.0).clamp(0.0, 1.0);
            }
          }
          return progressMap;
        });
  }

  /// Update progress for a specific content item.
  Future<void> updateProgress(
    String userId,
    String contentId,
    double progress,
  ) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('progress')
        .doc(contentId)
        .set({
          'id': contentId,
          'topic_score': (progress * 100).round(),
          'last_updated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true))
        .timeout(const Duration(seconds: 10));

    // Also update progress on the content document itself
    await _contentRef.doc(contentId).update({
      'progress': progress,
      'updated_at': FieldValue.serverTimestamp(),
    }).timeout(const Duration(seconds: 10));
  }

  // ─── Language Assignment ──────────────────────────────────────────

  /// Assign content to additional languages.
  Future<void> assignLanguages(
    String contentId,
    List<String> languages,
  ) async {
    await _contentRef
        .doc(contentId)
        .update({
          'assigned_languages': languages,
          'updated_at': FieldValue.serverTimestamp(),
        })
        .timeout(const Duration(seconds: 10));
  }

  // ─── Public / Sharing ─────────────────────────────────────────────

  /// Toggle content visibility (public/private).
  Future<void> toggleVisibility(String contentId, bool isPublic) async {
    await _contentRef
        .doc(contentId)
        .update({
          'is_public': isPublic,
          'updated_at': FieldValue.serverTimestamp(),
        })
        .timeout(const Duration(seconds: 10));
  }

  /// Get public feed (content shared by other users + suggestions).
  ///
  /// When [language] is provided without a specific [type] filter:
  /// - **AI-generated** content is shown across ALL languages (multilingual)
  /// - **Non-AI** content (imported, manual, etc.) is filtered by [assigned_languages]
  ///
  /// When [type] is specified or [language] is null, a single simple query is used.
  Stream<List<UserContent>> getPublicFeed({
    String? language,
    ContentType? type,
    int limit = 50,
  }) {
    // If type is specified or no language is specified, use the simple query
    if (type != null || language == null) {
      return getUserContent(
        isPublic: true,
        language: language,
        type: type,
        limit: limit,
      );
    }

    // Language-specific feed with no type filter:
    // AI-generated content is multilingual — shown for all languages.
    // Non-AI content is filtered by assigned_languages.
    final controller = StreamController<List<UserContent>>();

    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? aiSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? nonAiSub;
    List<UserContent>? aiContent;
    List<UserContent>? nonAiContent;

    void tryEmit() {
      if (aiContent == null || nonAiContent == null) return;

      // Merge and deduplicate by content ID
      final existingIds = <String>{};
      final merged = <UserContent>[];

      // Non-AI content comes first (language-specific)
      for (final item in nonAiContent!) {
        existingIds.add(item.id);
        merged.add(item);
      }

      // Add AI content that doesn't overlap (multilingual)
      for (final item in aiContent!) {
        if (!existingIds.contains(item.id)) {
          merged.add(item);
        }
      }

      // Sort by created_at descending so the combined result is chronological
      merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Apply limit
      controller.add(merged.length > limit ? merged.sublist(0, limit) : merged);
    }

    // Query 1: AI-generated public content — multilingual (no language filter)
    aiSub = _contentRef
        .where('is_public', isEqualTo: true)
        .where('type', isEqualTo: ContentType.aiGenerated.value)
        .orderBy('created_at', descending: true)
        .limit(limit)
        .snapshots()
        .listen((snapshot) {
          aiContent = snapshot.docs
              .map((doc) => UserContent.fromFirestore(doc))
              .toList();
          tryEmit();
        })
      ..onError((error) {
        Logger.error('getPublicFeed AI query error', error);
        controller.addError(error);
      });

    // Query 2: Non-AI public content filtered by assigned_languages
    nonAiSub = _contentRef
        .where('is_public', isEqualTo: true)
        .where('assigned_languages', arrayContains: language)
        .orderBy('created_at', descending: true)
        .limit(limit)
        .snapshots()
        .listen((snapshot) {
          nonAiContent = snapshot.docs
              .map((doc) => UserContent.fromFirestore(doc))
              .toList();
          tryEmit();
        })
      ..onError((error) {
        Logger.error('getPublicFeed non-AI query error', error);
        controller.addError(error);
      });

    controller.onCancel = () {
      aiSub?.cancel();
      nonAiSub?.cancel();
      controller.close();
    };

    return controller.stream;
  }

  /// Fetch a single page of public content with cursor-based pagination.
  ///
  /// When [typeFilter] is provided, only content matching those types is
  /// returned.  This eliminates the need to fetch-and-discard pages on the
  /// client side for narrow filters.
  ///
  /// Filter behaviour:
  /// - `null` → both AI (multilingual) and non-AI (language-filtered) queries
  /// - `{aiGenerated}` → only the AI query runs
  /// - Other non-AI types → only the non-AI query runs, with a type filter
  ///
  /// Returns a [PaginatedFeedResult] with the merged items and the last
  /// document from each *executed* query for the next page's cursor.
  /// Queries that were skipped due to the filter return `null` cursors.
  Future<PaginatedFeedResult> getPublicFeedPage({
    required String language,
    int limit = 50,
    DocumentSnapshot? afterAiDoc,
    DocumentSnapshot? afterNonAiDoc,
    Set<ContentType>? typeFilter,
  }) async {
    try {
      // Determine which query branches are needed.
      final bool isAiOnly =
          typeFilter != null &&
          typeFilter.length == 1 &&
          typeFilter.contains(ContentType.aiGenerated);
      final bool isNonAiOnly =
          typeFilter != null && !isAiOnly;

      List<UserContent> aiContent = [];
      List<UserContent> nonAiContent = [];
      DocumentSnapshot? lastAiDocResult;
      DocumentSnapshot? lastNonAiDocResult;
      bool hasMoreAi = false;
      bool hasMoreNonAi = false;

      if (!isNonAiOnly) {
        // AI query — multilingual, no language filter
        Query aiQuery = _contentRef
            .where('is_public', isEqualTo: true)
            .where('type', isEqualTo: ContentType.aiGenerated.value)
            .orderBy('created_at', descending: true)
            .limit(limit);
        if (afterAiDoc != null) {
          aiQuery = aiQuery.startAfterDocument(afterAiDoc);
        }

        final aiSnapshot = await aiQuery.get();
        aiContent = aiSnapshot.docs
            .map((doc) => UserContent.fromFirestore(doc))
            .toList();
        lastAiDocResult =
            aiSnapshot.docs.isNotEmpty ? aiSnapshot.docs.last : null;
        hasMoreAi = aiSnapshot.docs.length >= limit;
      }

      if (!isAiOnly) {
        // Non-AI query — filtered by assigned_languages
        Query nonAiQuery = _contentRef
            .where('is_public', isEqualTo: true)
            .where('assigned_languages', arrayContains: language)
            .orderBy('created_at', descending: true)
            .limit(limit);

        // Apply type filter for non-AI types when specified.
        if (typeFilter != null && !isAiOnly) {
          final typeValues = typeFilter.map((t) => t.value).toList();
          nonAiQuery = typeValues.length == 1
              ? nonAiQuery.where('type', isEqualTo: typeValues.first)
              : nonAiQuery.where('type', whereIn: typeValues);
        }

        if (afterNonAiDoc != null) {
          nonAiQuery = nonAiQuery.startAfterDocument(afterNonAiDoc);
        }

        final nonAiSnapshot = await nonAiQuery.get();
        nonAiContent = nonAiSnapshot.docs
            .map((doc) => UserContent.fromFirestore(doc))
            .toList();
        lastNonAiDocResult =
            nonAiSnapshot.docs.isNotEmpty ? nonAiSnapshot.docs.last : null;
        hasMoreNonAi = nonAiSnapshot.docs.length >= limit;
      }

      // Merge results depending on which queries ran.
      List<UserContent> merged;
      if (isAiOnly) {
        merged = aiContent;
      } else if (isNonAiOnly) {
        merged = nonAiContent;
      } else {
        // Both queries ran — merge and deduplicate by content ID
        final existingIds = <String>{};
        merged = <UserContent>[];
        for (final item in nonAiContent) {
          existingIds.add(item.id);
          merged.add(item);
        }
        for (final item in aiContent) {
          if (!existingIds.contains(item.id)) {
            merged.add(item);
          }
        }
      }

      merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return PaginatedFeedResult(
        items: merged,
        lastAiDoc: lastAiDocResult,
        lastNonAiDoc: lastNonAiDocResult,
        hasMore: hasMoreAi || hasMoreNonAi,
      );
    } catch (e) {
      Logger.error('getPublicFeedPage failed', e);
      return PaginatedFeedResult(items: [], hasMore: false);
    }
  }

  /// Get user's own content.
  Stream<List<UserContent>> getMyContent({
    required String userId,
    String? language,
    ContentType? type,
    List<String>? tags,
    int limit = 50,
  }) {
    Query query = _contentRef.where('user_id', isEqualTo: userId);

    if (language != null) {
      query = query.where('assigned_languages', arrayContains: language);
    }
    if (type != null) {
      query = query.where('type', isEqualTo: type.value);
    }

    query = query.orderBy('created_at', descending: true).limit(limit);

    return query.snapshots().map(
          (snapshot) => snapshot.docs
              .map((doc) => UserContent.fromFirestore(doc))
              .toList(),
        );
  }

  // ─── Suggestions / Seed Data ──────────────────────────────────────

  /// Fork a suggestion (or any public content) to the user's collection.
  /// Creates a copy with the user's ID and sets origin_type to "forked".
  /// Also clones any underlying lessons so the user has independent progress.
  ///
  /// Increments [popularity_score] on the original content so the
  /// recommendation system can rank by fork popularity.
  Future<String?> addSuggestionToUser({
    required String userId,
    required String suggestionId,
    List<String>? assignedLanguages,
    List<String>? additionalTags,
    /// Where the fork originated: e.g. 'home_recommended', 'library', or null
    /// for unknown/legacy sources. Logged to fork_events for CTR measurement.
    String? source,
  }) async {
    final original = await getContent(suggestionId);
    if (original == null) return null;

    // Merge tags
    final mergedTags = [...original.tags];
    if (additionalTags != null) {
      for (final tag in additionalTags) {
        if (!mergedTags.contains(tag)) {
          mergedTags.add(tag);
        }
      }
    }

    final metadata = Map<String, dynamic>.from(original.metadata ?? {});

    // Create the forked UserContent document with canonical reference.
    // Forks are duplicates of the canonical content, not new content — so
    // they must NOT inflate the global tag counters. The canonical document
    // already owns those tags.
    final forkedId = await addContent(
      userId: userId,
      type: original.type,
      title: original.title,
      authorName: original.authorName,
      authorPhotoUrl: original.authorPhotoUrl,
      description: original.description,
      tags: mergedTags,
      language: original.language,
      assignedLanguages: assignedLanguages ?? original.assignedLanguages,
      isPublic: false, // User's copy starts private
      source: ContentSource.suggestion,
      canonicalContentId: original.id,
      originType: OriginType.forked,
      metadata: metadata,
      wordCount: original.wordCount,
      lessonCount: original.lessonCount,
      segmentBy: original.segmentBy,
      segmentValue: original.segmentValue,
      incrementTagCounts: false,
    );

    // Clone the canonical `source/raw` document into the fork so the fork
    // owns an independent copy of the underlying source data (transcript,
    // raw text, chapters, …). This keeps the fork fully functional even if
    // the original canonical import is deleted or made private later.
    // Failures are non-fatal: segmentation falls back to the canonical
    // document (or metadata) at virtual-segmentation time.
    try {
      var sourceDoc = await _sourceDataRef(original.id).get();
      if (!sourceDoc.exists && original.canonicalContentId != null) {
        // The original is itself a fork — use its canonical source.
        sourceDoc =
            await _sourceDataRef(original.canonicalContentId!).get();
      }
      final sourceData = sourceDoc.data();
      if (sourceDoc.exists && sourceData != null) {
        await _sourceDataRef(forkedId)
            .set(sourceData)
            .timeout(const Duration(seconds: 10));
      }
    } catch (e) {
      Logger.warn('Failed to clone source/raw to fork $forkedId: $e');
    }

    // Increment popularity_score on the original (canonical) content.
    // This is used by the recommendation system for ranking.
    try {
      await _contentRef.doc(suggestionId).update({
        'popularity_score': FieldValue.increment(1),
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      Logger.error('Failed to increment popularity_score for $suggestionId', e);
    }

    // Log fork source event for CTR / engagement metrics
    if (source != null) {
      try {
        await _firestore.collection('fork_events').add({
          'user_id': userId,
          'content_id': suggestionId,
          'fork_id': forkedId,
          'source': source,
          'timestamp': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        Logger.warn('Failed to log fork source event: $e');
      }
    }

    // No lesson cloning needed — segments are computed in-memory at read
    // time (ContentSegmenter). The fork's own `source/raw` copy (cloned
    // above) plus its inherited segment_by/segment_value/lesson_count
    // preferences make the fork fully independent of the canonical document.

    return forkedId;
  }

  // ─── Source Data ──────────────────────────────────────────────────

  DocumentReference<Map<String, dynamic>> _sourceDataRef(String contentId) =>
      _contentRef.doc(contentId).collection('source').doc('raw');

  /// Read the raw source data for a content item.
  /// Returns null if no source data exists.
  Future<SourceData?> getSourceData(String contentId) async {
    try {
      final doc = await _sourceDataRef(contentId).get();
      if (!doc.exists) return null;
      return SourceData.fromMap(doc.data()!);
    } catch (e) {
      Logger.error('Error fetching source data', e);
      return null;
    }
  }

  /// Write raw source data to `user_content/{contentId}/source/raw`.
  Future<void> writeSourceData({
    required String contentId,
    required SourceData sourceData,
  }) async {
    await _sourceDataRef(contentId)
        .set(sourceData.toFirestore(), SetOptions(merge: true))
        .timeout(const Duration(seconds: 10));
  }

  /// Delete the source data for a content item.
  Future<void> deleteSourceData(String contentId) async {
    await _sourceDataRef(contentId).delete().timeout(const Duration(seconds: 10));
  }

  // ─── Lesson Progress Subcollection (Phase 4F) ─────────────────────

  CollectionReference<Map<String, dynamic>> _progressRef(String contentId) =>
      _contentRef.doc(contentId).collection('progress');

  /// Stream lesson progress entries for a content item.
  /// Emits whenever any progress doc changes in the progress subcollection.
  Stream<Map<int, Map<String, dynamic>>> getLessonProgressStream(
    String contentId,
  ) {
    return _progressRef(contentId).snapshots().map((snapshot) {
      final progressMap = <int, Map<String, dynamic>>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final orderIndex = data['order_index'] as int?;
        if (orderIndex != null) {
          progressMap[orderIndex] = {
            ...data,
            'id': doc.id,
          };
        }
      }
      return progressMap;
    });
  }

  /// Read all lesson progress entries for a content item.
  /// Returns a map keyed by orderIndex with full progress doc data.
  /// Returns empty map if no progress exists.
  Future<Map<int, Map<String, dynamic>>> getLessonProgress(
    String contentId,
  ) async {
    try {
      final snapshot =
          await _progressRef(contentId).orderBy('order_index').get();
      final progressMap = <int, Map<String, dynamic>>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final orderIndex = data['order_index'] as int?;
        if (orderIndex != null) {
          progressMap[orderIndex] = {
            ...data,
            'id': doc.id,
          };
        }
      }
      return progressMap;
    } catch (e) {
      Logger.error('Error reading progress for $contentId', e);
      return {};
    }
  }

  /// Update the progress for a specific lesson in a content item.
  ///
  /// Uses a Firestore transaction to only write forward (no regressions).
  /// After writing, recalculates and syncs the overall content progress.
  ///
  /// [position] — For text lessons: 0-1 scroll fraction.
  ///              For video lessons: 0-1 progress fraction (watched/duration).
  /// Update the progress for a specific lesson in a content item.
  ///
  /// Uses a Firestore transaction to only write forward (no regressions).
  /// After writing, recalculates and syncs the overall content progress.
  ///
  /// [position] — For text lessons: 0-1 scroll fraction.
  ///              For video lessons: 0-1 progress fraction (watched/duration).
  /// [immediateSync] — When true, skips the debounce and syncs immediately.
  ///                   Use for explicit user actions (mark complete, scroll-to-end).
  ///                   Default false to batch rapid updates (video playback ticks).
  Future<void> updateLessonProgress({
    required String contentId,
    required int orderIndex,
    required double position,
    bool immediateSync = false,
  }) async {
    final progressDocRef = _progressRef(contentId).doc(orderIndex.toString());

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(progressDocRef);
      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>;
        final currentPosition =
            (data['last_position'] as num?)?.toDouble() ?? 0.0;
        // Only write forward — no regressions
        if (position <= currentPosition) return;
      }

      transaction.set(
        progressDocRef,
        {
          'order_index': orderIndex,
          'last_position': position,
          'completed': position >= 0.99,
          'updated_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }).timeout(const Duration(seconds: 10));

    if (immediateSync) {
      await _syncOverallProgress(contentId);
    } else {
      // Recalculate and update overall content progress (debounced)
      _scheduleSyncOverallProgress(contentId);
    }
  }

  /// Called when a part reaches 100% consumption.
  /// Updates the content doc with the last completed part index
  /// and triggers immediate overall progress sync.
  Future<void> onPartCompleted({
    required String contentId,
    required int orderIndex,
  }) async {
    // 1. Immediate progress sync
    await _syncOverallProgress(contentId);

    // 2. Update the content doc with the last completed part index.
    // Note: Do NOT reset word_generated here — it's tracked per-topic
    // (via the topicId = "{contentId}_part_{orderIndex}" pattern), so
    // resetting it would force word regeneration for ALL parts.
    await _contentRef
        .doc(contentId)
        .update({
          'last_completed_part': orderIndex,
          'updated_at': FieldValue.serverTimestamp(),
        })
        .timeout(const Duration(seconds: 10));
  }

  /// Stream the most recently completed part index for a content item.
  /// Returns null when no part has been completed yet.
  Stream<int?> watchLastCompletedPart(String contentId) {
    return _contentRef.doc(contentId).snapshots().map((doc) {
      return doc.data()?['last_completed_part'] as int?;
    });
  }

  /// Debounce _syncOverallProgress to batch rapid progress updates.
  /// Cancels any pending sync for this contentId and schedules a new one
  /// after [_syncDebounceDuration]. Uses a Map to handle multiple content
  /// items independently.
  void _scheduleSyncOverallProgress(String contentId) {
    _syncTimers[contentId]?.cancel();
    _syncTimers[contentId] = Timer(_syncDebounceDuration, () {
      _syncTimers.remove(contentId);
      _syncOverallProgress(contentId);
    });
  }

  /// Recalculate overall content progress from all lesson progress entries.
  ///
  /// Uses virtual segments to know segment boundaries (start/end times).
  /// For video segments: weighted by duration.
  /// For text-only segments: simple average of lesson progress.
  Future<void> _syncOverallProgress(String contentId) async {
    try {
      final progress = await getLessonProgress(contentId);
      if (progress.isEmpty) return;

      final segments = await _virtualSegments(contentId);
      if (segments == null || segments.isEmpty) return;

      double totalWatched = 0;
      double totalWeight = 0;

      for (final segment in segments) {
        final orderIndex = segment['order_index'] as int? ?? 0;
        final progressEntry = progress[orderIndex];
        if (progressEntry == null) continue;

        final double lastPos =
            (progressEntry['last_position'] as num?)?.toDouble() ?? 0.0;
        final double startTime =
            (segment['start_time'] as num?)?.toDouble() ?? 0.0;
        final double endTime =
            (segment['end_time'] as num?)?.toDouble() ?? 1.0;
        final bool hasTiming =
            segment.containsKey('start_time') && segment.containsKey('end_time');

        if (hasTiming && startTime < endTime) {
          // Video segment: lastPos is 0-1 fraction, duration = end - start
          final double duration = endTime - startTime;
          double watched = lastPos * duration;
          if (lastPos >= 0.99) watched = duration;
          totalWatched += watched;
          totalWeight += duration;
        } else {
          if (hasTiming) {
            Logger.warn(
              'Segment $orderIndex has timing data but start_time ($startTime) '
              '>= end_time ($endTime) — falling back to text weight for '
              'content $contentId',
            );
          }
          // Text segment: lastPos is 0-1 scroll fraction, weight = 1
          totalWatched += lastPos >= 0.99 ? 1.0 : lastPos;
          totalWeight += 1.0;
        }
      }

      final double overallProgress =
          totalWeight > 0 ? (totalWatched / totalWeight).clamp(0.0, 1.0) : 0.0;

      await _contentRef.doc(contentId).update({
        'progress': overallProgress,
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      Logger.error('Error syncing overall progress for $contentId', e);
    }
  }

  /// Merge saved progress into segments by matching on order_index.
  /// Adds `last_position` and `last_updated` fields to each segment.
  List<Map<String, dynamic>> _mergeProgressIntoSegments(
    List<Map<String, dynamic>> segments,
    Map<int, Map<String, dynamic>> progress,
  ) {
    return segments.map((segment) {
      final orderIndex = segment['order_index'] as int? ?? 0;
      final progressEntry = progress[orderIndex];
      if (progressEntry != null) {
        final lastPos = progressEntry['last_position'];
        final lastUpdated = progressEntry['updated_at'];
        final score = progressEntry['score'];
        final lessonProgress = progressEntry['lesson_progress'];
        return {
          ...segment,
          if (lastPos != null) 'last_position': lastPos,
          if (lastUpdated != null) 'last_updated': lastUpdated,
          if (score != null) 'score': score,
          if (lessonProgress != null) 'lesson_progress': lessonProgress,
        };
      }
      return segment;
    }).toList();
  }

  // ─── Segments Subcollection ────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _segmentsRef(String contentId) =>
      _contentRef.doc(contentId).collection('segments');

  /// Stream the segments for a content item — **in-memory virtual segmentation**.
  ///
  /// Reads `source/raw` + `user_content` doc, applies [ContentSegmenter]
  /// in memory, and yields a single list. Merges saved progress from the
  /// `progress` subcollection into the virtual segments.
  /// Returns empty list if no source data is available.
  /// Stream the segments for a content item — **in-memory virtual segmentation**.
  ///
  /// Reads `source/raw` + `user_content` doc, applies [ContentSegmenter]
  /// in memory, and yields segments. Listens to doc updates so when backend
  /// extraction finishes, segments automatically appear.
  Stream<List<Map<String, dynamic>>> getContentSegments(
    String contentId,
  ) async* {
    // Yield immediately from current state
    final inMemoryInitial = await _virtualSegments(contentId);
    if (inMemoryInitial != null) {
      final progress = await getLessonProgress(contentId);
      yield _mergeProgressIntoSegments(inMemoryInitial, progress);
    } else {
      yield [];
    }

    // Also listen to changes on user_content document (e.g. status ready, metadata populated)
    yield* _contentRef.doc(contentId).snapshots().asyncMap((doc) async {
      final inMemory = await _virtualSegments(contentId);
      if (inMemory != null) {
        final progress = await getLessonProgress(contentId);
        return _mergeProgressIntoSegments(inMemory, progress);
      }
      return <Map<String, dynamic>>[];
    });
  }

  /// Fetch segments for a content item once — **in-memory virtual segmentation**.
  /// Merges saved progress into virtual segments.
  /// Returns empty list if no source data is available.
  Future<List<Map<String, dynamic>>> getContentSegmentsOnce(
    String contentId,
  ) async {
    final inMemory = await _virtualSegments(contentId);
    if (inMemory != null) {
      final progress = await getLessonProgress(contentId);
      return _mergeProgressIntoSegments(inMemory, progress);
    }
    return [];
  }

  /// Internal helper: compute virtual segments in-memory via [ContentSegmenter].
  /// Returns `null` if no source data is available (triggers legacy fallback chain).
  ///
  /// **Fork resolution:** The document's own `source/raw` is tried first
  /// (forks receive a cloned copy at fork time). If missing, the canonical
  /// document ([canonicalContentId]) is used as a fallback, and finally the
  /// document's metadata. The fork's own [segmentBy]/[segmentValue]
  /// preferences are used for independent segmentation control.
  Future<List<Map<String, dynamic>>?> _virtualSegments(
    String contentId,
  ) async {
    try {
      // Read user_content doc first (needed for fork resolution)
      final content = await getContent(contentId);
      if (content == null) return null;

      // Source resolution:
      // 1. Prefer the document's OWN source/raw (forks receive a cloned copy
      //    at fork time, making them independent of the canonical document).
      // 2. Fall back to the canonical document for forks created before the
      //    clone existed (or when the clone failed).
      // 3. Fall back to building minimal SourceData from metadata below.
      var sourceData = await getSourceData(contentId);

      if (sourceData == null && content.canonicalContentId != null) {
        sourceData = await getSourceData(content.canonicalContentId!);
      }

      if (sourceData == null) {
        // Fallback: if source/raw does not exist yet, build minimal SourceData from content metadata
        final meta = content.metadata ?? {};
        final sourceUrl = meta['source_url'] as String?;
        final rawText = meta['raw_text'] as String?;
        final transcriptJson = meta['transcript_json'] as String?;
        final st = (meta['source_type'] as String?) ?? content.type.name;

        if (sourceUrl != null || rawText != null || transcriptJson != null || st == 'youtube') {
          sourceData = SourceData(
            sourceUrl: sourceUrl,
            rawText: rawText,
            transcriptJson: transcriptJson,
            sourceType: st,
          );
        } else {
          return null;
        }
      }

      final segmentBy = content.segmentBy ?? 'words';
      final segmentValue = content.segmentValue;
      final sourceType = sourceData.sourceType ??
          content.metadata?['source_type'] as String? ??
          'text';

      // Build a full document map for ContentSegmenter (needs title + metadata)
      final contentData = <String, dynamic>{
        'title': content.title,
        'metadata': content.metadata ?? <String, dynamic>{},
      };

      final virtualLessons = ContentSegmenter.segment(
        source: sourceData,
        segmentBy: segmentBy,
        segmentValue: segmentValue,
        sourceType: sourceType,
        contentData: contentData,
      );

      var segments = virtualLessons
          .asMap()
          .entries
          .map((e) => e.value.toLegacyLessonMap()
            ..['id'] = '${contentId}_${e.key + 1}')
          .toList();

      // Merge editor overrides on top of virtual segments
      final overrides = content.metadata?['editor_overrides'] as Map<String, dynamic>?;
      if (overrides != null && overrides.isNotEmpty) {
        segments = _mergeEditorOverrides(segments, overrides);
      }

      return segments;
    } catch (e) {
      Logger.error('_virtualSegments failed for $contentId', e);
      return null;
    }
  }

  /// Merge editor overrides (title/text_content) into segments by matching
  /// on orderIndex. Overrides are stored as a map keyed by string orderIndex:
  /// `{ "0": { "title": "...", "text_content": "..." }, ... }`
  List<Map<String, dynamic>> _mergeEditorOverrides(
    List<Map<String, dynamic>> segments,
    Map<String, dynamic> overrides,
  ) {
    return segments.map((segment) {
      final orderIndex = (segment['order_index'] as int?).toString();
      final override = overrides[orderIndex] as Map<String, dynamic>?;
      if (override == null) return segment;

      final merged = Map<String, dynamic>.from(segment);
      if (override.containsKey('title')) {
        merged['title'] = override['title'] as String;
      }
      if (override.containsKey('text_content')) {
        merged['text_content'] = override['text_content'] as String;
      }
      // Mark as edited so the UI can show a visual indicator
      merged['has_override'] = true;
      return merged;
    }).toList();
  }

  /// Add languages to an existing forked copy (when user already has a fork
  /// and wants to assign it to additional languages). Updates the
  /// assigned_languages array to include the new languages alongside existing ones.
  Future<void> addLanguagesToFork({
    required String forkId,
    required List<String> newLanguages,
  }) async {
    try {
      final doc = await _contentRef.doc(forkId).get();
      if (!doc.exists) return;

      final data = doc.data() as Map<String, dynamic>;
      final currentLangs = List<String>.from(data['assigned_languages'] as List? ?? []);

      // Merge — deduplicate
      final mergedLangs = {...currentLangs, ...newLanguages}.toList();

      await _contentRef.doc(forkId).update({
        'assigned_languages': mergedLangs,
        'updated_at': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 10));
    } catch (e) {
      Logger.error('Error adding languages to fork $forkId', e);
    }
  }

  /// Update the segmentation preference on the `user_content` document only.
  ///
  /// Phase 4C: No Firestore batch writes to `segments` subcollection —
  /// the preference is stored and segments are computed in-memory at read
  /// time by [ContentSegmenter].
  /// Also clears any editor overrides since segments will change.
  ///
  /// After the preference is written, the new segment count is recomputed
  /// from [_virtualSegments] and `lesson_count` is saved on the document so
  /// list/UI views show the new count immediately.
  Future<void> updateSegmentationPreference({
    required String contentId,
    required String segmentBy,
    int? segmentValue,
  }) async {
    await _contentRef
        .doc(contentId)
        .update({
          'segment_by': segmentBy,
          if (segmentValue != null) 'segment_value': segmentValue,
          'metadata.editor_overrides': FieldValue.delete(),
          'updated_at': FieldValue.serverTimestamp(),
        })
        .timeout(const Duration(seconds: 10));

    // Recompute and persist the new lesson count. Non-fatal: if source data
    // is not available yet the count simply stays as-is.
    try {
      final segments = await _virtualSegments(contentId);
      if (segments != null) {
        await _contentRef
            .doc(contentId)
            .update({
              'lesson_count': segments.length,
              'updated_at': FieldValue.serverTimestamp(),
            })
            .timeout(const Duration(seconds: 10));
      }
    } catch (e) {
      Logger.warn('Failed to refresh lesson_count for $contentId: $e');
    }
  }

  /// Save an individual lesson override (title and/or text_content) for a
  /// specific segment identified by [orderIndex]. Overrides are stored inside
  /// the `metadata` map on the `user_content` doc under `editor_overrides`,
  /// keyed by orderIndex (string). They are merged on top of virtual segments
  /// at read time by [_mergeEditorOverrides].
  ///
  /// Only non-null fields are written — pass `null` for a field to keep its
  /// existing value from the virtual segment.
  Future<void> updateLessonOverride({
    required String contentId,
    required int orderIndex,
    String? title,
    String? textContent,
  }) async {
    final prefix = 'metadata.editor_overrides.$orderIndex';
    final updates = <String, dynamic>{
      'updated_at': FieldValue.serverTimestamp(),
    };
    if (title != null) updates['$prefix.title'] = title;
    if (textContent != null) updates['$prefix.text_content'] = textContent;
    await _contentRef
        .doc(contentId)
        .update(updates)
        .timeout(const Duration(seconds: 10));
  }

  /// Clear all editor overrides for a content item.
  Future<void> clearLessonOverrides(String contentId) async {
    await _contentRef
        .doc(contentId)
        .update({
          'metadata.editor_overrides': FieldValue.delete(),
          'updated_at': FieldValue.serverTimestamp(),
        })
        .timeout(const Duration(seconds: 10));
  }

  /// Clean up legacy segments subcollection for content that has migrated
  /// to the new in-memory virtual segmentation path.
  Future<void> clearLegacySegments(String contentId) async {
    final snapshot = await _segmentsRef(contentId).get();
    if (snapshot.docs.isEmpty) return;
    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit().timeout(const Duration(seconds: 10));
  }

  /// Delete all progress entries for a content item.
  Future<void> deleteContentProgress(String contentId) async {
    final snapshot = await _progressRef(contentId).get();
    if (snapshot.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit().timeout(const Duration(seconds: 10));
  }

  /// Delete all segments for a content item.
  Future<void> deleteContentSegments(String contentId) async {
    final snapshot = await _segmentsRef(contentId).get();
    if (snapshot.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit().timeout(const Duration(seconds: 10));
  }

  // ─── Import Helpers ───────────────────────────────────────────────

  /// Update the status of an import (processing → ready / failed).
  Future<void> updateImportStatus(
    String contentId,
    ContentStatus status, {
    Map<String, dynamic>? metadata,
  }) async {
    final updates = <String, dynamic>{
      'status': status.value,
      'updated_at': FieldValue.serverTimestamp(),
    };
    if (metadata != null) {
      for (final entry in metadata.entries) {
        updates['metadata.${entry.key}'] = entry.value;
      }
    }
    await _contentRef
        .doc(contentId)
        .update(updates)
        .timeout(const Duration(seconds: 10));
  }

  /// Mark content as opened (update last_opened_at).
  Future<void> markAsOpened(String contentId) async {
    await _contentRef
        .doc(contentId)
        .update({
          'last_opened_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
        })
        .timeout(const Duration(seconds: 10));
  }

  /// Search public content via the backend server.
  ///
  /// Sends the query to the /recommendations/search endpoint which performs
  /// hybrid (semantic + keyword) scoring server-side.  Returns items sorted
  /// by relevance.  Falls back to an empty result on error so the caller can
  /// degrade to local-only search gracefully.
  ///
  /// [typeFilter] — optional set of ContentType values to restrict results.
  Future<PaginatedFeedResult> searchPublicFeed({
    required String query,
    required String language,
    int limit = 50,
    Set<ContentType>? typeFilter,
  }) async {
    try {
      final url = Uri.parse(
        '${ApiConfig.getBaseUrl()}/recommendations/search',
      );
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'query': query,
              'language': language,
              'limit': limit,
              if (typeFilter != null)
                'type_filter': typeFilter.map((t) => t.value).toList(),
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final items = (data['items'] as List)
            .map((e) => UserContent.fromMap(e as Map<String, dynamic>, e['id']))
            .toList();
        final hasMore = data['has_more'] as bool;
        return PaginatedFeedResult(
          items: items,
          hasMore: hasMore,
        );
      } else {
        Logger.warn(
          'Server search returned ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      Logger.warn('Server search failed, falling back to local: $e');
    }
    // Fallback: return empty result — caller degrades to local search
    return PaginatedFeedResult(items: [], hasMore: false);
  }

  /// Log a recommendation click event to Firestore.
  ///
  /// Records when a user taps on a recommended/public content card.
  /// Used by the daily metric computation to calculate CTR, Precision@K, etc.
  ///
  /// [source] indicates where the click happened: "home_recommended" or "library".
  Future<void> logRecommendationClick({
    required String userId,
    required String contentId,
    required String source,
  }) async {
    try {
      final now = DateTime.now();
      final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await _firestore.collection('recommendation_clicks').add({
        'user_id': userId,
        'content_id': contentId,
        'source': source,
        'impression_date': dateStr,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Non-blocking — silently fail; click logging should never
      // interfere with the user experience
      Logger.warn('Failed to log recommendation click: $e');
    }
  }

  /// Get the current Firebase Auth ID token (if logged in).
  Future<String?> _getIdToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        return await user.getIdToken();
      }
    } catch (e) {
      Logger.warn('Failed to get Firebase ID token: $e');
    }
    return null;
  }

  /// Get personalized recommendations for a user (Phases 2 & 3).
  ///
  /// Calls the standalone Recommendation Service API endpoint.
  /// Falls back to simple rule-based recommendations if backend is unreachable.
  Future<List<UserContent>> getRecommendations({
    required String userId,
    required String language,
    int limit = 20,
  }) async {
    final cacheKey = '__recommendations_${userId}_${language}__';

    // 1. Try local cache first (1-hour TTL)
    if (_cacheService != null) {
      try {
        final cached = await _cacheService.getCache(cacheKey);
        if (cached != null) {
          final items = (cached['items'] as List)
              .map((e) => UserContent.fromMap(e, e['id']))
              .toList();
          return items;
        }
      } catch (e) {
        Logger.warn('Recommendation cache miss: $e');
      }
    }

    // 2. Call the separate Recommendation Service with Firebase Auth token
    try {
      final url = Uri.parse(ApiConfig.recommendationsUrl);
      final idToken = await _getIdToken();
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (idToken != null) {
        headers['Authorization'] = 'Bearer $idToken';
      }

      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode({
          'user_id': userId,
          'language': language,
          'limit': limit,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final recommendations = data
            .map((item) => UserContent.fromMap(item as Map<String, dynamic>, item['id']))
            .toList();

        // Cache results
        if (_cacheService != null) {
          await _cacheService.setCache(
            contentId: cacheKey,
            data: {
              'items': recommendations.map((r) => r.toFirestore()..['id'] = r.id).toList(),
            },
            ttl: const Duration(hours: 1),
          );
        }

        return recommendations;
      } else {
        Logger.warn('Recommendation backend error: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      Logger.error('Failed to fetch recommendations from backend', e);
    }

    // 3. Fallback: Simple rule-based popularity / language match (Phase 1 logic)
    try {
      final snapshot = await _contentRef
          .where('is_public', isEqualTo: true)
          .where('assigned_languages', arrayContains: language)
          .orderBy('created_at', descending: true)
          .limit(limit * 2)
          .get();

      final candidates = snapshot.docs
          .map((doc) => UserContent.fromFirestore(doc))
          .toList();

      // Simple shuffle for variety in fallback
      candidates.shuffle();
      return candidates.take(limit).toList();
    } catch (e) {
      Logger.error('Fallback recommendations failed', e);
      return [];
    }
  }

  /// Get all unique tags from the aggregated `metadata/tag_counts` document.
  /// This replaces the previous full-collection scan with a single document
  /// read. The result is cached for [_tagsCacheTTL] to further reduce reads.
  Future<List<MapEntry<String, int>>> getAllTagsWithCounts({
    int limit = 50,
  }) async {
    const cacheKey = '__all_tags_with_counts__';

    // 1. Try cache
    if (_cacheService != null) {
      try {
        final cached = await _cacheService.getCache(cacheKey);
        if (cached != null) {
          final list = (cached['tags'] as List<dynamic>)
              .map((e) => MapEntry<String, int>(
                    e['name'] as String,
                    e['count'] as int,
                  ))
              .toList();
          return list.take(limit).toList();
        }
      } catch (_) {
        // Cache miss — fall through
      }
    }

    // 2. Read from the aggregated tag-counts document (single read).
    try {
      final snapshot = await _tagCountsRef.get();
      final counts = snapshot.data()?['counts'] as Map<String, dynamic>? ?? {};

      final sorted = counts.entries
          .map((e) => MapEntry(e.key, (e.value as num).toInt()))
          .where((e) => e.value > 0)
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final result = sorted.take(limit).toList();

      // 3. Cache the result
      if (_cacheService != null) {
        await _cacheService.setCache(
          contentId: cacheKey,
          data: {
            'tags': result
                .map((e) => {'name': e.key, 'count': e.value})
                .toList(),
          },
          ttl: _tagsCacheTTL,
        );
      }

      return result;
    } catch (e) {
      Logger.error('Error getting all tags', e);
      return [];
    }
  }
}
