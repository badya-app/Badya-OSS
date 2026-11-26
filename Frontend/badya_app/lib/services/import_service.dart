import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:Badya/config/local_mode.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import 'package:Badya/config/api_config.dart';
import 'package:Badya/models/source_data.dart';
import 'package:Badya/services/adk_service.dart';
import 'package:Badya/utils/constants.dart';
import 'package:Badya/utils/content_segmenter.dart';
import 'package:Badya/utils/logger.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class ImportService {
  static final ImportService _instance = ImportService._internal();
  factory ImportService() => _instance;
  ImportService._internal();

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;
  final _uuid = const Uuid();

  String? get _uid => _auth.currentUser?.uid;

  String _currentLanguage = 'English';
  String get currentLanguage => _currentLanguage;

  /// Sets the active language for import operations.
  /// All subsequent reads/writes will be scoped to this language.
  void setLanguage(String lang) {
    _currentLanguage = lang;
  }

  String _currentLanguageCode() {
    final base = _currentLanguage.split('(').first.trim();
    final mapped = languageBcp47Codes[base];
    if (mapped != null) return mapped;

    if (base.length == 2) return base.toLowerCase();
    if (base.length == 3) return base.toLowerCase();
    return 'en';
  }

  /// Returns true if the given section ID is a default section (any language).
  static bool isDefaultSectionId(String? sectionId) {
    if (sectionId == null) return false;
    return sectionId.startsWith('default_import_section') ||
        sectionId.startsWith('default_file_section');
  }

  CollectionReference get _importsRef => _firestore
      .collection('users')
      .doc(_uid ?? 'anonymous')
      .collection('imports');

  CollectionReference get _sectionsRef => _firestore
      .collection('users')
      .doc(_uid ?? 'anonymous')
      .collection('import_sections');

  CollectionReference get _userContentRef =>
      _firestore.collection('user_content');

  /// Reference to the aggregated tag-counts document.
  /// Kept in sync with ContentService._tagCountsRef.
  DocumentReference<Map<String, dynamic>> get _tagCountsRef =>
      _firestore.collection('metadata').doc('tag_counts');

  /// Map internal source type to user_content type string.
  String _mapSourceTypeToContentType(String sourceType) {
    switch (sourceType) {
      case 'youtube':
        return 'youtube';
      case 'url':
        return 'article';
      case 'pdf':
        return 'pdf';
      case 'txt':
        return 'document';
      case 'text':
        return 'text';
      default:
        return 'text';
    }
  }

  /// Creates the initial user_content entry (status: processing) linked to a legacy import.
  /// [contentId] is the single UUID used for BOTH the legacy import doc and the
  /// user_content doc, so the backend can write results directly to
  /// user_content/{contentId} without a cross-reference lookup.
  /// Returns the user_content document ID (same as [contentId]).
  Future<String> _createUserContentEntry({
    required String userId,
    required String importId,
    required String contentId,
    required String sourceType,
    required String title,
    required String language,
    List<String> tags = const [],
    String? filePath,
    String? rawText,
    String? sourceUrl,
    bool isPublic = false,
    String? segmentBy,
    int? segmentValue,
  }) async {
    final now = DateTime.now();
    final user = _auth.currentUser;

    final metadata = <String, dynamic>{
      'legacy_import_id': importId,
      'source_type': sourceType,
    };
    if (sourceUrl != null) metadata['source_url'] = sourceUrl;
    if (filePath != null) metadata['file_path'] = filePath;
    if (rawText != null) metadata['raw_text'] = rawText;

    await _userContentRef
        .doc(contentId)
        .set({
          'type': _mapSourceTypeToContentType(sourceType),
          'title': title.isEmpty ? 'Processing...' : title,
          'description': '',
          'tags': tags,
          'language': language,
          'assigned_languages': [language],
          'created_at': Timestamp.fromDate(now),
          'updated_at': Timestamp.fromDate(now),
          'user_id': userId,
          'author_name': user?.displayName ?? '',
          'author_photo_url': user?.photoURL,
          'is_public': isPublic,
          'is_canonical': true, // Original imports are canonical
          'source': 'import',
          'origin_type': 'user_created',
          'progress': 0.0,
          'status': 'processing',
          'metadata': metadata,
          if (segmentBy != null) 'segment_by': segmentBy,
          if (segmentValue != null) 'segment_value': segmentValue,
        })
        .timeout(const Duration(seconds: 10));

    // Update aggregated tag counts for the new content.
    if (tags.isNotEmpty) {
      try {
        final updates = <String, dynamic>{};
        for (final tag in tags) {
          final normalized = tag.trim().toLowerCase();
          if (normalized.isNotEmpty) {
            updates['counts.$normalized'] = FieldValue.increment(1);
          }
        }
        if (updates.isNotEmpty) {
          await _tagCountsRef
              .set(updates, SetOptions(merge: true))
              .timeout(const Duration(seconds: 10));
        }
      } catch (_) {
        // Non-fatal: tag counts may drift but will be corrected on next rebuild.
      }
    }

    // Store the user_content_id back on the old import for cross-referencing
    await _importsRef
        .doc(importId)
        .update({'metadata.user_content_id': contentId})
        .timeout(const Duration(seconds: 10));

    // Write source data subcollection (raw content for re-segmentation)
    try {
      final sourceData = SourceData(
        rawText: rawText,
        sourceUrl: sourceUrl,
        sourceType: sourceType,
      );
      await _userContentRef
          .doc(contentId)
          .collection('source')
          .doc('raw')
          .set(sourceData.toFirestore())
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      Logger.warn('Failed to write source data for $contentId: $e');
    }

    return contentId;
  }

  /// Update the status and optional metadata on a user_content entry.
  Future<void> _updateUserContentEntry(
    String contentId, {
    required String status,
    Map<String, dynamic>? metadata,
    int? wordCount,
    int? lessonCount,
    String? segmentBy,
    int? segmentValue,
  }) async {
    final updates = <String, dynamic>{
      'status': status,
      'updated_at': FieldValue.serverTimestamp(),
    };
    // Merge metadata keys individually via dot-notation so we don't
    // clobber unrelated fields (e.g. thumbnail_url) already in metadata.
    if (metadata != null) {
      for (final entry in metadata.entries) {
        updates['metadata.${entry.key}'] = entry.value;
      }
    }
    if (wordCount != null) updates['word_count'] = wordCount;
    if (lessonCount != null) updates['lesson_count'] = lessonCount;
    if (segmentBy != null) updates['segment_by'] = segmentBy;
    if (segmentValue != null) updates['segment_value'] = segmentValue;
    await _userContentRef
        .doc(contentId)
        .update(updates)
        .timeout(const Duration(seconds: 10));
  }

  /// Creates a new import record in Firestore.
  ///
  /// Uses a SINGLE UUID for both the legacy import and the user_content doc,
  /// so the backend can write results directly to user_content/{importId}
  /// without needing a cross-reference lookup.
  Future<String> createImport({
    required String title,
    String? sectionId,
    String? subjectId,
    String? sourceUrl,
    String? filePath,
    String? rawText,

    /// Explicit source type override. When null, auto-detected from other params.
    /// Supported: 'youtube' | 'url' | 'pdf' | 'txt' | 'text'
    String? sourceType,
    bool runSync = true,
    String? segmentBy,
    int? segmentValue,
    List<String> tags = const [],
    String language = 'English',

    /// Whether this content should be visible to everyone in the library.
    bool isPublic = false,
  }) async {
    final userId = _uid ?? 'anonymous';
    // Single UUID used for BOTH the legacy import doc and the user_content doc.
    final String singleId = _uuid.v4();

    // Auto-detect source type when not explicitly provided
    if (sourceType == null) {
      final bool isYouTube =
          sourceUrl != null &&
          (sourceUrl.contains('youtube.com') || sourceUrl.contains('youtu.be'));
      if (isYouTube) {
        sourceType = 'youtube';
      } else if (filePath != null) {
        sourceType = filePath.toLowerCase().endsWith('.pdf') ? 'pdf' : 'txt';
      } else if (rawText != null) {
        sourceType = 'text';
      } else {
        sourceType = 'txt';
      }
    }

    // Override _currentLanguage with the provided language so downstream
    // processing methods (_processLocally / _processViaBackend) use it.
    _currentLanguage = language;

    final bool isYouTube = sourceType == 'youtube';

    // Determine default section based on type — language-specific
    final defaultSectionId = isYouTube
        ? 'default_import_section_$_currentLanguage'
        : 'default_file_section_$_currentLanguage';

    // 1. Initial Firestore record (as processing)
    final newImport = {
      'title': title.isEmpty ? 'Processing...' : title,
      'section_id': sectionId ?? defaultSectionId,
      'subject_id': subjectId,
      'source_type': sourceType,
      'source_url': sourceUrl,
      'file_path': filePath,
      'raw_text': rawText != null && rawText.length > 50
          ? "${rawText.substring(0, 50)}..."
          : rawText,
      'language': _currentLanguage,
      'status': 'processing',
      'created_at': FieldValue.serverTimestamp(),
      'last_updated': FieldValue.serverTimestamp(),
      'metadata': {'source_type': sourceType},
    };

    await _importsRef
        .doc(singleId)
        .set(newImport)
        .timeout(const Duration(seconds: 10));

    // 1b. Create the user_content entry immediately (status: processing)
    //     so the new UI sees it in the library.
    // Uses the SAME UUID (singleId) for both docs so backend can write
    // directly to user_content/{import_id} without a cross-reference.
    final userContentId = await _createUserContentEntry(
      userId: userId,
      importId: singleId,
      contentId: singleId,
      sourceType: sourceType,
      title: title,
      language: language,
      tags: tags,
      filePath: filePath,
      rawText: rawText,
      sourceUrl: sourceUrl,
      isPublic: isPublic,
      segmentBy: segmentBy,
      segmentValue: segmentValue,
    );

    // Update section timestamp when content is added
    if (sectionId != null) {
      await _sectionsRef
          .doc(sectionId)
          .update({'last_updated': FieldValue.serverTimestamp()})
          .timeout(const Duration(seconds: 10));
    }

    final String importId = singleId;

    // 2. Route: local processing for TXT/text, backend for everything else.
    if (sourceType == 'text' || sourceType == 'txt') {
      await _processLocally(
        importId: importId,
        userContentId: userContentId,
        sourceType: sourceType,
        title: title,
        filePath: filePath,
        rawText: rawText,
      );
    } else {
      try {
        await _processViaBackend(
          importId: importId,
          userContentId: userContentId,
          userId: userId,
          sourceType: sourceType,
          title: title,
          sourceUrl: sourceUrl,
          filePath: filePath,
          subjectId: subjectId,
          rawText: rawText,
        );
      } catch (e) {
        Logger.warn('Backend processing failed: $e');
        // Mark user_content as ready with minimal data so it appears in the library
        await _updateUserContentEntry(
          userContentId,
          status: 'ready',
          metadata: {
            'legacy_import_id': importId,
            'source_type': sourceType,
            'message':
                'Backend unreachable. Content will be processed when available.',
          },
        );
      }
    }

    return importId;
  }

  // ---------------------------------------------------------------
  // Local Processing (TXT files + raw text) — no server needed
  // ---------------------------------------------------------------

  /// Process text-based imports entirely on the client.
  Future<void> _processLocally({
    required String importId,
    required String userContentId,
    required String sourceType,
    required String title,
    String? filePath,
    String? rawText,
  }) async {
    try {
      String text = '';
      Map<String, dynamic> metadata = {};

      if (sourceType == 'text' && rawText != null) {
        // Raw text import
        text = rawText;
        final sizeBytes = utf8.encode(text).length;
        metadata = {
          'type': 'text',
          'char_count': text.length,
          'word_count': text
              .split(RegExp(r'\s+'))
              .where((w) => w.isNotEmpty)
              .length,
          'file_size_bytes': sizeBytes,
          'file_size': _formatBytes(sizeBytes),
        };
      } else if (sourceType == 'txt' && filePath != null) {
        // TXT file import — read locally
        final file = File(filePath);
        if (!await file.exists()) {
          throw Exception('File not found: $filePath');
        }
        try {
          text = await file.readAsString(encoding: utf8);
        } catch (e) {
          Logger.warn('Failed to read file as UTF-8, trying Latin-1: $e');
          text = await file.readAsString(encoding: latin1);
        }
        final sizeBytes = await file.length();
        metadata = {
          'file_size_bytes': sizeBytes,
          'file_size': _formatBytes(sizeBytes),
        };
      }

      if (text.trim().isEmpty) {
        throw Exception('File is empty or contains no readable text.');
      }

      // Detect language
      final lang = _detectLanguage(text);
      if (lang != null) {
        metadata['language'] = lang;
      }

      // Segment into lessons
      final List<Map<String, dynamic>> lessons;
      if (sourceType == 'text') {
        // Raw text import: always a single part
        lessons = [
          {
            'id': '${importId}_part_1',
            'title': title,
            'text_content': text,
            'order_index': 0,
            'is_processed': true,
          },
        ];
      } else {
        // TXT file import: delegate segmentation to ContentSegmenter
        final sourceData = SourceData(rawText: text, sourceType: sourceType);
        final virtualLessons = ContentSegmenter.segment(
          source: sourceData,
          segmentBy: 'words',
          sourceType: sourceType,
        );
        lessons = virtualLessons
            .asMap()
            .entries
            .map(
              (e) =>
                  e.value.toLegacyLessonMap()
                    ..['id'] = '${importId}_part_${e.key + 1}',
            )
            .toList();
      }

      // Save to Firestore
      await _importsRef
          .doc(importId)
          .update({
            'status': 'ready',
            'metadata': metadata,
            'last_updated': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 10));

      // Sync user_content entry: mark as ready with metadata
      final userContentMeta = <String, dynamic>{
        'legacy_import_id': importId,
        'source_type': sourceType,
        ...metadata,
      };
      final localWordCount = text
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .length;
      await _updateUserContentEntry(
        userContentId,
        status: 'ready',
        metadata: userContentMeta,
        wordCount: metadata['word_count'] as int? ?? localWordCount,
        lessonCount: lessons.length,
      );

      // Update source data with computed values from local processing
      try {
        final sourceData = SourceData(
          rawText: text,
          sourceType: sourceType,
          wordCount: localWordCount,
          characterCount: text.length,
        );
        await _userContentRef
            .doc(userContentId)
            .collection('source')
            .doc('raw')
            .set(sourceData.toFirestore(), SetOptions(merge: true))
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        Logger.warn('Failed to update source data after local processing: $e');
      }

      // Generate embedding for the recommendation system
      await _generateEmbedding(
        contentId: userContentId,
        title: title,
        rawText: text,
      );

      Logger.info(
        'Locally processed import $importId (${lessons.length} lessons)',
      );
    } catch (e) {
      Logger.error('Local processing failed', e);
      await _importsRef
          .doc(importId)
          .update({
            'status': 'failed',
            'metadata': {'error': e.toString()},
            'last_updated': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 10));
      // Also mark user_content as failed
      await _updateUserContentEntry(
        userContentId,
        status: 'failed',
        metadata: {'legacy_import_id': importId, 'error': e.toString()},
      );
    }
  }

  /// Generate embedding via the AI server's /recommendations/embed endpoint.
  /// Uses title + first ~2000 chars of raw text for the embedding payload.
  /// The embedding is stored directly on the user_content doc metadata.
  /// Returns silently on failure — embedding is optional for cold-start recommendation.
  Future<void> _generateEmbedding({
    required String contentId,
    required String title,
    required String rawText,
  }) async {
    try {
      // Truncate to ~2000 characters — enough for a meaningful semantic vector
      final excerpt = rawText.length > 2000
          ? rawText.substring(0, 2000)
          : rawText;

      final url = Uri.parse('${ApiConfig.getBaseUrl()}/recommendations/embed');
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'title': title,
              'description': excerpt,
              'tags': <String>[],
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        final embedding = List<double>.from(result['embedding']);
        // Check for zero vector — don't store if empty
        if (embedding.any((v) => v != 0.0)) {
          await _firestore
          .collection('user_content')
          .doc(contentId)
          .update({'metadata.embedding': embedding})
          .timeout(const Duration(seconds: 10));
        }
      }
    } catch (e) {
      // Backend unreachable or timeout — embedding is optional
      Logger.warn('_generateEmbedding failed (non-blocking): $e');
    }
  }

  /// Simple language detection — checks for common English words.
  String? _detectLanguage(String text) {
    const commonEn = {
      'the',
      'be',
      'to',
      'of',
      'and',
      'a',
      'in',
      'that',
      'have',
      'i',
    };
    final words = text.toLowerCase().split(RegExp(r'\s+')).take(100).toList();
    final enCount = words.where((w) => commonEn.contains(w)).length;
    return enCount > 5 ? 'en' : null;
  }

  // ---------------------------------------------------------------
  // Backend Processing (YouTube + PDF)
  // ---------------------------------------------------------------

  /// Get the current Firebase Auth ID token (if logged in).
  Future<String?> _getIdToken() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        return await user.getIdToken();
      }
    } catch (e) {
      Logger.warn('Failed to get Firebase ID token: $e');
    }
    return null;
  }

  Future<void> _processViaBackend({
    required String importId,
    required String userContentId,
    required String userId,
    required String sourceType,
    required String title,
    String? sourceUrl,
    String? filePath,
    String? subjectId,
    String? rawText,
  }) async {
    const bool runSync = true;
    bool success = false;
    String lastError = '';
    for (final url in ApiConfig.contentServiceImportUrls) {
      if (success) break;

      try {
        Logger.info('Attempting to call backend with Multipart: $url');

        final request = http.MultipartRequest('POST', Uri.parse(url));

        // Add Firebase Auth token if available
        final idToken = await _getIdToken();
        if (idToken != null) {
          request.headers['Authorization'] = 'Bearer $idToken';
        }

        // Add form fields
        request.fields['user_id'] = userId;
        request.fields['source_type'] = sourceType;
        request.fields['title'] = title;
        request.fields['import_id'] = importId;
        request.fields['target_language'] = _currentLanguageCode();
        if (sourceUrl != null) request.fields['source_url'] = sourceUrl;
        if (subjectId != null) request.fields['subject_id'] = subjectId;
        if (rawText != null) request.fields['raw_text'] = rawText;
        request.fields['run_sync'] = runSync.toString();

        // Add file if exists
        if (filePath != null && sourceType != 'youtube') {
          request.files.add(
            await http.MultipartFile.fromPath('file', filePath),
          );
        }

        final streamedResponse = await request.send().timeout(
          const Duration(seconds: 120),
        );
        final response = await http.Response.fromStream(streamedResponse);

        // 202 = async queued (background task). Firestore will be updated by
        // the server when processing completes. Nothing more to do.
        if (response.statusCode == 429) {
          // Rate limit hit — preserve the structured error message
          Logger.error('Rate limit exceeded on import: ${response.body}');
          try {
            final errorBody = jsonDecode(response.body);
            final detail = errorBody['detail'];
            if (detail is Map) {
              lastError = detail['message'] ?? 'rate_limit_exceeded';
            } else if (detail is String) {
              lastError = detail;
            }
          } catch (_) {
            lastError = 'rate_limit_exceeded';
          }
          // Don't retry other URLs — rate limit applies to all
          break;
        } else if (response.statusCode == 202) {
          success = true;
          Logger.info('Backend accepted import as background task at $url');
        } else if (response.statusCode == 200) {
          final result = jsonDecode(response.body);

          if (result['status'] == 'success') {
            Map<String, dynamic> updates = {
              'status': 'ready',
              'last_updated': FieldValue.serverTimestamp(),
            };

            if (result['metadata'] != null) {
              final backendMeta = Map<String, dynamic>.from(result['metadata']);
              // Preserve the source_type we already wrote
              backendMeta.putIfAbsent('source_type', () => sourceType);
              // transcript_json is stored in source/raw subcollection only —
              // strip it from metadata to avoid duplication on the doc.
              backendMeta.remove('transcript_json');
              for (final entry in backendMeta.entries) {
                updates['metadata.${entry.key}'] = entry.value;
              }
            }

            if (result['title'] != null &&
                result['title'] != 'Untitled Import') {
              updates['title'] = result['title'];
            }

            await _importsRef
                .doc(importId)
                .update(updates)
                .timeout(const Duration(seconds: 10));

            // Determine backend metadata for syncing
            final backendMeta = result['metadata'] != null
                ? Map<String, dynamic>.from(result['metadata'])
                : <String, dynamic>{};
            // Strip transcript_json — stored in source/raw only
            backendMeta.remove('transcript_json');

            // Sync user_content entry: mark as ready with backend metadata
            await _updateUserContentEntry(
              userContentId,
              status: 'ready',
              metadata: {
                'legacy_import_id': importId,
                'source_type': sourceType,
                ...backendMeta,
              },
              wordCount: result['metadata']?['word_count'] as int?,
              lessonCount: result['lessons'] != null
                  ? (result['lessons'] as List).length
                  : null,
            );

            // Update source data with backend-processed content info
            try {
              final backendSourceData = SourceData(
                rawText: (result['raw_text'] as String?) ?? rawText,
                transcriptJson: result['transcript_json'] as String?,
                sourceUrl: sourceUrl,
                sourceType: sourceType,
                wordCount: result['metadata']?['word_count'] as int?,
              );
              await _userContentRef
                  .doc(userContentId)
                  .collection('source')
                  .doc('raw')
                  .set(
                    backendSourceData.toFirestore(),
                    SetOptions(merge: true),
                  )
                  .timeout(const Duration(seconds: 10));
            } catch (e) {
              Logger.warn(
                'Failed to update source data after backend processing: $e',
              );
            }

            success = true;
            Logger.info(
              'Successfully connected to backend via Multipart at $url',
            );
          } else {
            // Backend processed but returned a failure — mark failed, no mock lessons.
            Logger.error('Backend returned failed status: ${result['error']}');
            success = true;
            await _importsRef
                .doc(importId)
                .update({
                  'status': 'failed',
                  'error_message': result['error'] ?? 'Processing failed',
                  'last_updated': FieldValue.serverTimestamp(),
                })
                .timeout(const Duration(seconds: 10));
            // Also mark user_content as failed
            await _updateUserContentEntry(
              userContentId,
              status: 'failed',
              metadata: {
                'legacy_import_id': importId,
                'backend_error': result['error'] ?? 'Processing failed',
              },
            );
          }
        } else {
          Logger.error(
            'Backend Error: ${response.statusCode} - ${response.body}',
          );
          try {
            final errorBody = jsonDecode(response.body);
            lastError =
                errorBody['message'] ?? errorBody['detail'] ?? response.body;
          } catch (_) {
            lastError = response.body;
          }
          // Break on 500 — server processing failure won't resolve with retry.
          if (response.statusCode >= 500) break;
        }
      } catch (e) {
        Logger.warn('Failed to connect to $url: $e');
        lastError = e.toString();
      }
    }

    if (!success) {
      Logger.error('All backend connection attempts failed.');
      await _importsRef.doc(importId).delete().timeout(const Duration(seconds: 10));
      // Mark user_content as failed when we can't reach the backend
      await _updateUserContentEntry(
        userContentId,
        status: 'failed',
        metadata: {'legacy_import_id': importId, 'error': lastError},
      );
      throw Exception(
        lastError.isNotEmpty ? lastError : 'Could not reach the import server',
      );
    }
  }

  /// Fetch a transcript for a specific video and language from the Content Service.
  /// Uses youtube_transcript_api on the server (more reliable than youtube_explode_dart).
  /// Returns null on failure.
  /// Fetch a transcript for a specific video and language from the Content Service.
  /// Uses youtube_transcript_api on the server (more reliable than youtube_explode_dart).
  ///
  /// Throws [RateLimitException] if the backend returns 429 (too many requests).
  /// Returns null on other failures.
  Future<Map<String, dynamic>?> fetchTranscriptFromBackend({
    required String videoId,
    String? languageCode,
  }) async {
    final List<String> baseUrls = [ApiConfig.getRecommendationsBaseUrl()];

    for (final baseUrl in baseUrls) {
      try {
        final uri = Uri.parse('$baseUrl/transcript').replace(
          queryParameters: {
            'video_id': videoId,
            if (languageCode != null) 'lang': languageCode,
          },
        );
        Logger.info('Fetching transcript from backend: $uri');
        final response = await http
            .get(uri)
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 429) {
          // Rate limit hit — throw so callers can show a dialog
          String message =
              'Too many transcript requests. Please try again later.';
          try {
            final body = jsonDecode(response.body);
            final detail = body['detail'];
            if (detail is Map) {
              message = detail['message'] ?? message;
            } else if (detail is String) {
              message = detail;
            }
          } catch (e) {
            Logger.warn('Failed to parse rate-limit error detail: $e');
          }
          throw RateLimitException(message);
        }

        if (response.statusCode == 200) {
          return jsonDecode(response.body) as Map<String, dynamic>;
        }
        Logger.warn(
          'Backend transcript fetch returned ${response.statusCode}: ${response.body}',
        );
      } on RateLimitException {
        // Re-throw rate limit — don't retry other URLs
        rethrow;
      } catch (e) {
        Logger.warn('Backend transcript fetch failed for $baseUrl: $e');
      }
    }
    return null;
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (log(bytes) / log(1024)).floor();
    var size = bytes / pow(1024, i);
    return "${size.toStringAsFixed(1)} ${suffixes[i]}";
  }
}
