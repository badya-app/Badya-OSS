import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:Badya/models/source_data.dart';
import 'package:Badya/utils/content_segmenter.dart';

/// Helper: generate a string of ~N words.
String _words(int n) => List.filled(n, 'word').join(' ');

void main() {
  // ─── Sample Data ─────────────────────────────────────────────────────

  final sampleTranscript = jsonEncode([
    {'text': 'Hello and welcome', 'start': 0.0, 'duration': 2.5},
    {'text': 'to this video about', 'start': 2.5, 'duration': 2.0},
    {'text': 'learning Spanish.', 'start': 4.5, 'duration': 1.5},
    {'text': 'First we will cover', 'start': 6.0, 'duration': 2.0},
    {'text': 'basic greetings.', 'start': 8.0, 'duration': 2.0},
    {'text': 'Then we move to', 'start': 10.0, 'duration': 2.0},
    {'text': 'more advanced phrases.', 'start': 12.0, 'duration': 2.0},
    {'text': 'Finally a summary', 'start': 14.0, 'duration': 2.0},
    {'text': 'of what we learned.', 'start': 16.0, 'duration': 2.5},
  ]);

  // ─── Tests ───────────────────────────────────────────────────────────

  group('ContentSegmenter.segment()', () {
    test('dispatches to segmentAsOne for segmentBy=none', () {
      final source = SourceData(rawText: 'Hello world', sourceType: 'text');
      final result = ContentSegmenter.segment(source: source, segmentBy: 'none');
      expect(result.length, 1);
      expect(result.first.title, 'Full Content');
    });

    test('dispatches to segmentByWords for segmentBy=words', () {
      final source = SourceData(rawText: _words(300), sourceType: 'text');
      final result = ContentSegmenter.segment(source: source, segmentBy: 'words', segmentValue: 100);
      expect(result.length, greaterThan(1));
      expect(result.first.orderIndex, 0);
    });

    test('dispatches to segmentByMinutes for YouTube', () {
      final source = SourceData(
        transcriptJson: sampleTranscript,
        sourceType: 'youtube',
        sourceUrl: 'https://youtube.com/watch?v=test',
      );
      final result = ContentSegmenter.segment(source: source, segmentBy: 'minutes', segmentValue: 10);
      expect(result.length, greaterThanOrEqualTo(1));
    });

    test('falls back to word-based for non-YouTube with segmentBy=minutes', () {
      final source = SourceData(rawText: _words(300), sourceType: 'text');
      final result = ContentSegmenter.segment(source: source, segmentBy: 'minutes', segmentValue: 10);
      expect(result.length, 1);
    });

    test('dispatches to segmentByChapters for YouTube with chapters in contentData', () {
      final chapters = [
        {'start_time': 0.0, 'end_time': 6.0, 'title': 'Intro'},
        {'start_time': 6.0, 'end_time': 14.0, 'title': 'Main Topic'},
        {'start_time': 14.0, 'end_time': 18.5, 'title': 'Summary'},
      ];
      final source = SourceData(
        transcriptJson: sampleTranscript,
        sourceType: 'youtube',
        sourceUrl: 'https://youtube.com/watch?v=test',
      );
      final result = ContentSegmenter.segment(
        source: source,
        segmentBy: 'chapters',
        contentData: {'metadata': {'chapters': chapters}},
      );
      expect(result.length, 3);
      expect(result[0].title, 'Intro');
      expect(result[1].title, 'Main Topic');
      expect(result[2].title, 'Summary');
      expect(result[0].startTime, 0.0);
      expect(result[0].endTime, 6.0);
    });

    test('dispatches to segmentByChapters for text with chapters in contentData', () {
      final chapters = [
        {'level': 1, 'title': 'Introduction', 'page': 1},
        {'level': 1, 'title': 'Core Concepts', 'page': 5},
      ];
      final source = SourceData(
        rawText: '<!-- PAGE_BREAK_PAGE_1 -->\nIntro text here...\n'
            '<!-- PAGE_BREAK_PAGE_5 -->\nCore concepts here...\n',
        sourceType: 'pdf',
      );
      final result = ContentSegmenter.segment(
        source: source,
        segmentBy: 'chapters',
        contentData: {'metadata': {'chapters': chapters}},
      );
      expect(result.length, 2);
      expect(result[0].title, 'Introduction');
      expect(result[1].title, 'Core Concepts');
    });

    test('falls back to minutes for YouTube when no chapters in contentData', () {
      final source = SourceData(
        transcriptJson: sampleTranscript,
        sourceType: 'youtube',
        sourceUrl: 'https://youtube.com/watch?v=test',
      );
      final result = ContentSegmenter.segment(source: source, segmentBy: 'chapters');
      expect(result.length, greaterThanOrEqualTo(1));
    });

    test('falls back to words for text when no chapters in contentData', () {
      final result = ContentSegmenter.segment(
        source: SourceData(rawText: _words(300), sourceType: 'text'),
        segmentBy: 'chapters',
      );
      expect(result.length, 1);
      expect(result[0].title, 'Part 1');
    });

    test('throws ArgumentError for unknown segmentBy', () {
      expect(
        () => ContentSegmenter.segment(source: SourceData(rawText: 'x', sourceType: 'text'), segmentBy: 'unknown'),
        throwsArgumentError,
      );
    });
  });

  group('ContentSegmenter.segmentAsOne()', () {
    test('returns single lesson with rawText', () {
      final result = ContentSegmenter.segmentAsOne(SourceData(rawText: 'Hello world', sourceType: 'text'));
      expect(result.length, 1);
      expect(result.first.textContent, 'Hello world');
      expect(result.first.wordCount, 2);
    });

    test('flattens transcript JSON', () {
      final result = ContentSegmenter.segmentAsOne(SourceData(transcriptJson: sampleTranscript, sourceType: 'youtube'));
      expect(result.first.textContent, contains('Hello and welcome'));
      expect(result.first.textContent, contains('what we learned'));
    });

    test('returns empty when no text', () {
      final result = ContentSegmenter.segmentAsOne(SourceData(sourceType: 'text'));
      expect(result.first.textContent, '');
      expect(result.first.wordCount, 0);
    });

    test('uses contentData title', () {
      final result = ContentSegmenter.segmentAsOne(SourceData(rawText: 'Hello', sourceType: 'text'), contentData: {'title': 'Custom'});
      expect(result.first.title, 'Custom');
    });

    test('falls back to Full Content title', () {
      final result = ContentSegmenter.segmentAsOne(SourceData(rawText: 'Hello', sourceType: 'text'));
      expect(result.first.title, 'Full Content');
    });
  });

  group('ContentSegmenter.segmentByWords()', () {
    test('splits into multiple chunks', () {
      final text = List.generate(20, (i) => 'Paragraph ${i + 1}. ' * 30).join('\n\n');
      final result = ContentSegmenter.segmentByWords(SourceData(rawText: text, sourceType: 'text'), wordsPerChunk: 100);
      expect(result.length, greaterThan(1));
    });

    test('returns single chunk for small text', () {
      final result = ContentSegmenter.segmentByWords(SourceData(rawText: 'Short text.', sourceType: 'text'), wordsPerChunk: 1200);
      expect(result.length, 1);
    });

    test('throws on empty transcript', () {
      expect(() => ContentSegmenter.segmentByWords(SourceData(transcriptJson: jsonEncode([]), sourceType: 'youtube')), throwsArgumentError);
    });

    test('throws on empty text', () {
      expect(() => ContentSegmenter.segmentByWords(SourceData(rawText: '', sourceType: 'text')), throwsArgumentError);
    });

    test('throws on null text and transcript', () {
      expect(() => ContentSegmenter.segmentByWords(SourceData(sourceType: 'text')), throwsArgumentError);
    });

    test('flattens transcript JSON', () {
      final result = ContentSegmenter.segmentByWords(SourceData(transcriptJson: sampleTranscript, sourceType: 'youtube'), wordsPerChunk: 10);
      expect(result.length, greaterThanOrEqualTo(1));
      expect(result.first.textContent, isNotEmpty);
    });
  });

  group('ContentSegmenter.segmentByMinutes()', () {
    final longTranscript = jsonEncode([
      for (int i = 0; i < 60; i++)
        {'text': 'Entry $i.', 'start': i * 10.0, 'duration': 5.0, 'end': i * 10.0 + 5.0},
    ]);

    test('groups entries into intervals', () {
      final result = ContentSegmenter.segmentByMinutes(SourceData(transcriptJson: longTranscript, sourceType: 'youtube'), intervalMinutes: 10);
      expect(result.length, greaterThanOrEqualTo(1));
    });

    test('creates multiple groups for short intervals', () {
      final result = ContentSegmenter.segmentByMinutes(SourceData(transcriptJson: longTranscript, sourceType: 'youtube'), intervalMinutes: 1);
      expect(result.length, greaterThanOrEqualTo(5));
    });

    test('groups have correct timing', () {
      final result = ContentSegmenter.segmentByMinutes(SourceData(transcriptJson: longTranscript, sourceType: 'youtube'), intervalMinutes: 5);
      for (final lesson in result) {
        expect(lesson.startTime, greaterThanOrEqualTo(0));
        expect(lesson.endTime, greaterThan(lesson.startTime!));
      }
    });

    test('throws on null transcript', () {
      expect(() => ContentSegmenter.segmentByMinutes(SourceData(sourceType: 'youtube')), throwsArgumentError);
    });

    test('throws on empty transcript string', () {
      expect(() => ContentSegmenter.segmentByMinutes(SourceData(transcriptJson: '', sourceType: 'youtube')), throwsArgumentError);
    });

    test('throws on invalid JSON', () {
      expect(() => ContentSegmenter.segmentByMinutes(SourceData(transcriptJson: 'not json', sourceType: 'youtube')), throwsArgumentError);
    });

    test('falls back to single segment when entries empty', () {
      final result = ContentSegmenter.segmentByMinutes(SourceData(transcriptJson: jsonEncode([]), sourceType: 'youtube'));
      expect(result.length, 1);
    });

    test('falls back to single segment when no groups', () {
      final result = ContentSegmenter.segmentByMinutes(SourceData(
        transcriptJson: jsonEncode([{'text': 'Hello', 'start': 0.0, 'duration': 0.0}]),
        sourceType: 'youtube',
      ));
      expect(result.length, 1);
    });
  });

  group('VirtualLesson.toLegacyLessonMap()', () {
    test('converts text lesson', () {
      final map = VirtualLesson(id: 't1', title: 'Test', textContent: 'Hello', orderIndex: 0, wordCount: 1).toLegacyLessonMap();
      expect(map['id'], 't1');
      expect(map['title'], 'Test');
      expect(map.containsKey('start_time'), false);
    });

    test('converts video lesson', () {
      final map = VirtualLesson(id: 'v1', title: 'Video', textContent: 'text', orderIndex: 1, startTime: 0.0, endTime: 30.0, duration: 30, wordCount: 50).toLegacyLessonMap();
      expect(map['start_time'], 0.0);
      expect(map['end_time'], 30.0);
    });

    test('omits wordCount when zero', () {
      final map = VirtualLesson(id: 'e', title: 'E', textContent: '', orderIndex: 0, wordCount: 0).toLegacyLessonMap();
      expect(map.containsKey('word_count'), false);
    });
  });

  group('ContentSegmenter.segmentByChapters()', () {
    final youtubeChapters = [
      {'start_time': 0.0, 'end_time': 6.0, 'title': 'Intro'},
      {'start_time': 6.0, 'end_time': 14.0, 'title': 'Main Topic'},
      {'start_time': 14.0, 'end_time': 18.5, 'title': 'Summary'},
    ];

    test('creates YouTube segments with filtered transcript text', () {
      final source = SourceData(
        transcriptJson: sampleTranscript,
        sourceType: 'youtube',
        sourceUrl: 'https://youtube.com/watch?v=test',
      );
      final result = ContentSegmenter.segmentByChapters(
        source: source,
        chapters: youtubeChapters,
        sourceType: 'youtube',
      );
      expect(result.length, 3);

      // Chapter 1: entries with start < 6.0
      expect(result[0].title, 'Intro');
      expect(result[0].startTime, 0.0);
      expect(result[0].endTime, 6.0);
      expect(result[0].textContent, contains('Hello and welcome'));
      expect(result[0].textContent, contains('learning Spanish'));

      // Chapter 2: entries with 6.0 <= start < 14.0
      expect(result[1].title, 'Main Topic');
      expect(result[1].startTime, 6.0);
      expect(result[1].endTime, 14.0);
      expect(result[1].textContent, contains('First we will cover'));
      expect(result[1].textContent, contains('more advanced phrases'));
      expect(result[1].textContent, isNot(contains('Hello and welcome')));

      // Chapter 3: entries with start >= 14.0
      expect(result[2].title, 'Summary');
      expect(result[2].startTime, 14.0);
      expect(result[2].endTime, 18.5);
      expect(result[2].textContent, contains('Finally a summary'));
      expect(result[2].textContent, contains('what we learned'));
    });

    test('creates segments with correct word counts', () {
      final source = SourceData(
        transcriptJson: sampleTranscript,
        sourceType: 'youtube',
      );
      final result = ContentSegmenter.segmentByChapters(
        source: source,
        chapters: youtubeChapters,
        sourceType: 'youtube',
      );
      for (final lesson in result) {
        expect(lesson.wordCount, greaterThan(0));
      }
    });

    test('handles empty transcript for YouTube chapters', () {
      final source = SourceData(sourceType: 'youtube');
      final result = ContentSegmenter.segmentByChapters(
        source: source,
        chapters: youtubeChapters,
        sourceType: 'youtube',
      );
      expect(result.length, 3);
      expect(result[0].title, 'Intro');
      expect(result[0].textContent, '');
    });

    test('splits PDF by page breaks using chapter page numbers', () {
      final chapters = [
        {'level': 1, 'title': 'Introduction', 'page': 1},
        {'level': 1, 'title': 'Chapter 1', 'page': 3},
        {'level': 1, 'title': 'Chapter 2', 'page': 7},
      ];
      final rawText = '<!-- PAGE_BREAK_PAGE_1 -->\n'
          'Introduction content...\n'
          '<!-- PAGE_BREAK_PAGE_3 -->\n'
          'Chapter 1 content...\n'
          '<!-- PAGE_BREAK_PAGE_7 -->\n'
          'Chapter 2 content...\n';
      final source = SourceData(
        rawText: rawText,
        sourceType: 'pdf',
      );
      final result = ContentSegmenter.segmentByChapters(
        source: source,
        chapters: chapters,
        sourceType: 'pdf',
      );
      expect(result.length, 3);
      expect(result[0].title, 'Introduction');
      expect(result[0].textContent, contains('Introduction content'));
      expect(result[1].title, 'Chapter 1');
      expect(result[1].textContent, contains('Chapter 1 content'));
      expect(result[2].title, 'Chapter 2');
      expect(result[2].textContent, contains('Chapter 2 content'));
    });

    test('falls back to word-based when no page breaks or headings match', () {
      final chapters = [
        {'title': 'Introduction'},
        {'title': 'Body'},
      ];
      final source = SourceData(
        rawText: _words(500),
        sourceType: 'text',
      );
      final result = ContentSegmenter.segmentByChapters(
        source: source,
        chapters: chapters,
        sourceType: 'text',
      );
      expect(result.length, greaterThanOrEqualTo(1));
      // Should use chapter title for first segment if available
      expect(result[0].title, 'Introduction');
    });

    test('falls back to word-based with chapter titles for proportional split', () {
      final chapters = [
        {'title': 'Part One'},
        {'title': 'Part Two'},
        {'title': 'Part Three'},
      ];
      final source = SourceData(
        rawText: _words(600),
        sourceType: 'text',
      );
      final result = ContentSegmenter.segmentByChapters(
        source: source,
        chapters: chapters,
        sourceType: 'text',
      );
      // With 600 words / 200 words per chunk = 3 segments
      // Should use chapter titles for the first 3 segments
      for (int i = 0; i < result.length && i < 3; i++) {
        expect(result[i].title, chapters[i]['title']);
      }
    });

    test('splits by markdown headings matching chapter titles', () {
      final chapters = [
        {'title': 'Getting Started'},
        {'title': 'Advanced Topics'},
      ];
      final filler = List.filled(10, 'enough content words to make a real section.').join(' ');
      final rawText = '# Getting Started\n$filler'
          '\n\n# Advanced Topics\n$filler';
      final source = SourceData(
        rawText: rawText,
        sourceType: 'text',
      );
      final result = ContentSegmenter.segmentByChapters(
        source: source,
        chapters: chapters,
        sourceType: 'text',
      );
      expect(result.length, 2);
      expect(result[0].title, 'Getting Started');
      expect(result[0].textContent, contains('enough content words'));
      expect(result[0].textContent, isNot(contains('Advanced Topics')));
      expect(result[1].title, 'Advanced Topics');
      expect(result[1].textContent, contains('enough content words'));
    });

    test('creates title-only segments for empty text with chapters', () {
      final source = SourceData(sourceType: 'text');
      final result = ContentSegmenter.segmentByChapters(
        source: source,
        chapters: [{'title': 'Empty Chapter'}],
        sourceType: 'text',
      );
      expect(result.length, 1);
      expect(result[0].title, 'Empty Chapter');
      expect(result[0].textContent, '');
    });

    test('segments have correct orderIndex continuity', () {
      final chapters = [
        {'start_time': 0.0, 'end_time': 10.0, 'title': 'Ch1'},
        {'start_time': 10.0, 'end_time': 20.0, 'title': 'Ch2'},
        {'start_time': 20.0, 'end_time': 30.0, 'title': 'Ch3'},
      ];
      final source = SourceData(
        transcriptJson: sampleTranscript,
        sourceType: 'youtube',
      );
      final result = ContentSegmenter.segmentByChapters(
        source: source,
        chapters: chapters,
        sourceType: 'youtube',
      );
      for (int i = 0; i < result.length; i++) {
        expect(result[i].orderIndex, i);
      }
    });
  });

  group('ContentSegmenter.segment() — edge cases', () {
    test('minutes on non-YouTube falls back to word-based with correct heuristic',
        () {
      // When segmentBy=minutes on non-YouTube content, it uses
      // wordsPerChunk = segmentValue * 200 heuristic
      final source = SourceData(rawText: _words(500), sourceType: 'text');
      final result = ContentSegmenter.segment(
        source: source,
        segmentBy: 'minutes',
        segmentValue: 5, // 5 min → 5 * 200 = 1000 words per chunk
      );
      // 500 words / 1000 words per chunk = 1 segment
      expect(result.length, 1);
      expect(result.first.wordCount, lessThanOrEqualTo(1000));
    });

    test('minutes on non-YouTube with null segmentValue uses default 1200',
        () {
      final source = SourceData(rawText: _words(2500), sourceType: 'text');
      final result = ContentSegmenter.segment(
        source: source,
        segmentBy: 'minutes',
        // segmentValue is null → should use default 1200 words
      );
      // 2500 / 1200 ≈ 3 segments
      expect(result.length, greaterThanOrEqualTo(2));
    });

    test('segmentAsOne with null rawText and null transcript returns empty',
        () {
      final result = ContentSegmenter.segmentAsOne(SourceData(sourceType: 'text'));
      expect(result.length, 1);
      expect(result.first.textContent, '');
      expect(result.first.wordCount, 0);
    });

    test('segmentByWords with text exactly at boundary creates correct count',
        () {
      // Exactly 1200 words with wordsPerChunk=1200 → 1 segment
      final result = ContentSegmenter.segmentByWords(
        SourceData(rawText: _words(1200), sourceType: 'text'),
        wordsPerChunk: 1200,
      );
      expect(result.length, 1);
    });

    test('segmentByWords with text just over boundary creates 2 segments',
        () {
      // 1201 words with wordsPerChunk=1200 → 2 segments
      final result = ContentSegmenter.segmentByWords(
        SourceData(rawText: _words(1201), sourceType: 'text'),
        wordsPerChunk: 1200,
      );
      expect(result.length, 2);
    });

    test('segmentByMinutes handles entries with missing start times', () {
      final transcript = jsonEncode([
        {'text': 'No start', 'end': 10.0},
        {'text': 'With start', 'start': 5.0, 'end': 15.0},
      ]);
      // Should not throw — entries without 'start' default to 0.0
      final result = ContentSegmenter.segmentByMinutes(
        SourceData(transcriptJson: transcript, sourceType: 'youtube'),
        intervalMinutes: 10,
      );
      expect(result.length, greaterThanOrEqualTo(1));
    });

    test('segment preserves order_index continuity', () {
      final source = SourceData(
        rawText: 'Part 1\n${_words(200)}\nPart 2\n${_words(200)}\nPart 3\n${_words(200)}',
        sourceType: 'text',
      );
      final result = ContentSegmenter.segment(
        source: source,
        segmentBy: 'words',
        segmentValue: 150,
      );
      for (int i = 0; i < result.length; i++) {
        expect(result[i].orderIndex, i);
      }
    });

    test('segmentByWords with single paragraph exceeding wordsPerChunk', () {
      // A single paragraph with sentence delimiters, much larger than the chunk size.
      // Each "sentence" acts as a split point.
      final text = List.filled(100, 'This is a test sentence that contains several words. ').join();
      final result = ContentSegmenter.segmentByWords(
        SourceData(rawText: text, sourceType: 'text'),
        wordsPerChunk: 50,
      );
      expect(result.length, greaterThanOrEqualTo(2));
    });

    test('segmentByMinutes adjusts transcript offset for segment start', () {
      final transcript = jsonEncode([
        {'text': 'A', 'start': 600.0, 'duration': 30.0, 'end': 630.0},
        {'text': 'B', 'start': 700.0, 'duration': 30.0, 'end': 730.0},
      ]);
      // interval = 10 min = 600s → both entries should be in the same group (index 1)
      final result = ContentSegmenter.segmentByMinutes(
        SourceData(transcriptJson: transcript, sourceType: 'youtube'),
        intervalMinutes: 10,
      );
      // Entry 0: 600/600 = 1, Entry 1: 700/600 = 1
      expect(result.length, 1);
      expect(result.first.textContent, contains('A'));
      expect(result.first.textContent, contains('B'));
    });
  });
}
