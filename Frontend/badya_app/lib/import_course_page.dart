import 'package:Badya/widgets/language_picker_sheet.dart';
import 'package:Badya/services/language_manager.dart';
import 'package:Badya/utils/constants.dart';
import 'package:Badya/widgets/balance_widget.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:Badya/services/content_service.dart';
import 'package:Badya/services/user_preferences_service.dart';
import 'package:Badya/widgets/custom_app_bar.dart';
import 'package:Badya/imported_content_page.dart';
import 'package:Badya/utils/import_utils.dart';
import 'package:Badya/widgets/lesson_list_skeleton.dart';
import 'package:Badya/services/auth_service.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

class ImportCoursePage extends StatelessWidget {
  final Map<String, dynamic> importItem;
  final String? contentId;

  ImportCoursePage({super.key, required this.importItem, this.contentId});

  /// Navigates to the appropriate page for an import item.
  /// If it's a text import with only one lesson, it skips the course page.
  static Future<void> navigate(
    BuildContext context,
    Map<String, dynamic> item, {
    String? contentId,
  }) async {
    final String id = (item['id'] ?? '').toString();

    // Mark as opened — use contentId for the new system
    final String targetId = contentId ?? id;
    if (targetId.isNotEmpty) {
      await ContentService().markAsOpened(targetId);
    }

    if (!context.mounted) return;

    // Detection logic
    final metadata = Map<String, dynamic>.from(item['metadata'] ?? {});
    final String type = (metadata['type'] ?? '').toString().toLowerCase();
    final String sourceType = (metadata['source_type'] ?? '')
        .toString()
        .toLowerCase();
    final bool isText = type == 'text' || sourceType == 'text';

    if (isText) {
      final lessons = await ContentService().getContentSegmentsOnce(
        contentId ?? id,
      );
      if (lessons.length == 1 && context.mounted) {
        final userPrefs = UserPreferencesService();
        final lang = await userPrefs.getCurrentLanguage();
        final nativeLang = await userPrefs.getNativeLanguage();
        final authService = Provider.of<AuthService>(context, listen: false);
        final userId = authService.currentUser?.uid ?? 'anonymous';

        if (context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ImportedContentPage(
                importId: id,
                contentId: contentId,
                lesson: lessons.first,
                userId: userId,
                language: lang,
                nativeLanguage: nativeLang,
              ),
            ),
          );
          return;
        }
      }
    }

    // Default: show the course page
    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          settings: const RouteSettings(name: 'ImportCoursePage'),
          builder: (context) =>
              ImportCoursePage(importItem: item, contentId: contentId),
        ),
      );
    }
  }

  /// Returns true if the import item should be treated as a video (YouTube/URL).
  static bool _isVideoImport(Map<String, dynamic> item) =>
      ImportUtils.isVideoImport(item);

  /// Formats seconds to MM:SS or HH:MM:SS.
  static String _formatSeconds(double seconds) {
    final totalSeconds = seconds.round().abs();
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Returns a human-friendly reading/watch time estimate for a lesson (F6).
  ///
  /// • For video segments: derives duration from [start_time] and [end_time].
  /// • For text lessons: uses [word_count] metadata at 200 wpm, falling back to
  ///   character count at 1000 chars/min.
  static String _lessonTimeEstimate(Map<String, dynamic> lesson, bool isVideo) {
    if (isVideo) {
      final double start = (lesson['start_time'] as num?)?.toDouble() ?? 0.0;
      final double end = (lesson['end_time'] as num?)?.toDouble() ?? 0.0;
      final int secs = (end - start).round().abs();
      if (secs <= 0) return '';
      final int mins = secs ~/ 60;
      final int remSecs = secs % 60;
      if (mins == 0) return '${remSecs}s watch';
      if (remSecs == 0) return '${mins} min watch';
      return '${mins}:${remSecs.toString().padLeft(2, '0')} watch';
    } else {
      // Text lesson — estimate from word_count first, then character count
      final int? wordCount = (lesson['word_count'] as num?)?.toInt();
      if (wordCount != null && wordCount > 0) {
        final int minsRead = (wordCount / 200).ceil();
        return '~${minsRead} min read';
      }
      final String text = (lesson['text_content'] as String?) ?? '';
      if (text.isNotEmpty) {
        final int words = text.split(RegExp(r'\s+')).length;
        final int minsRead = (words / 200).ceil();
        return '~${minsRead} min read';
      }
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final String importId = importItem['id'];
    final String title = importItem['title'] ?? 'Imported Course';

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                CustomAppBar(
                  showMenuButton: false,
                  showLanguageButton: true,
                  languageCode:
                      languageCodes[context
                          .watch<LanguageManager>()
                          .currentLanguage],
                  onLanguagePressed: () {
                    final lm = context.read<LanguageManager>();
                    showLanguagePickerSheet(
                      context: context,
                      myLanguages: lm.myLanguages,
                      currentLanguage: lm.currentLanguage,
                      languageCodes: languageCodes,
                      onLanguageSelected: (lang) =>
                          lm.updateCurrentLanguage(lang),
                    );
                  },
                  actions: const [BalanceWidget()],
                ),
                // Single stream that feeds both the progress header and lesson list.
                // Phase 4E: Uses ContentService.getContentSegments (in-memory virtual) instead of ImportService.getImportLessons.
                // Phase 4F: Overall progress is computed in-memory from merged lesson data
                // (last_position merged from user_content/{contentId}/progress subcollection).
                // — Progress header ————————————————————————————————————
                // Uses a separate stream for progress updates so that real-time
                // progress changes (from other sessions/tabs) update the header
                // without re-building the entire lesson list.
                _ProgressHeader(
                  contentId: contentId ?? importId,
                  contentService: ContentService(),
                ),
                // — Lesson list (re-uses the same stream) ————————————————
                SliverFillRemaining(
                  hasScrollBody: true,
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: ContentService().getContentSegments(
                      contentId ?? importId,
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const LessonListSkeleton();
                      }
                      final lessons = snapshot.data ?? [];

                      if (lessons.isEmpty) {
                        final bool isVideo = _isVideoImport(importItem);
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  width: 36,
                                  height: 36,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.teal),
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  'Processing segments...',
                                  style: GoogleFonts.nunito(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(context).brightness == Brightness.dark
                                        ? Colors.white70
                                        : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Transcripts or chapters are being prepared.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.nunito(
                                    fontSize: 13,
                                    color: Colors.grey,
                                  ),
                                ),
                                if (isVideo) ...[
                                  const SizedBox(height: 24),
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      final fallbackLesson = <String, dynamic>{
                                        'id': '${contentId ?? importId}_full',
                                        'title': title,
                                        'start_time': 0.0,
                                        'end_time': null,
                                        'is_processed': true,
                                      };
                                      _handleLessonTap(context, fallbackLesson, importId);
                                    },
                                    icon: const Icon(Icons.play_circle_outline, color: Colors.teal),
                                    label: Text(
                                      'Play Video Directly',
                                      style: GoogleFonts.nunito(
                                        color: Colors.teal,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: Colors.teal),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      }

                      return Column(
                        children: [
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                0,
                                16,
                                120,
                              ), // Extra bottom padding for button
                              itemCount: lessons.length,
                              itemBuilder: (context, index) {
                                final lesson = lessons[index];

                                // Progress calculation
                                // All lesson types store last_position as a
                                // normalized 0-1 value (scrolled fraction for
                                // text, watched fraction for video).
                                final bool isTextLesson =
                                    lesson['start_time'] == null &&
                                    lesson['end_time'] == null;

                                final double lastPos =
                                    (lesson['last_position'] as num?)
                                        ?.toDouble() ??
                                    0.0;

                                final double start =
                                    (lesson['start_time'] as num?)
                                        ?.toDouble() ??
                                    0.0;
                                final double end =
                                    (lesson['end_time'] as num?)?.toDouble() ??
                                    1.0;

                                final double totalDuration = end - start;
                                final double progress = lastPos.clamp(0.0, 1.0);

                                final bool isVideo = _isVideoImport(importItem);

                                final bool isCompleted = progress >= 0.99;
                                // Phase 4 UI: Score from merged progress
                                final int score =
                                    (lesson['score'] as num?)?.toInt() ?? 0;
                                final bool hasScore = score > 0;

                                final String statusText;
                                if (hasScore) {
                                  statusText = 'Score: $score';
                                } else if (isCompleted) {
                                  statusText = 'Completed';
                                } else if (progress > 0) {
                                  if (isVideo && totalDuration > 0) {
                                    final double remainingSeconds =
                                        (1.0 - progress) * totalDuration;
                                    final int mins = (remainingSeconds / 60)
                                        .floor();
                                    final int secs = (remainingSeconds % 60)
                                        .toInt();
                                    final String timeStr = mins > 0
                                        ? '$mins:${secs.toString().padLeft(2, '0')} left'
                                        : '${secs}s left';
                                    statusText =
                                        '${(progress * 100).toInt()}% • $timeStr';
                                  } else {
                                    statusText = '${(progress * 100).toInt()}%';
                                  }
                                } else {
                                  statusText = 'Not started';
                                }

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  decoration: BoxDecoration(
                                    color:
                                        Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.white.withValues(alpha: 0.05)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color: isCompleted && hasScore
                                          ? Colors.teal.withValues(alpha: 0.6)
                                          : isCompleted
                                              ? Colors.teal
                                                    .withValues(alpha: 0.3)
                                              : Theme.of(context)
                                                    .dividerColor
                                                    .withValues(alpha: 0.1),
                                      width: isCompleted && hasScore ? 2.0 : 1.5,
                                    ),
                                    boxShadow:
                                        isCompleted && hasScore
                                            ? [
                                                BoxShadow(
                                                  color: Colors.teal
                                                      .withValues(alpha: 0.15),
                                                  blurRadius: 12,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ]
                                            : Theme.of(context).brightness ==
                                                Brightness.light
                                            ? [
                                                BoxShadow(
                                                  color:
                                                      Colors.black.withValues(
                                                    alpha: 0.05,
                                                  ),
                                                  blurRadius: 10,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ]
                                            : null,
                                  ),
                                  child: InkWell(
                                    onTap: () => _handleLessonTap(
                                      context,
                                      lesson,
                                      importId,
                                    ),
                                    borderRadius: BorderRadius.circular(24),
                                    child: Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Column(
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                width: 48,
                                                height: 48,
                                                decoration: BoxDecoration(
                                                  color: isCompleted
                                                      ? Colors.teal.withValues(
                                                          alpha: 0.1,
                                                        )
                                                      : (progress > 0
                                                            ? Colors.teal
                                                                  .withValues(
                                                                    alpha: 0.2,
                                                                  )
                                                            : Theme.of(context)
                                                                  .dividerColor
                                                                  .withValues(
                                                                    alpha: 0.05,
                                                                  )),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    (index + 1).toString(),
                                                    style: GoogleFonts.nunito(
                                                      color:
                                                          isCompleted ||
                                                              progress > 0
                                                          ? Colors.teal
                                                          : null,
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      lessons.length == 1
                                                          ? title
                                                          : (lesson['title'] ??
                                                                'Part ${index + 1}'),
                                                      style: GoogleFonts.nunito(
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        fontSize: 18,
                                                        height: 1.2,
                                                      ),
                                                    ),
                                                    if (lesson['start_time'] != null && lesson['end_time'] != null) ...[
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        '${_formatSeconds(start)} - ${_formatSeconds(end)}',
                                                        style:
                                                            GoogleFonts.nunito(
                                                              color: Colors.grey
                                                                  .withValues(
                                                                    alpha: 0.35,
                                                                  ),
                                                              fontSize: 12,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                      ),
                                                    ],
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      statusText,
                                                      style: GoogleFonts.nunito(
                                                        color: Colors.grey,
                                                        fontSize: 14,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    // Watch / read time estimate (F6)
                                                    Text(
                                                      _lessonTimeEstimate(
                                                        lesson,
                                                        isVideo,
                                                      ),
                                                      style: GoogleFonts.nunito(
                                                        color: Colors.grey
                                                            .withValues(
                                                              alpha: 0.55,
                                                            ),
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Icon(
                                                isCompleted
                                                    ? Icons.check_circle
                                                    : (progress > 0
                                                          ? Icons
                                                                .play_circle_filled
                                                          : Icons
                                                                .arrow_forward_ios),
                                                color:
                                                    isCompleted || progress > 0
                                                    ? (Theme.of(
                                                                context,
                                                              ).brightness ==
                                                              Brightness.dark
                                                          ? Colors.tealAccent
                                                          : Colors.teal)
                                                    : Colors.grey.withValues(
                                                        alpha: 0.5,
                                                      ),
                                                size:
                                                    isCompleted || progress > 0
                                                    ? 28
                                                    : 16,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 16),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            child: LinearProgressIndicator(
                                              value: hasScore ? score / 100.0 : 0.0,
                                              backgroundColor: Theme.of(context)
                                                  .dividerColor
                                                  .withValues(alpha: 0.05),
                                              valueColor: AlwaysStoppedAnimation<Color>(
                                                isCompleted
                                                    ? (Theme.of(
                                                                context,
                                                              ).brightness ==
                                                              Brightness.dark
                                                          ? Colors.tealAccent
                                                          : Colors.teal)
                                                    : (Theme.of(
                                                                    context,
                                                                  ).brightness ==
                                                                  Brightness
                                                                      .dark
                                                              ? Colors
                                                                    .tealAccent
                                                              : Colors.teal)
                                                          .withValues(
                                                            alpha: 0.6,
                                                          ),
                                              ),
                                              minHeight: 6,
                                            ),
                                          ),
                                          // Phase 4: Score badge
                                          if (hasScore)
                                            _buildScoreBadge(score, context),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomSheet: StreamBuilder<List<Map<String, dynamic>>>(
        stream: ContentService().getContentSegments(contentId ?? importId),
        builder: (context, snapshot) {
          final lessons = snapshot.data ?? [];
          if (lessons.isEmpty) return const SizedBox.shrink();

          // Find logical "Continue" spot: Last opened uncompleted lesson.
          // last_position is a normalized 0-1 value for all lesson types.
          final incompleteLessons = lessons.where((l) {
            final double lastPos =
                (l['last_position'] as num?)?.toDouble() ?? 0.0;
            return lastPos < 0.99; // Not finished (< 99%)
          }).toList();

          final Map<String, dynamic> nextLesson;
          if (incompleteLessons.isNotEmpty) {
            // Sort by last_updated descending to find the "last opened" among uncompleted
            incompleteLessons.sort((a, b) {
              final aTime = a['last_updated'] as Timestamp?;
              final bTime = b['last_updated'] as Timestamp?;
              if (aTime == null) return 1;
              if (bTime == null) return -1;
              return bTime.compareTo(aTime);
            });
            nextLesson = incompleteLessons.first;
          } else {
            // If all are completed, or none have interaction yet, default to first or most recent
            final allLessons = List<Map<String, dynamic>>.from(lessons);
            allLessons.sort((a, b) {
              final aTime = a['last_updated'] as Timestamp?;
              final bTime = b['last_updated'] as Timestamp?;
              if (aTime == null) return 1;
              if (bTime == null) return -1;
              return bTime.compareTo(aTime);
            });
            nextLesson = allLessons.first;
          }

          final nextScore =
              (nextLesson['score'] as num?)?.toInt() ?? 0;

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                ),
              ),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(
                    onPressed: () =>
                        _handleLessonTap(context, nextLesson, importId),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 60),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 4,
                      shadowColor: Colors.teal.withValues(alpha: 0.4),
                    ),
                    child: Text(
                      'Continue Learning',
                      style: GoogleFonts.nunito(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  // Phase 4: Part score display in bottom sheet
                  if (nextScore > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Part Score: $nextScore',
                        style: GoogleFonts.nunito(
                          color: Colors.teal,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _handleLessonTap(
    BuildContext context,
    Map<String, dynamic> lesson,
    String importId,
  ) async {
    final userPrefs = UserPreferencesService();
    final language = await userPrefs.getCurrentLanguage();
    final nativeLang = await userPrefs.getNativeLanguage();
    final authService = Provider.of<AuthService>(context, listen: false);
    final userId = authService.currentUser?.uid ?? 'anonymous';

    if (!context.mounted) return;

    // Read the latest metadata from user_content instead of legacy import record.
    // Bridge the schema: user_content stores source_url inside metadata,
    // but downstream code expects it at the top level.
    final String targetContentId = contentId ?? importId;
    final latestContent = await ContentService().getContent(targetContentId);
    final Map<String, dynamic> actualImportItem;
    if (latestContent != null) {
      final meta = latestContent.metadata ?? <String, dynamic>{};
      actualImportItem = {
        'id': importId,
        'title': latestContent.title,
        'metadata': meta,
        'source_url': meta['source_url'],
      };
    } else {
      actualImportItem = importItem;
    }

    final bool isVideo = _isVideoImport(actualImportItem);

    if (!context.mounted) return;    // Prefer the original YouTube URL so we always resolve a fresh stream
    // on each visit (cached stream_url expires after ~6 hours).
    final String? sourceUrl = isVideo
        ? (actualImportItem['source_url'] ??
              actualImportItem['metadata']?['stream_url'] ??
              '')
        : null;
    final String? originalUrl = isVideo ? actualImportItem['source_url'] : null;

    if (!context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ImportedContentPage(
          importId: importId,
          contentId: contentId,
          lesson: lesson,
          userId: userId,
          language: language,
          nativeLanguage: nativeLang,
          sourceUrl: sourceUrl,
          originalUrl: originalUrl,
        ),
      ),
    );
  }
}

/// Streaming progress header widget that reactively updates when lesson
/// progress changes (from any session/tab), without re-building the entire
/// lesson list.
///
/// Uses duration-weighted averaging for timed segments (video) matching
/// ContentService._syncOverallProgress, and simple averaging for text-only
/// segments.
class _ProgressHeader extends StatefulWidget {
  final String contentId;
  final ContentService contentService;

  const _ProgressHeader({
    required this.contentId,
    required this.contentService,
  });

  @override
  State<_ProgressHeader> createState() => _ProgressHeaderState();
}

class _ProgressHeaderState extends State<_ProgressHeader> {
  /// Live segment metadata from the content stream. Subscribes to
  /// getContentSegments() so that re-segmentation (edit → re-segment)
  /// is reflected in the progress bar immediately.
  List<Map<String, dynamic>>? _segments;
  StreamSubscription<List<Map<String, dynamic>>>? _segmentsSub;

  @override
  void initState() {
    super.initState();
    _segmentsSub = widget.contentService
        .getContentSegments(widget.contentId)
        .listen((segments) {
      if (mounted) {
        setState(() => _segments = segments);
      }
    });
  }

  @override
  void dispose() {
    _segmentsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<int, Map<String, dynamic>>>(
      stream: widget.contentService.getLessonProgressStream(widget.contentId),
      builder: (context, progressSnapshot) {
        final progress = progressSnapshot.data ?? {};

        if (progress.isEmpty) {
          // No progress yet — hide the header entirely
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }

        // Compute overall progress from progress entries.
        // Uses duration-weighted averaging for timed segments, matching
        // ContentService._syncOverallProgress().
        double totalWatched = 0;
        double totalWeight = 0;
        double totalScore = 0;
        int scoredParts = 0;

        if (_segments != null && _segments!.isNotEmpty) {
          // Weighted average using segment durations (video) or equal weights (text)
          for (final segment in _segments!) {
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
                segment.containsKey('start_time') &&
                    segment.containsKey('end_time');

            if (hasTiming && startTime < endTime) {
              // Video segment: lastPos is 0-1 fraction, weight = duration
              final double duration = endTime - startTime;
              double watched = lastPos * duration;
              if (lastPos >= 0.99) watched = duration;
              totalWatched += watched;
              totalWeight += duration;
            } else {
              // Text segment or video segment with invalid timing data
              // (start >= end): fall back to weight=1 to avoid skewing
              // the average when mixed with timed segments.
              totalWatched += lastPos >= 0.99 ? 1.0 : lastPos;
              totalWeight += 1.0;
            }

            final score = (progressEntry['score'] as num?)?.toInt() ?? 0;
            if (score > 0) {
              totalScore += score;
              scoredParts++;
            }
          }
        } else {
          // Fallback: simple average (no segment timing data yet)
          for (final entry in progress.entries) {
            final lastPos =
                (entry.value['last_position'] as num?)?.toDouble() ?? 0.0;
            totalWatched += lastPos >= 0.99 ? 1.0 : lastPos;
            totalWeight += 1.0;

            final score = (entry.value['score'] as num?)?.toInt() ?? 0;
            if (score > 0) {
              totalScore += score;
              scoredParts++;
            }
          }
        }

        final overallProgress = totalWeight > 0
            ? (totalWatched / totalWeight).clamp(0.0, 1.0)
            : 0.0;
        final averageScore =
            scoredParts > 0 ? (totalScore / scoredParts).round() : null;

        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24.0, 8.0, 24.0, 24.0),
            child: _ProgressBar(
              overallProgress: overallProgress,
              averageScore: averageScore,
            ),
          ),
        );
      },
    );
  }
}

/// The actual progress bar UI (extracted for reuse).
class _ProgressBar extends StatelessWidget {
  final double overallProgress;
  final int? averageScore;

  const _ProgressBar({
    required this.overallProgress,
    this.averageScore,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Learning Progress',
                style: GoogleFonts.nunito(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(overallProgress * 100).toInt()}%',
                  style: GoogleFonts.nunito(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.teal,
                  ),
                ),
                if (averageScore != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.emoji_events_rounded,
                          size: 14,
                          color: Colors.teal,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Score: $averageScore',
                          style: GoogleFonts.nunito(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.teal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: overallProgress,
            minHeight: 10,
            backgroundColor: Colors.teal.withValues(alpha: 0.1),
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.teal),
          ),
        ),
      ],
    );
  }
}

/// Score badge widget shown on part cards after lessons are completed.
Widget _buildScoreBadge(int score, BuildContext context) {
  final Color badgeColor;
  if (score >= 80) {
    badgeColor = Colors.green;
  } else if (score >= 60) {
    badgeColor = Colors.orange;
  } else {
    badgeColor = Colors.redAccent;
  }

  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      children: [
        Icon(Icons.emoji_events_rounded, size: 16, color: badgeColor),
        const SizedBox(width: 4),
        Text(
          'Score: $score',
          style: GoogleFonts.nunito(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: badgeColor,
          ),
        ),
      ],
    ),
  );
}
