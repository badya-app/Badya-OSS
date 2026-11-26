import 'package:Badya/services/content_service.dart';
import 'package:Badya/config/content_types.dart';
import 'package:Badya/models/source_data.dart';
import 'package:Badya/models/user_content.dart';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ContentService', () {
    late FakeFirebaseFirestore fakeFirestore;
    late ContentService contentService;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      contentService = ContentService(firestore: fakeFirestore);
    });

    // ─── addContent ────────────────────────────────────────────────────

    test('addContent creates a document in user_content collection', () async {
      final id = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'Test Content',
        description: 'A test description',
      );

      final doc = await fakeFirestore.collection('user_content').doc(id).get();
      expect(doc.exists, true);
      expect(doc.data()!['title'], 'Test Content');
      expect(doc.data()!['type'], 'text');
      expect(doc.data()!['user_id'], 'user_1');
      expect(doc.data()!['description'], 'A test description');
    });

    test('addContent stores tags and language', () async {
      final id = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.youtube,
        title: 'Video',
        tags: ['flutter', 'tutorial'],
        language: 'English',
        assignedLanguages: ['English'],
      );

      final doc = await fakeFirestore.collection('user_content').doc(id).get();
      expect(doc.data()!['tags'], ['flutter', 'tutorial']);
      expect(doc.data()!['language'], 'English');
      expect(doc.data()!['assigned_languages'], ['English']);
    });

    test('addContent stores AI prompt when provided', () async {
      final id = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.aiGenerated,
        title: 'AI Lesson',
        aiPrompt: 'Create a lesson on Spanish greetings',
      );

      final doc = await fakeFirestore.collection('user_content').doc(id).get();
      expect(doc.data()!['ai_prompt'], 'Create a lesson on Spanish greetings');
    });

    test('addContent stores custom status', () async {
      final id = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.document,
        title: 'Processing Doc',
        status: ContentStatus.processing,
      );

      final doc = await fakeFirestore.collection('user_content').doc(id).get();
      expect(doc.data()!['status'], 'processing');
    });

    // ─── getContent ────────────────────────────────────────────────────

    test('getContent returns null for non-existent content', () async {
      final result = await contentService.getContent('nonexistent_id');
      expect(result, isNull);
    });

    test('getContent returns UserContent for existing content', () async {
      final id = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'Findable',
      );

      final result = await contentService.getContent(id);
      expect(result, isNotNull);
      expect(result!.title, 'Findable');
      expect(result.id, id);
    });

    // ─── updateContent ─────────────────────────────────────────────────

    test('updateContent updates title', () async {
      final id = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'Original',
      );

      await contentService.updateContent(id, title: 'Updated');

      final doc = await fakeFirestore.collection('user_content').doc(id).get();
      expect(doc.data()!['title'], 'Updated');
    });

    test('updateContent updates multiple fields', () async {
      final id = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'Original',
        tags: ['old'],
        isPublic: false,
      );

      await contentService.updateContent(
        id,
        title: 'Updated',
        tags: ['new'],
        isPublic: true,
      );

      final doc = await fakeFirestore.collection('user_content').doc(id).get();
      expect(doc.data()!['title'], 'Updated');
      expect(doc.data()!['tags'], ['new']);
      expect(doc.data()!['is_public'], true);
    });

    // ─── deleteContent ─────────────────────────────────────────────────

    test('deleteContent removes document', () async {
      final id = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'To Delete',
      );

      await contentService.deleteContent(id);

      final doc = await fakeFirestore.collection('user_content').doc(id).get();
      expect(doc.exists, false);
    });

    // ─── getUserContent stream ─────────────────────────────────────────

    test('getUserContent streams all content when no filters', () async {
      await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'Item 1',
      );
      await contentService.addContent(
        userId: 'user_2',
        type: ContentType.youtube,
        title: 'Item 2',
      );

      final stream = contentService.getUserContent();
      final items = await stream.first;

      expect(items.length, 2);
    });

    test('getUserContent filters by userId', () async {
      await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'Mine',
      );
      await contentService.addContent(
        userId: 'user_2',
        type: ContentType.youtube,
        title: 'Not Mine',
      );

      final stream = contentService.getUserContent(userId: 'user_1');
      final items = await stream.first;

      expect(items.length, 1);
      expect(items.first.title, 'Mine');
    });

    test('getUserContent filters by type', () async {
      await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'Text',
      );
      await contentService.addContent(
        userId: 'user_1',
        type: ContentType.youtube,
        title: 'Video',
      );

      final stream = contentService.getUserContent(type: ContentType.youtube);
      final items = await stream.first;

      expect(items.length, 1);
      expect(items.first.title, 'Video');
    });

    // ─── getMyContent ──────────────────────────────────────────────────

    test('getMyContent returns only the user content', () async {
      await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'Mine',
      );
      await contentService.addContent(
        userId: 'user_2',
        type: ContentType.text,
        title: 'Other',
      );

      final stream = contentService.getMyContent(userId: 'user_1');
      final items = await stream.first;

      expect(items.length, 1);
      expect(items.first.title, 'Mine');
    });

    test('getMyContent filters by language', () async {
      await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'English Item',
        language: 'English',
      );
      await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'Spanish Item',
        language: 'Spanish',
      );

      final stream = contentService.getMyContent(
        userId: 'user_1',
        language: 'Spanish',
      );
      final items = await stream.first;

      expect(items.length, 1);
      expect(items.first.title, 'Spanish Item');
    });

    // ─── addContent as import ─────────────────────────────────────────
    // Note: createImport was moved to ImportService. These tests verify
    // that ContentService.addContent can create import-style entries.

    test('addContent creates a processing import-style entry', () async {
      final id = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.youtube,
        title: 'My YouTube Import',
        source: ContentSource.import,
        status: ContentStatus.processing,
      );

      final doc = await fakeFirestore.collection('user_content').doc(id).get();
      expect(doc.data()!['title'], 'My YouTube Import');
      expect(doc.data()!['source'], 'import');
      expect(doc.data()!['status'], 'processing');
    });

    test('addContent stores empty title as-is (ImportService handles defaults)',
        () async {
      final id = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.document,
        title: '',
        source: ContentSource.import,
        status: ContentStatus.processing,
      );

      final doc = await fakeFirestore.collection('user_content').doc(id).get();
      // ContentService.addContent stores the title verbatim;
      // the "Processing..." default is handled by ImportService.createImport.
      expect(doc.data()!['title'], '');
    });

    // ─── updateImportStatus ────────────────────────────────────────────

    test('updateImportStatus changes status from processing to ready',
        () async {
      final id = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.youtube,
        title: 'Import',
        source: ContentSource.import,
        status: ContentStatus.processing,
      );

      await contentService.updateImportStatus(id, ContentStatus.ready);

      final doc = await fakeFirestore.collection('user_content').doc(id).get();
      expect(doc.data()!['status'], 'ready');
    });

    // ─── addSuggestionToUser ───────────────────────────────────────────

    test('addSuggestionToUser creates a forked copy', () async {
      // Create public content
      final suggestionId = await contentService.addContent(
        userId: 'system',
        type: ContentType.text,
        title: 'Public Content',
        tags: ['spanish', 'beginner'],
        language: 'Spanish',
        isPublic: true,
      );

      // Fork to user
      final forkedId = await contentService.addSuggestionToUser(
        userId: 'user_1',
        suggestionId: suggestionId,
      );

      expect(forkedId, isNotNull);
      expect(forkedId, isNot(suggestionId));

      final doc =
          await fakeFirestore.collection('user_content').doc(forkedId!).get();
      expect(doc.data()!['user_id'], 'user_1');
      expect(doc.data()!['canonical_content_id'], suggestionId);
      expect(doc.data()!['origin_type'], 'forked');
      expect(doc.data()!['is_public'], false);
    });

    test('addSuggestionToUser merges additional tags', () async {
      final suggestionId = await contentService.addContent(
        userId: 'system',
        type: ContentType.text,
        title: 'Public Content',
        tags: ['spanish', 'beginner'],
        isPublic: true,
      );

      final forkedId = await contentService.addSuggestionToUser(
        userId: 'user_1',
        suggestionId: suggestionId,
        additionalTags: ['my_tag', 'beginner'], // 'beginner' is duplicate
      );

      final doc =
          await fakeFirestore.collection('user_content').doc(forkedId!).get();
      expect(doc.data()!['tags'], ['spanish', 'beginner', 'my_tag']);
    });

    test('addSuggestionToUser returns null for non-existent content',
        () async {
      final result = await contentService.addSuggestionToUser(
        userId: 'user_1',
        suggestionId: 'nonexistent',
      );

      expect(result, isNull);
    });

    test(
        'addSuggestionToUser preserves segmentation preferences '
        '(segment_by, segment_value, lesson_count)', () async {
      final suggestionId = await contentService.addContent(
        userId: 'system',
        type: ContentType.youtube,
        title: 'Segmented Video',
        isPublic: true,
        lessonCount: 4,
        segmentBy: 'minutes',
        segmentValue: 8,
      );

      final forkedId = await contentService.addSuggestionToUser(
        userId: 'user_1',
        suggestionId: suggestionId,
      );

      expect(forkedId, isNotNull);

      final doc =
          await fakeFirestore.collection('user_content').doc(forkedId!).get();
      expect(doc.data()!['segment_by'], 'minutes',
          reason: 'Fork must inherit segment_by from the original');
      expect(doc.data()!['segment_value'], 8,
          reason: 'Fork must inherit segment_value from the original');
      expect(doc.data()!['lesson_count'], 4,
          reason: 'Fork must inherit lesson_count from the original');
    });

    test('addSuggestionToUser copies source/raw from canonical content to fork',
        () async {
      final suggestionId = await contentService.addContent(
        userId: 'system',
        type: ContentType.text,
        title: 'Imported Article',
        isPublic: true,
      );

      await contentService.writeSourceData(
        contentId: suggestionId,
        sourceData: SourceData(
          rawText: '# Chapter 1\n${'Original source text. ' * 40}',
          sourceType: 'text',
          wordCount: 40,
        ),
      );

      final forkedId = await contentService.addSuggestionToUser(
        userId: 'user_1',
        suggestionId: suggestionId,
      );

      expect(forkedId, isNotNull);

      final forkSource = await contentService.getSourceData(forkedId!);
      expect(forkSource, isNotNull,
          reason: 'Fork must own an independent copy of source/raw');
      expect(
        forkSource!.rawText,
        '# Chapter 1\n${'Original source text. ' * 40}',
      );
      expect(forkSource.sourceType, 'text');
      expect(forkSource.wordCount, 40);
    });

    test('forked imported content produces identical virtual segments to canonical',
        () async {
      final rawText = '# Chapter 1\n'
          '${'First chapter body with enough text to form a real section. ' * 20}'
          '\n\n# Chapter 2\n'
          '${'Second chapter body with enough text to form a real section. ' * 20}';

      final suggestionId = await contentService.addContent(
        userId: 'system',
        type: ContentType.text,
        title: 'Canonical Article',
        isPublic: true,
        lessonCount: 2,
        segmentBy: 'chapters',
      );

      await contentService.writeSourceData(
        contentId: suggestionId,
        sourceData: SourceData(rawText: rawText, sourceType: 'text'),
      );

      final forkedId = await contentService.addSuggestionToUser(
        userId: 'user_1',
        suggestionId: suggestionId,
      );
      expect(forkedId, isNotNull);

      final canonicalSegments =
          await contentService.getContentSegmentsOnce(suggestionId);
      final forkSegments = await contentService.getContentSegmentsOnce(forkedId!);

      expect(canonicalSegments, isNotEmpty);
      expect(forkSegments.length, canonicalSegments.length,
          reason: 'Fork must segment identically to the canonical content');
      for (var i = 0; i < canonicalSegments.length; i++) {
        expect(forkSegments[i]['title'], canonicalSegments[i]['title']);
        expect(
          forkSegments[i]['text_content'],
          canonicalSegments[i]['text_content'],
        );
        expect(forkSegments[i]['order_index'],
            canonicalSegments[i]['order_index']);
      }
    });

    test('updateSegmentationPreference updates lesson_count on document',
        () async {
      final contentId = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'Counted Segments',
      );

      final sourceData = SourceData(
        rawText: '# First Chapter\n'
            '${'Content for the first chapter with enough words to be a section. ' * 20}'
            '\n\n# Second Chapter\n'
            '${'Content for the second chapter with enough words to be a section. ' * 20}',
        sourceType: 'text',
      );
      await contentService.writeSourceData(
        contentId: contentId,
        sourceData: sourceData,
      );

      await contentService.updateSegmentationPreference(
        contentId: contentId,
        segmentBy: 'chapters',
      );

      final segments = await contentService.getContentSegmentsOnce(contentId);
      expect(segments, isNotEmpty,
          reason: 'Source data must produce at least one segment');

      final doc =
          await fakeFirestore.collection('user_content').doc(contentId).get();
      expect(doc.data()!['segment_by'], 'chapters');
      expect(doc.data()!['lesson_count'], segments.length,
          reason: 'lesson_count must reflect the recomputed segment count');
    });

    // ─── updateProgress ────────────────────────────────────────────────

    test('updateProgress stores progress in content and user progress',
        () async {
      final contentId = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'Progressive Lesson',
      );

      await contentService.updateProgress('user_1', contentId, 0.75);

      // Check content document
      final contentDoc =
          await fakeFirestore.collection('user_content').doc(contentId).get();
      expect(contentDoc.data()!['progress'], 0.75);

      // Check user progress collection
      final progressDoc = await fakeFirestore
          .collection('users')
          .doc('user_1')
          .collection('progress')
          .doc(contentId)
          .get();
      expect(progressDoc.exists, true);
      expect(progressDoc.data()!['topic_score'], 75);
    });

    // ─── getProgress stream ────────────────────────────────────────────

    test('getProgress streams progress map for user', () async {
      await fakeFirestore
          .collection('users')
          .doc('user_1')
          .collection('progress')
          .doc('content_a')
          .set({'id': 'content_a', 'topic_score': 50});
      await fakeFirestore
          .collection('users')
          .doc('user_1')
          .collection('progress')
          .doc('content_b')
          .set({'id': 'content_b', 'topic_score': 100});

      final stream = contentService.getProgress('user_1');
      final progress = await stream.first;

      expect(progress['content_a'], 0.5);
      expect(progress['content_b'], 1.0);
    });

    // ─── assignLanguages ───────────────────────────────────────────────

    test('assignLanguages updates assigned_languages field', () async {
      final id = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'Multilingual Content',
      );

      await contentService.assignLanguages(id, ['English', 'Spanish']);

      final doc = await fakeFirestore.collection('user_content').doc(id).get();
      expect(doc.data()!['assigned_languages'], ['English', 'Spanish']);
    });

    // ─── getPublicFeed ────────────────────────────────────────────────

    test('getPublicFeed returns public content filtered by language for non-AI',
        () async {
      await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'English Text',
        language: 'English',
        assignedLanguages: ['English'],
        isPublic: true,
      );
      await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'Spanish Text (hidden)',
        language: 'Spanish',
        assignedLanguages: ['Spanish'],
        isPublic: true,
      );

      final stream = contentService.getPublicFeed(language: 'English');
      final items = await stream.first;

      expect(items.length, 1);
      expect(items.first.title, 'English Text');
    });

    test('getPublicFeed includes AI content across all languages', () async {
      await contentService.addContent(
        userId: 'user_1',
        type: ContentType.aiGenerated,
        title: 'AI Spanish Topic',
        language: 'Spanish',
        assignedLanguages: ['Spanish'],
        isPublic: true,
      );
      await contentService.addContent(
        userId: 'user_1',
        type: ContentType.aiGenerated,
        title: 'AI French Topic',
        language: 'French',
        assignedLanguages: ['French'],
        isPublic: true,
      );
      await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'English Import',
        language: 'English',
        assignedLanguages: ['English'],
        isPublic: true,
      );

      // When filtering by English, should see:
      // - English Import (non-AI, language matches)
      // - Both AI topics (multilingual — shown regardless of language)
      final stream = contentService.getPublicFeed(language: 'English');
      final items = await stream.first;

      expect(items.length, 3);
      expect(items.any((c) => c.title == 'English Import'), true);
      expect(items.any((c) => c.title == 'AI Spanish Topic'), true);
      expect(items.any((c) => c.title == 'AI French Topic'), true);
    });

    test('getPublicFeed deduplicates AI content with matching assigned_languages',
        () async {
      // AI content that also has English in assigned_languages
      // Should only appear once in the merged result
      await contentService.addContent(
        userId: 'user_1',
        type: ContentType.aiGenerated,
        title: 'Duplicated AI',
        language: 'English',
        assignedLanguages: ['English', 'Spanish'],
        isPublic: true,
      );

      final stream = contentService.getPublicFeed(language: 'English');
      final items = await stream.first;

      expect(items.length, 1);
      expect(items.first.title, 'Duplicated AI');
    });

    test('getPublicFeed with type filter uses single query', () async {
      await contentService.addContent(
        userId: 'user_1',
        type: ContentType.aiGenerated,
        title: 'AI Topic',
        language: 'Spanish',
        assignedLanguages: ['Spanish'],
        isPublic: true,
      );
      await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'Text Topic',
        language: 'Spanish',
        assignedLanguages: ['Spanish'],
        isPublic: true,
      );

      // When type is specified, AI content IS filtered by language
      final stream =
          contentService.getPublicFeed(language: 'English', type: ContentType.aiGenerated);
      final items = await stream.first;

      expect(items, isEmpty);
    });

    test('getPublicFeed sorts merged results by created_at descending',
        () async {
      await contentService.addContent(
        userId: 'user_1',
        type: ContentType.aiGenerated,
        title: 'Older AI',
        language: 'English',
        assignedLanguages: ['English'],
        isPublic: true,
      );
      // Small delay to ensure different timestamps
      await Future.delayed(const Duration(milliseconds: 10));
      await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'Newer Import',
        language: 'English',
        assignedLanguages: ['English'],
        isPublic: true,
      );

      final stream = contentService.getPublicFeed(language: 'English');
      final items = await stream.first;

      expect(items.length, 2);
      expect(items[0].title, 'Newer Import');
      expect(items[1].title, 'Older AI');
    });

    // ─── toggleVisibility ──────────────────────────────────────────────

    test('toggleVisibility makes content public', () async {
      final id = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'Private',
        isPublic: false,
      );

      await contentService.toggleVisibility(id, true);

      final doc = await fakeFirestore.collection('user_content').doc(id).get();
      expect(doc.data()!['is_public'], true);
    });

    test('toggleVisibility makes content private', () async {
      final id = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'Public',
        isPublic: true,
      );

      await contentService.toggleVisibility(id, false);

      final doc = await fakeFirestore.collection('user_content').doc(id).get();
      expect(doc.data()!['is_public'], false);
    });

    // ─── markAsOpened ──────────────────────────────────────────────────

    test('markAsOpened updates last_opened_at', () async {
      final id = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'Open Me',
      );

      await contentService.markAsOpened(id);

      final doc = await fakeFirestore.collection('user_content').doc(id).get();
      expect(doc.data()!.containsKey('last_opened_at'), true);
    });

    // ─── getAllTagsWithCounts ──────────────────────────────────────────

    test('getAllTagsWithCounts returns sorted tags by frequency', () async {
      // content_1: ['flutter', 'dart']
      await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'C1',
        tags: ['Flutter', 'Dart'],
      );
      // content_2: ['tutorial']
      await contentService.addContent(
        userId: 'user_2',
        type: ContentType.youtube,
        title: 'C2',
        tags: ['Tutorial'],
      );
      // content_3: ['dart', 'tutorial']
      await contentService.addContent(
        userId: 'user_2',
        type: ContentType.text,
        title: 'C3',
        tags: ['Dart', 'Tutorial'],
      );

      final tags = await contentService.getAllTagsWithCounts();

      // 'dart' appears 2 times (C1 + C3)
      // 'tutorial' appears 2 times (C2 + C3)
      // 'flutter' appears 1 time
      expect(tags.length, 3);
      // Both 'dart' and 'tutorial' have count 2; 'flutter' has 1
      expect(tags[0].value, 2);
      expect(tags[1].value, 2);
      expect(tags[2].value, 1);
    });

    test('getAllTagsWithCounts returns empty list when no tags', () async {
      await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'No Tags',
        tags: [],
      );

      final tags = await contentService.getAllTagsWithCounts();
      expect(tags, isEmpty);
    });

    // ─── UserContent.fromFirestore ─────────────────────────────────────

    test('UserContent.fromFirestore parses document correctly', () async {
      final id = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.aiGenerated,
        title: 'AI Lesson',
        description: 'A great lesson',
        tags: ['ai', 'spanish'],
        language: 'Spanish',
        wordCount: 500,
        lessonCount: 3,
      );

      final doc = await fakeFirestore.collection('user_content').doc(id).get();
      final content = UserContent.fromFirestore(doc);

      expect(content.type, ContentType.aiGenerated);
      expect(content.title, 'AI Lesson');
      expect(content.description, 'A great lesson');
      expect(content.tags, ['ai', 'spanish']);
      expect(content.language, 'Spanish');
      expect(content.wordCount, 500);
      expect(content.lessonCount, 3);
    });

    // ─── UserContent.toFirestore ───────────────────────────────────────

    // ─── updateSegmentationPreference ─────────────────────────────────

    test('updateSegmentationPreference sets segment_by on user_content doc',
        () async {
      final id = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'Segmented',
      );

      await contentService.updateSegmentationPreference(
        contentId: id,
        segmentBy: 'words',
        segmentValue: 500,
      );

      final doc = await fakeFirestore.collection('user_content').doc(id).get();
      expect(doc.data()!['segment_by'], 'words');
      expect(doc.data()!['segment_value'], 500);
    });

    test('updateSegmentationPreference omits segment_value when null',
        () async {
      final id = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'Segmented',
      );

      await contentService.updateSegmentationPreference(
        contentId: id,
        segmentBy: 'none',
      );

      final doc = await fakeFirestore.collection('user_content').doc(id).get();
      expect(doc.data()!['segment_by'], 'none');
      expect(doc.data()!.containsKey('segment_value'), false);
    });

    // ─── Source Data CRUD ──────────────────────────────────────────────

    test('writeSourceData and getSourceData round-trip', () async {
      final contentId = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'Source Data Test',
      );

      final sourceData = SourceData(
        rawText: 'Hello world',
        sourceType: 'text',
        sourceUrl: null,
        wordCount: 2,
        characterCount: 11,
      );

      await contentService.writeSourceData(
        contentId: contentId,
        sourceData: sourceData,
      );

      final fetched = await contentService.getSourceData(contentId);
      expect(fetched, isNotNull);
      expect(fetched!.rawText, 'Hello world');
      expect(fetched.sourceType, 'text');
      expect(fetched.wordCount, 2);
    });

    test('getSourceData returns null for non-existent source data', () async {
      final result =
          await contentService.getSourceData('nonexistent_content');
      expect(result, isNull);
    });

    test('writeSourceData merges with existing data', () async {
      final contentId = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.youtube,
        title: 'Merge Test',
      );

      // Write initial source data
      final initialData = SourceData(
        rawText: 'Initial',
        sourceType: 'youtube',
        wordCount: 500,
        characterCount: 2500,
      );
      await contentService.writeSourceData(
        contentId: contentId,
        sourceData: initialData,
      );

      // Merge with new data (should keep existing fields not overwritten)
      final mergedData = SourceData(
        sourceType: 'youtube',
      );
      await contentService.writeSourceData(
        contentId: contentId,
        sourceData: mergedData,
      );

      final fetched = await contentService.getSourceData(contentId);
      expect(fetched, isNotNull);
      // These should survive the merge (not overwritten by the second write)
      expect(fetched!.wordCount, 500);
      expect(fetched.characterCount, 2500);
    });

    test('deleteSourceData removes source subcollection document', () async {
      final contentId = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'Delete Source',
      );

      final sourceData = SourceData(rawText: 'Data', sourceType: 'text');
      await contentService.writeSourceData(
        contentId: contentId,
        sourceData: sourceData,
      );

      // Verify it exists
      var fetched = await contentService.getSourceData(contentId);
      expect(fetched, isNotNull);

      await contentService.deleteSourceData(contentId);

      // Verify it's gone
      fetched = await contentService.getSourceData(contentId);
      expect(fetched, isNull);
    });

    // ─── Lesson Progress Subcollection ─────────────────────────────────

    test('getLessonProgress returns empty map when no progress exists',
        () async {
      final contentId = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'No Progress Yet',
      );

      final progress = await contentService.getLessonProgress(contentId);
      expect(progress, isEmpty);
    });

    test('updateLessonProgress creates a progress document', () async {
      final contentId = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'Progress Test',
      );

      await contentService.updateLessonProgress(
        contentId: contentId,
        orderIndex: 0,
        position: 0.5,
      );

      final progress = await contentService.getLessonProgress(contentId);
      expect(progress.length, 1);
      expect(progress[0]!['last_position'], 0.5);
      expect(progress[0]!['order_index'], 0);
      expect(progress[0]!['completed'], false);
    });

    test('updateLessonProgress marks completed when position >= 0.99',
        () async {
      final contentId = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'Complete Test',
      );

      await contentService.updateLessonProgress(
        contentId: contentId,
        orderIndex: 0,
        position: 1.0,
      );

      final progress = await contentService.getLessonProgress(contentId);
      expect(progress[0]!['completed'], true);
    });

    test('updateLessonProgress is forward-only (no regressions)', () async {
      final contentId = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'Forward Only',
      );

      // Write position 0.8
      await contentService.updateLessonProgress(
        contentId: contentId,
        orderIndex: 0,
        position: 0.8,
      );

      // Try to write a lower position — should NOT regress
      await contentService.updateLessonProgress(
        contentId: contentId,
        orderIndex: 0,
        position: 0.3,
      );

      final progress = await contentService.getLessonProgress(contentId);
      expect(progress[0]!['last_position'], 0.8);
    });

    test('updateLessonProgress tracks multiple segments independently',
        () async {
      final contentId = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.youtube,
        title: 'Multi Segment',
      );

      await contentService.updateLessonProgress(
        contentId: contentId,
        orderIndex: 0,
        position: 0.9,
      );
      await contentService.updateLessonProgress(
        contentId: contentId,
        orderIndex: 1,
        position: 0.4,
      );
      await contentService.updateLessonProgress(
        contentId: contentId,
        orderIndex: 2,
        position: 0.0,
      );

      final progress = await contentService.getLessonProgress(contentId);
      expect(progress.length, 3);
      expect(progress[0]!['last_position'], 0.9);
      expect(progress[1]!['last_position'], 0.4);
      // When position is 0 and no previous value, it should be saved
      expect(progress[2]!['last_position'], 0.0);
    });

    // ─── getContentSegmentsOnce with virtual segments ──────────────────

    test('getContentSegmentsOnce returns empty when no source data',
        () async {
      final contentId = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'No Source',
      );

      final segments =
          await contentService.getContentSegmentsOnce(contentId);
      expect(segments, isEmpty);
    });

    test('getContentSegmentsOnce returns virtual segments from source data',
        () async {
      final contentId = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'Virtual Segments',
      );

      // Write source data so virtual segmentation can work.
      // Use structural sections (markdown headings) to guarantee segmentation.
      final sourceData = SourceData(
        rawText: '# Chapter 1\n' +
            'First paragraph with enough text to make a real section. ' * 30 +
            '\n\n# Chapter 2\n' +
            'Second paragraph with enough content to form a separate section. ' * 30,
        sourceType: 'text',
      );
      await contentService.writeSourceData(
        contentId: contentId,
        sourceData: sourceData,
      );

      // Set segmentation preference to chapters (structural sections for text)
      await contentService.updateSegmentationPreference(
        contentId: contentId,
        segmentBy: 'chapters',
      );

      final segments =
          await contentService.getContentSegmentsOnce(contentId);
      expect(segments.length, greaterThanOrEqualTo(1));
      expect(segments.first['order_index'], 0);
      expect(segments.first['title'], isNotEmpty);
      expect(segments.first['text_content'], isNotEmpty);
    });

    test('getContentSegmentsOnce merges progress into virtual segments',
        () async {
      final contentId = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'Progress Merge',
      );

      // Write source data with structural headings
      final sourceData = SourceData(
        rawText: '# First Chapter\n' +
            'Content for the first chapter with enough words to be its own section. ' * 20 +
            '\n\n# Second Chapter\n' +
            'Content for the second chapter with enough words to be its own section. ' * 20,
        sourceType: 'text',
      );
      await contentService.writeSourceData(
        contentId: contentId,
        sourceData: sourceData,
      );

      await contentService.updateSegmentationPreference(
        contentId: contentId,
        segmentBy: 'chapters',
      );

      // Write progress for the first segment
      await contentService.updateLessonProgress(
        contentId: contentId,
        orderIndex: 0,
        position: 1.0,
      );

      final segments =
          await contentService.getContentSegmentsOnce(contentId);
      expect(segments.length, greaterThanOrEqualTo(1));

      // The first segment should have last_position = 1.0 merged in
      final firstSegment = segments.firstWhere(
        (s) => (s['order_index'] as int) == 0,
      );
      expect(firstSegment['last_position'], 1.0);
    });

    // ─── clearLegacySegments ───────────────────────────────────────────

    test('clearLegacySegments deletes segments subcollection', () async {
      final contentId = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'Legacy Segments',
      );

      // Manually write a legacy segment doc
      await fakeFirestore
          .collection('user_content')
          .doc(contentId)
          .collection('segments')
          .doc('seg_1')
          .set({'title': 'Old Segment', 'order_index': 0});

      // Verify it exists
      var snapshot = await fakeFirestore
          .collection('user_content')
          .doc(contentId)
          .collection('segments')
          .get();
      expect(snapshot.docs.length, 1);

      await contentService.clearLegacySegments(contentId);

      // Verify it's gone
      snapshot = await fakeFirestore
          .collection('user_content')
          .doc(contentId)
          .collection('segments')
          .get();
      expect(snapshot.docs.length, 0);
    });

    test('clearLegacySegments does nothing when no segments exist', () async {
      final contentId = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'Empty Segments',
      );

      // Should not throw
      await contentService.clearLegacySegments(contentId);

      final snapshot = await fakeFirestore
          .collection('user_content')
          .doc(contentId)
          .collection('segments')
          .get();
      expect(snapshot.docs.length, 0);
    });

    // ─── deleteContent cascading ───────────────────────────────────────

    test('deleteContent deletes source/raw subcollection', () async {
      final contentId = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'Cascade Delete',
      );

      // Write source data
      final sourceData = SourceData(rawText: 'Data to delete', sourceType: 'text');
      await contentService.writeSourceData(
        contentId: contentId,
        sourceData: sourceData,
      );

      // Verify source data exists
      var source = await contentService.getSourceData(contentId);
      expect(source, isNotNull);

      // Delete content
      await contentService.deleteContent(contentId);

      // Verify source data is also gone
      source = await contentService.getSourceData(contentId);
      expect(source, isNull);

      // Verify the document itself is gone
      final doc =
          await fakeFirestore.collection('user_content').doc(contentId).get();
      expect(doc.exists, false);
    });

    test('deleteContent removes progress subcollection', () async {
      final contentId = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'Progress Cascade',
      );

      // Write some lesson progress
      await contentService.updateLessonProgress(
        contentId: contentId,
        orderIndex: 0,
        position: 0.5,
      );

      // Delete content
      await contentService.deleteContent(contentId);

      // Verify progress is gone
      final progress = await contentService.getLessonProgress(contentId);
      expect(progress, isEmpty);
    });

    // ─── addSuggestionToUser with fork resolution ──────────────────────

    test('addSuggestionToUser creates forked copy with canonical_content_id',
        () async {
      final originalId = await contentService.addContent(
        userId: 'system',
        type: ContentType.text,
        title: 'Original',
        isPublic: true,
      );

      final forkedId = await contentService.addSuggestionToUser(
        userId: 'user_1',
        suggestionId: originalId,
      );

      expect(forkedId, isNotNull);

      final doc =
          await fakeFirestore.collection('user_content').doc(forkedId!).get();
      expect(doc.data()!['canonical_content_id'], originalId);
      expect(doc.data()!['origin_type'], 'forked');
      expect(doc.data()!['user_id'], 'user_1');
      expect(doc.data()!['is_public'], false);
      expect(doc.data()!['source'], 'suggestion');
    });

    test('addSuggestionToUser preserves original metadata', () async {
      final originalId = await contentService.addContent(
        userId: 'system',
        type: ContentType.youtube,
        title: 'Video Original',
        isPublic: true,
        metadata: {
          'duration': '10:00',
          'thumbnail': 'https://example.com/thumb.jpg',
        },
      );

      final forkedId = await contentService.addSuggestionToUser(
        userId: 'user_1',
        suggestionId: originalId,
      );

      final doc =
          await fakeFirestore.collection('user_content').doc(forkedId!).get();
      final metadata = doc.data()!['metadata'] as Map<String, dynamic>;
      expect(metadata['duration'], '10:00');
      expect(metadata['thumbnail'], 'https://example.com/thumb.jpg');
    });

    // ─── UserContent round-trip ────────────────────────────────────────

    test('UserContent round-trip preserves all fields', () async {
      final id = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.youtube,
        title: 'YouTube Video',
        description: 'A video description',
        tags: ['flutter', 'tutorial'],
        language: 'English',
        assignedLanguages: ['English', 'Spanish'],
        isPublic: true,
        canonicalContentId: 'original_id',
        originType: OriginType.forked,
        wordCount: 1000,
        lessonCount: 5,
        metadata: {'duration': '10:00'},
      );

      final doc = await fakeFirestore.collection('user_content').doc(id).get();
      final content = UserContent.fromFirestore(doc);

      expect(content.id, id);
      expect(content.type, ContentType.youtube);
      expect(content.title, 'YouTube Video');
      expect(content.userId, 'user_1');
      expect(content.canonicalContentId, 'original_id');
      expect(content.originType, OriginType.forked);
      expect(content.assignedLanguages, ['English', 'Spanish']);
      expect(content.metadata, {'duration': '10:00'});
    });

    // ─── Tag aggregation regression tests (Optimization 3.4 bug fixes) ──

    /// Reads the aggregated tag-counts document directly from Firestore.
    Future<Map<String, int>> readTagCounts() async {
      final doc = await fakeFirestore
          .collection('metadata')
          .doc('tag_counts')
          .get();
      final counts = doc.data()?['counts'] as Map<String, dynamic>? ?? {};
      return counts.map((k, v) => MapEntry(k, (v as num).toInt()));
    }

    test('forks do NOT inflate tag counts (Bug #1 fix)', () async {
      // Canonical content with tags — adds to counters.
      final originalId = await contentService.addContent(
        userId: 'system',
        type: ContentType.text,
        title: 'Public Topic',
        tags: ['spanish', 'beginner'],
        language: 'Spanish',
        isPublic: true,
      );

      // Baseline counts: 'spanish' = 1, 'beginner' = 1.
      var counts = await readTagCounts();
      expect(counts['spanish'], 1);
      expect(counts['beginner'], 1);

      // Fork the content 3 times. Forks must NOT change the counters.
      for (int i = 0; i < 3; i++) {
        await contentService.addSuggestionToUser(
          userId: 'user_$i',
          suggestionId: originalId,
        );
      }

      counts = await readTagCounts();
      expect(
        counts['spanish'],
        1,
        reason: 'Forks must not inflate tag counts',
      );
      expect(
        counts['beginner'],
        1,
        reason: 'Forks must not inflate tag counts',
      );
    });

    test('forks with additionalTags also do NOT inflate counters', () async {
      final originalId = await contentService.addContent(
        userId: 'system',
        type: ContentType.text,
        title: 'Topic',
        tags: ['spanish'],
        language: 'Spanish',
        isPublic: true,
      );

      await contentService.addSuggestionToUser(
        userId: 'user_1',
        suggestionId: originalId,
        additionalTags: ['my_tag'],
      );

      final counts = await readTagCounts();
      expect(counts['spanish'], 1);
      expect(
        counts['my_tag'],
        isNot(1),
        reason: "Fork's additionalTags must not increment tag counters",
      );
    });

    test('deleting a canonical content decrements its tag counts', () async {
      final id = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'To Delete',
        tags: ['dart', 'flutter'],
      );

      var counts = await readTagCounts();
      expect(counts['dart'], 1);
      expect(counts['flutter'], 1);

      await contentService.deleteContent(id);

      counts = await readTagCounts();
      expect(
        counts['dart'],
        0,
        reason: 'Deleting canonical content must decrement counters',
      );
      expect(
        counts['flutter'],
        0,
        reason: 'Deleting canonical content must decrement counters',
      );
    });

    test('deleting a fork does NOT decrement its tag counts', () async {
      // Create canonical content with tags.
      final originalId = await contentService.addContent(
        userId: 'system',
        type: ContentType.text,
        title: 'Canonical',
        tags: ['spanish'],
        isPublic: true,
      );

      // Fork it.
      final forkedId = await contentService.addSuggestionToUser(
        userId: 'user_1',
        suggestionId: originalId,
      );

      var counts = await readTagCounts();
      expect(counts['spanish'], 1);

      // Delete the fork. Counters must NOT change (forks never incremented).
      await contentService.deleteContent(forkedId!);

      counts = await readTagCounts();
      expect(
        counts['spanish'],
        1,
        reason: 'Deleting a fork must not decrement tag counters',
      );
    });

    test('updateContent swaps old and new tag counts (Bug #2/#3 fix)',
        () async {
      final id = await contentService.addContent(
        userId: 'user_1',
        type: ContentType.text,
        title: 'Editable',
        tags: ['old_tag', 'shared'],
      );

      var counts = await readTagCounts();
      expect(counts['old_tag'], 1);
      expect(counts['shared'], 1);

      await contentService.updateContent(
        id,
        tags: ['new_tag', 'shared'],
      );

      counts = await readTagCounts();
      expect(counts['old_tag'], 0, reason: 'Old tag must be decremented');
      expect(counts['new_tag'], 1, reason: 'New tag must be incremented');
      expect(counts['shared'], 1, reason: 'Shared tag count is unchanged');
    });
  });
}
