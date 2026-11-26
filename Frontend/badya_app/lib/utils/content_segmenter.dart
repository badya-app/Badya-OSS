import 'dart:convert';

import 'package:Badya/models/source_data.dart';
import 'package:Badya/utils/logger.dart';

/// Simple in-memory segment — NOT a Firestore document.
/// Created at read-time, discarded on preference change.
class VirtualLesson {
  final String id;
  final String title;
  final String textContent;
  final int orderIndex;
  final bool isProcessed;

  // YouTube / video-specific
  final double? startTime;
  final double? endTime;
  final int? duration;

  // Optional metadata
  final int wordCount;

  const VirtualLesson({
    required this.id,
    required this.title,
    required this.textContent,
    required this.orderIndex,
    this.isProcessed = true,
    this.startTime,
    this.endTime,
    this.duration,
    this.wordCount = 0,
  });

  /// Convert to the legacy lesson map format (for backward compatibility
  /// until Phase 4C removes Firestore writes entirely).
  Map<String, dynamic> toLegacyLessonMap() {
    return {
      'id': id,
      'title': title,
      'text_content': textContent,
      'order_index': orderIndex,
      'is_processed': isProcessed,
      if (startTime != null) 'start_time': startTime,
      if (endTime != null) 'end_time': endTime,
      if (duration != null) 'duration': duration,
      if (wordCount > 0) 'word_count': wordCount,
    };
  }
}

/// Pure utility class — all methods are stateless pure functions.
/// No Firebase, no async, no side effects.
///
/// Extracted from ImportService's private segmentation methods as part of
/// the Phase 4B refactor. Enables client-side virtual segmentation that
/// can be unit-tested independently of Firestore.
class ContentSegmenter {
  /// Main entry point: dispatch to correct strategy based on preference.
  ///
  /// [source] — the raw source data (text, transcript, etc.)
  /// [segmentBy] — segmentation method: 'none', 'words', 'minutes'
  /// [segmentValue] — optional threshold value (words per chunk, minutes, etc.)
  /// [sourceType] — 'youtube', 'text', 'pdf', 'txt', 'url', etc.
  /// [contentData] — full content document map (used for fallback)
  static List<VirtualLesson> segment({
    required SourceData source,
    required String segmentBy,
    int? segmentValue,
    String? sourceType,
    Map<String, dynamic>? contentData,
  }) {
    final isYouTube =
        sourceType == 'youtube' ||
        (source.sourceUrl?.contains('youtube.com') == true) ||
        (source.sourceUrl?.contains('youtu.be') == true);

    switch (segmentBy) {
      case 'none':
        return segmentAsOne(source, contentData: contentData);
      case 'words':
        return segmentByWords(source, wordsPerChunk: segmentValue ?? 1200);
      case 'minutes':
        if (!isYouTube) {
          // Minutes segmentation only makes sense for timed content.
          // Fall back to word-based with word-per-minute heuristic.
          Logger.warn(
            'segment: minutes mode used on non-YouTube content ($sourceType). '
            'Falling back to word-based segmentation with '
            '${segmentValue != null ? segmentValue * 200 : 1200} words per chunk '
            '(200 words/minute heuristic).',
          );
          return segmentByWords(
            source,
            wordsPerChunk: segmentValue != null ? segmentValue * 200 : 1200,
          );
        }
        return segmentByMinutes(
          source,
          intervalMinutes: segmentValue ?? 10,
          contentData: contentData,
        );
      case 'chapters':
        final chapters =
            contentData?['metadata']?['chapters'] as List<dynamic>?;
        if (chapters != null && chapters.isNotEmpty) {
          return segmentByChapters(
            source: source,
            chapters: chapters.cast<Map<String, dynamic>>(),
            sourceType: sourceType,
            contentData: contentData,
          );
        }
        // Fall back if no chapter data available
        if (isYouTube) {
          return segmentByMinutes(
            source,
            intervalMinutes: segmentValue ?? 10,
            contentData: contentData,
          );
        }
        return segmentByWords(source);
      default:
        throw ArgumentError('Unknown segmentation method: $segmentBy');
    }
  }

  /// No segmentation — single lesson with full content.
  static List<VirtualLesson> segmentAsOne(
    SourceData source, {
    Map<String, dynamic>? contentData,
  }) {
    final title = contentData?['title'] as String? ?? 'Full Content';

    // Determine the text content
    String fullText;
    if (source.rawText != null && source.rawText!.isNotEmpty) {
      fullText = source.rawText!;
    } else if (source.transcriptJson != null) {
      // Flatten transcript JSON into readable text
      fullText = _flattenTranscriptToText(source.transcriptJson!);
    } else {
      fullText = contentData?['metadata']?['raw_text'] as String? ?? '';
    }

    final wordCount = fullText.isEmpty
        ? 0
        : fullText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

    return [
      VirtualLesson(
        id: 'full',
        title: title,
        textContent: fullText,
        orderIndex: 0,
        isProcessed: true,
        wordCount: wordCount,
      ),
    ];
  }

  /// Segment by word count threshold (default 1200 words per chunk).
  /// Works for both text and YouTube (flattens transcript first).
  static List<VirtualLesson> segmentByWords(
    SourceData source, {
    int wordsPerChunk = 1200,
  }) {
    // Resolve the full text
    String fullText = '';
    if (source.rawText != null && source.rawText!.isNotEmpty) {
      fullText = source.rawText!;
    } else if (source.transcriptJson != null) {
      fullText = _flattenTranscriptToText(source.transcriptJson!);
    }

    if (fullText.isEmpty) {
      Logger.warn(
        'segmentByWords: No text content available. Falling back to single segment.',
      );
      return segmentAsOne(source);
    }

    return _segmentTextByWords(fullText, wordsPerChunk: wordsPerChunk);
  }

  /// Segment YouTube transcript by time intervals (default 10 min).
  /// If no transcript is available but duration is known, slices by video time.
  static List<VirtualLesson> segmentByMinutes(
    SourceData source, {
    int intervalMinutes = 10,
    Map<String, dynamic>? contentData,
  }) {
    if (source.transcriptJson == null || source.transcriptJson!.isEmpty) {
      final duration = (contentData?['metadata']?['duration'] as num?)?.toDouble() ?? 0.0;
      if (duration > 0) {
        final int intervalSeconds = intervalMinutes * 60;
        final int numSegments = (duration / intervalSeconds).ceil().clamp(1, 200);
        final title = contentData?['title'] as String? ?? 'Video';
        return List.generate(numSegments, (i) {
          final start = (i * intervalSeconds).toDouble();
          final end = ((i + 1) * intervalSeconds).toDouble().clamp(0.0, duration);
          return VirtualLesson(
            id: 'seg_${i + 1}',
            title: numSegments == 1 ? title : 'Part ${i + 1}',
            textContent: '',
            orderIndex: i,
            isProcessed: true,
            startTime: start,
            endTime: end,
            duration: (end - start).round(),
            wordCount: 0,
          );
        });
      }
      return segmentAsOne(source, contentData: contentData);
    }

    final List<dynamic> transcriptEntries;
    try {
      transcriptEntries = jsonDecode(source.transcriptJson!) as List<dynamic>;
    } catch (e) {
      final duration = (contentData?['metadata']?['duration'] as num?)?.toDouble() ?? 0.0;
      if (duration > 0) {
        final int intervalSeconds = intervalMinutes * 60;
        final int numSegments = (duration / intervalSeconds).ceil().clamp(1, 200);
        final title = contentData?['title'] as String? ?? 'Video';
        return List.generate(numSegments, (i) {
          final start = (i * intervalSeconds).toDouble();
          final end = ((i + 1) * intervalSeconds).toDouble().clamp(0.0, duration);
          return VirtualLesson(
            id: 'seg_${i + 1}',
            title: numSegments == 1 ? title : 'Part ${i + 1}',
            textContent: '',
            orderIndex: i,
            isProcessed: true,
            startTime: start,
            endTime: end,
            duration: (end - start).round(),
            wordCount: 0,
          );
        });
      }
      return segmentAsOne(source, contentData: contentData);
    }

    if (transcriptEntries.isEmpty) {
      // No transcript entries — fall back to single segment with a warning.
      // This shouldn't happen if the caller validates before calling.
      Logger.warn(
        'segmentByMinutes: transcript JSON has 0 entries. Falling back to single segment.',
      );
      return segmentAsOne(source, contentData: contentData);
    }

    final int intervalSeconds = intervalMinutes * 60;

    // Group transcript entries by time interval
    final Map<int, List<Map<String, dynamic>>> groups = {};

    for (final entry in transcriptEntries) {
      if (entry is! Map) continue;
      final start = (entry['start'] as num?)?.toDouble() ?? 0.0;
      final end = (entry['end'] as num?)?.toDouble() ?? (start + 5.0);
      final text = entry['text'] as String? ?? '';

      final groupIndex = (start / intervalSeconds).floor();
      groups.putIfAbsent(groupIndex, () => []);
      groups[groupIndex]!.add({'text': text, 'start': start, 'end': end});
    }

    if (groups.isEmpty) {
      Logger.warn(
        'segmentByMinutes: no time groups formed from transcript. Falling back to single segment.',
      );
      return segmentAsOne(source);
    }

    final sortedGroups = groups.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return List.generate(sortedGroups.length, (i) {
      final group = sortedGroups[i];
      final groupStart = group.value.first['start'] as double;
      final groupEnd = group.value.last['end'] as double;
      final text = group.value.map((e) => e['text'] as String).join(' ');

      final wordCount = text.isEmpty
          ? 0
          : text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

      return VirtualLesson(
        id: 'seg_${i + 1}',
        title: 'Part ${i + 1}',
        textContent: text,
        orderIndex: i,
        isProcessed: true,
        startTime: groupStart,
        endTime: groupEnd,
        duration: (groupEnd - groupStart).round(),
        wordCount: wordCount,
      );
    });
  }

  // ---------------------------------------------------------------
  // Chapter-based Segmentation (YouTube + PDF / Text)
  // ---------------------------------------------------------------

  /// Segment content using chapter metadata extracted by the backend.
  ///
  /// [chapters] comes from `content.metadata['chapters']`:
  ///   YouTube:  [{start_time, end_time, title}]
  ///   PDF:      [{level, title, page}]
  ///
  /// YouTube chapters filter the transcript by time windows.
  /// PDF/text chapters use page-break markers or markdown headings.
  /// Falls back to word-based segmentation with chapter titles if no
  /// structural split points are found.
  static List<VirtualLesson> segmentByChapters({
    required SourceData source,
    required List<Map<String, dynamic>> chapters,
    String? sourceType,
    Map<String, dynamic>? contentData,
  }) {
    final isYouTube =
        sourceType == 'youtube' ||
        (source.sourceUrl?.contains('youtube.com') == true) ||
        (source.sourceUrl?.contains('youtu.be') == true);

    if (isYouTube) {
      return _segmentYouTubeByChapters(source, chapters);
    }
    return _segmentTextByChapters(source, chapters);
  }

  /// YouTube: filter transcript entries into each chapter's time window.
  static List<VirtualLesson> _segmentYouTubeByChapters(
    SourceData source,
    List<Map<String, dynamic>> chapters,
  ) {
    List<Map<String, dynamic>> transcriptEntries = [];
    if (source.transcriptJson != null && source.transcriptJson!.isNotEmpty) {
      try {
        final parsed = jsonDecode(source.transcriptJson!);
        transcriptEntries = (parsed as List)
            .whereType<Map<String, dynamic>>()
            .toList();
      } catch (e) {
        Logger.warn('Failed to decode transcript JSON: $e');
      }
    }

    if (transcriptEntries.isEmpty) {
      // No transcript — create segments with titles/times only
      return List.generate(chapters.length, (i) {
        final chapter = chapters[i];
        return VirtualLesson(
          id: 'chapter_${i + 1}',
          title: chapter['title'] as String? ?? 'Chapter ${i + 1}',
          textContent: '',
          orderIndex: i,
          isProcessed: true,
          startTime: (chapter['start_time'] as num?)?.toDouble(),
          endTime: (chapter['end_time'] as num?)?.toDouble(),
        );
      });
    }

    final List<VirtualLesson> lessons = [];
    for (int i = 0; i < chapters.length; i++) {
      final chapter = chapters[i];
      final double start = (chapter['start_time'] as num?)?.toDouble() ?? 0.0;
      final double end =
          (chapter['end_time'] as num?)?.toDouble() ?? double.infinity;

      // Filter transcript entries that overlap with this chapter's time range
      final matchingEntries = transcriptEntries.where((entry) {
        final entryStart = (entry['start'] as num?)?.toDouble() ?? 0.0;
        return entryStart >= start && entryStart < end;
      }).toList();

      final text = matchingEntries
          .map((e) => e['text'] as String? ?? '')
          .where((t) => t.isNotEmpty)
          .join(' ');

      final wordCount = text.isEmpty
          ? 0
          : text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

      lessons.add(
        VirtualLesson(
          id: 'chapter_${i + 1}',
          title: chapter['title'] as String? ?? 'Chapter ${i + 1}',
          textContent: text,
          orderIndex: i,
          isProcessed: true,
          startTime: start,
          endTime: end,
          duration: (end - start).round().abs(),
          wordCount: wordCount,
        ),
      );
    }

    return lessons;
  }

  /// Text/PDF: split by page-break markers, markdown headings, or word count.
  static List<VirtualLesson> _segmentTextByChapters(
    SourceData source,
    List<Map<String, dynamic>> chapters,
  ) {
    final rawText = source.rawText ?? '';
    if (rawText.isEmpty) {
      return List.generate(chapters.length, (i) {
        final chapter = chapters[i];
        return VirtualLesson(
          id: 'chapter_${i + 1}',
          title: chapter['title'] as String? ?? 'Chapter ${i + 1}',
          textContent: '',
          orderIndex: i,
          isProcessed: true,
          wordCount: 0,
        );
      });
    }

    // Strategy 1: Page-break markers from PDF extraction
    // E.g. <!-- PAGE_BREAK_PAGE_1 -->
    final pageBreakPattern = RegExp(r'<!-- PAGE_BREAK_PAGE_(\d+) -->');
    final pageBreaks = <int, int>{}; // pageNumber -> textOffset
    for (final match in pageBreakPattern.allMatches(rawText)) {
      final pageNum = int.tryParse(match.group(1) ?? '') ?? 0;
      pageBreaks[pageNum] = match.start;
    }

    if (pageBreaks.isNotEmpty && chapters.any((c) => c['page'] != null)) {
      final result = _splitByPageBreaks(
        rawText,
        chapters,
        pageBreaks,
        pageBreakPattern,
      );
      if (result.isNotEmpty) return result;
    }

    // Strategy 2: Markdown headings matching chapter titles
    final result = _splitByMarkdownHeadings(rawText, chapters);
    if (result.isNotEmpty) return result;

    // Strategy 3: Fallback — word-based split with chapter titles
    final totalWords = rawText
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;
    final wordsPerChunk = (totalWords / chapters.length).ceil();
    final wordSegments = _segmentTextByWords(
      rawText,
      wordsPerChunk: wordsPerChunk > 0 ? wordsPerChunk : 1200,
    );

    return List.generate(wordSegments.length, (i) {
      final seg = wordSegments[i];
      final title = i < chapters.length
          ? (chapters[i]['title'] as String? ?? seg.title)
          : seg.title;
      return VirtualLesson(
        id: seg.id,
        title: title,
        textContent: seg.textContent,
        orderIndex: i,
        isProcessed: seg.isProcessed,
        wordCount: seg.wordCount,
      );
    });
  }

  /// Split raw text by page-break markers using chapter page ranges.
  static List<VirtualLesson> _splitByPageBreaks(
    String rawText,
    List<Map<String, dynamic>> chapters,
    Map<int, int> pageBreaks,
    RegExp pageBreakPattern,
  ) {
    final chaptersWithPages =
        chapters
            .where((c) => c['page'] != null)
            .map((c) => Map<String, dynamic>.from(c))
            .toList()
          ..sort(
            (a, b) => ((a['page'] as num?)?.toInt() ?? 0).compareTo(
              (b['page'] as num?)?.toInt() ?? 0,
            ),
          );

    if (chaptersWithPages.isEmpty) return [];

    final sortedPages = pageBreaks.keys.toList()..sort();
    if (sortedPages.isEmpty) return [];

    final maxPage = sortedPages.last;

    final List<VirtualLesson> lessons = [];
    for (int i = 0; i < chaptersWithPages.length; i++) {
      final chapter = chaptersWithPages[i];
      final int startPage =
          (chapter['page'] as num?)?.toInt() ?? sortedPages.first;

      final int endPage = i + 1 < chaptersWithPages.length
          ? (chaptersWithPages[i + 1]['page'] as num?)?.toInt() ?? maxPage + 1
          : maxPage + 1;

      // Find nearest actual page breaks
      final nearestStart = _nearestPageBreak(startPage, sortedPages);
      if (nearestStart == null) continue;

      // Use the next chapter's page break as the end boundary, or
      // fall back to end of document for the last chapter.
      final int endOffset;
      if (i + 1 < chaptersWithPages.length) {
        final nextPage =
            (chaptersWithPages[i + 1]['page'] as num?)?.toInt() ?? maxPage + 1;
        final nearestEnd = _nearestPageBreak(nextPage, sortedPages);
        // Only use next chapter's page break if it differs from current start
        if (nearestEnd != null &&
            nearestEnd != nearestStart &&
            pageBreaks.containsKey(nearestEnd)) {
          endOffset = pageBreaks[nearestEnd]!;
        } else {
          endOffset = rawText.length;
        }
      } else {
        // Last chapter: extend to end of document
        endOffset = rawText.length;
      }

      final startOffset = pageBreaks[nearestStart] ?? 0;

      String chapterText = rawText
          .substring(
            startOffset,
            endOffset > rawText.length ? rawText.length : endOffset,
          )
          .trim();
      chapterText = chapterText.replaceAll(pageBreakPattern, '').trim();

      final wordCount = chapterText.isEmpty
          ? 0
          : chapterText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

      lessons.add(
        VirtualLesson(
          id: 'chapter_${i + 1}',
          title: chapter['title'] as String? ?? 'Chapter ${i + 1}',
          textContent: chapterText,
          orderIndex: i,
          isProcessed: true,
          wordCount: wordCount,
        ),
      );
    }

    return lessons;
  }

  /// Find the nearest page break <= the target page number.
  static int? _nearestPageBreak(int targetPage, List<int> sortedPages) {
    for (int i = sortedPages.length - 1; i >= 0; i--) {
      if (sortedPages[i] <= targetPage) return sortedPages[i];
    }
    return sortedPages.isNotEmpty ? sortedPages.first : null;
  }

  /// Split raw text by markdown headings that match chapter titles.
  static List<VirtualLesson> _splitByMarkdownHeadings(
    String rawText,
    List<Map<String, dynamic>> chapters,
  ) {
    final headingPattern = RegExp(r'^#{1,6}\s+(.+)$', multiLine: true);

    // Build a map: lowercase chapter title -> chapter index
    final chapterTitleMap = <String, int>{};
    for (int i = 0; i < chapters.length; i++) {
      final title = (chapters[i]['title'] as String? ?? '')
          .trim()
          .toLowerCase();
      if (title.isNotEmpty) {
        chapterTitleMap[title] = i;
      }
    }

    if (chapterTitleMap.isEmpty) return [];

    // Find matching heading positions
    final headingPositions = <int, int>{}; // position -> chapterIndex

    for (final match in headingPattern.allMatches(rawText)) {
      final headingText = match.group(1)?.trim().toLowerCase() ?? '';
      // Strip trailing formatting
      final cleanHeading = headingText
          .replaceAll(RegExp(r'[#*_~`]'), '')
          .trim();

      if (chapterTitleMap.containsKey(cleanHeading)) {
        headingPositions[match.start] = chapterTitleMap[cleanHeading]!;
      }
    }

    if (headingPositions.length < 2 && chapters.length > 1) return [];

    // Sort by position in text
    final sortedPositions = headingPositions.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final List<VirtualLesson> lessons = [];
    for (int i = 0; i < sortedPositions.length; i++) {
      final entry = sortedPositions[i];
      final start = entry.key;
      final end = i + 1 < sortedPositions.length
          ? sortedPositions[i + 1].key
          : rawText.length;

      String chapterText = rawText.substring(start, end).trim();
      // Remove the heading line itself
      final firstNewline = chapterText.indexOf('\n');
      if (firstNewline >= 0) {
        chapterText = chapterText.substring(firstNewline + 1).trim();
      }

      final chapterIdx = entry.value;
      final chapter = chapters[chapterIdx];

      final wordCount = chapterText.isEmpty
          ? 0
          : chapterText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

      lessons.add(
        VirtualLesson(
          id: 'chapter_${chapterIdx + 1}',
          title: chapter['title'] as String? ?? 'Chapter ${chapterIdx + 1}',
          textContent: chapterText,
          orderIndex: chapterIdx,
          isProcessed: true,
          wordCount: wordCount,
        ),
      );
    }

    return lessons;
  }

  // ---------------------------------------------------------------
  // Private Helpers
  // ---------------------------------------------------------------

  /// Fallback: segment text by word count (~1200 words per chunk by default).
  static List<VirtualLesson> _segmentTextByWords(
    String text, {
    int wordsPerChunk = 1200,
  }) {
    List<String> paragraphs;
    if (text.contains('\n\n')) {
      paragraphs = text
          .split('\n\n')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();
    } else {
      paragraphs = text
          .split('\n')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .toList();
    }

    final List<String> chunks = [];
    List<String> currentChunk = [];
    int currentWords = 0;

    for (final p in paragraphs) {
      final pWords = p.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

      if (pWords > wordsPerChunk) {
        if (currentChunk.isNotEmpty) {
          chunks.add(currentChunk.join('\n\n'));
          currentChunk = [];
          currentWords = 0;
        }
        final sentences = p.split('. ');
        String subP = '';
        for (final sentence in sentences) {
          if ('$subP $sentence'
                  .split(RegExp(r'\s+'))
                  .where((w) => w.isNotEmpty)
                  .length >
              wordsPerChunk) {
            chunks.add(subP.trim());
            subP = '$sentence. ';
          } else {
            subP += '$sentence. ';
          }
        }
        if (subP.trim().isNotEmpty) {
          currentChunk.add(subP.trim());
          currentWords = subP
              .split(RegExp(r'\s+'))
              .where((w) => w.isNotEmpty)
              .length;
        }
        continue;
      }

      if (currentWords + pWords > wordsPerChunk && currentChunk.isNotEmpty) {
        chunks.add(currentChunk.join('\n\n'));
        currentChunk = [];
        currentWords = 0;
      }

      currentChunk.add(p);
      currentWords += pWords;
    }

    if (currentChunk.isNotEmpty) {
      chunks.add(currentChunk.join('\n\n'));
    }

    if (chunks.isEmpty) {
      chunks.add(text);
    }

    return List.generate(chunks.length, (i) {
      final wordCount = chunks[i].isEmpty
          ? 0
          : chunks[i].split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

      return VirtualLesson(
        id: 'part_${i + 1}',
        title: 'Part ${i + 1}',
        textContent: chunks[i],
        orderIndex: i,
        isProcessed: true,
        wordCount: wordCount,
      );
    });
  }

  /// Flatten a JSON transcript array into readable text.
  static String _flattenTranscriptToText(String transcriptJson) {
    try {
      final entries = jsonDecode(transcriptJson) as List<dynamic>;
      return entries
          .whereType<Map>()
          .map((e) => e['text'] as String? ?? '')
          .join(' ');
    } catch (e) {
      return '';
    }
  }
}
