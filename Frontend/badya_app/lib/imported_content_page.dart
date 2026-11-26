import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:Badya/lesson_paths_page.dart';
import 'package:Badya/services/adk_service.dart';
import 'package:Badya/services/content_service.dart';
import 'package:Badya/services/definition_controller.dart';
import 'package:Badya/services/lesson_session_service.dart';
import 'package:Badya/services/user_preferences_service.dart';
import 'package:Badya/services/vocab_review_service.dart';
import 'package:Badya/utils/logger.dart';
import 'package:Badya/widgets/imported_text_view.dart';
import 'package:Badya/widgets/imported_video_view.dart';
import 'package:Badya/widgets/reader_settings_sheet.dart';

/// Coordinator page for imported content (videos, articles, book chapters).
/// Delegates rendering to [ImportedVideoView] for videos and [ImportedTextView]
/// for text, while managing shared definition lookups, reader settings,
/// and practice navigation.
class ImportedContentPage extends StatefulWidget {
  final String importId;
  final String? contentId;
  final Map<String, dynamic> lesson;
  final String userId;
  final String language;
  final String? nativeLanguage;
  final String? sourceUrl;
  final String? originalUrl;

  const ImportedContentPage({
    super.key,
    required this.importId,
    this.contentId,
    required this.lesson,
    required this.userId,
    this.nativeLanguage,
    this.sourceUrl,
    this.originalUrl,
    required this.language,
  });

  bool get isVideo =>
      sourceUrl != null ||
      (lesson['start_time'] != null && lesson['end_time'] != null);

  @override
  State<ImportedContentPage> createState() => _ImportedContentPageState();
}

class _ImportedContentPageState extends State<ImportedContentPage>
    with TickerProviderStateMixin {
  final GlobalKey<ImportedVideoViewState> _videoViewKey = GlobalKey();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // ─── Reader settings (shared) ──────────────────────────────────────────
  ReaderSettings _readerSettings = const ReaderSettings();

  // ─── Definition system (shared controller) ─────────────────────────────
  final DefinitionController _definitionController = DefinitionController();

  // ─── Progress & Completion ─────────────────────────────────────────────
  bool _isCompleted = false;
  double _highestProgressSent = 0.0;

  // ─── Practice button pulse animation ───────────────────────────────────
  late final AnimationController _practiceButtonPulseController;
  late final Animation<double> _practiceButtonPulseAnimation;

  @override
  void initState() {
    super.initState();
    _loadReaderSettings();
    _definitionController.initialize(
      userId: widget.userId,
      language: widget.language,
      topicId: widget.importId,
      lessonType: widget.isVideo
          ? LessonTypes.importedVideo
          : LessonTypes.importedText,
      cacheKey: 'definitions_${widget.lesson['id']}',
    );
    _definitionController.addListener(() {
      if (mounted) setState(() {});
    });

    _practiceButtonPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _practiceButtonPulseAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.15,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.15,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 50,
      ),
    ]).animate(_practiceButtonPulseController);
  }

  @override
  void deactivate() {
    _definitionController.saveHistory().catchError((e) {
      Logger.error('Error saving definition history in deactivate', e);
    });
    super.deactivate();
  }

  @override
  void dispose() {
    _definitionController.dispose();
    _practiceButtonPulseController.dispose();
    super.dispose();
  }

  void _handleAction(BuildContext context, String action, String text) {
    _definitionController.handleToolbarAction(
      context,
      action,
      text,
      userId: widget.userId,
      language: widget.language,
      nativeLanguage: widget.nativeLanguage,
      onOpenDrawer: () => _scaffoldKey.currentState?.openEndDrawer(),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // READER SETTINGS
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _loadReaderSettings() async {
    try {
      final userPrefs = UserPreferencesService();
      final settings = await userPrefs.getReaderSettings();
      if (mounted) {
        setState(() {
          _readerSettings = ReaderSettings.fromJson(settings);
        });
      }
    } catch (e) {
      Logger.warn('Failed to load reader settings: $e');
    }
  }

  void _updateReaderSettings(ReaderSettings settings) {
    setState(() => _readerSettings = settings);
    UserPreferencesService().updateReaderSettings(settings.toJson());
  }

  Future<void> _showReaderSettings() async {
    await showReaderSettingsSheet(
      context,
      current: _readerSettings,
      language: widget.language,
      onChanged: _updateReaderSettings,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PROGRESS TRACKING
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _markProgress(double progress) async {
    if (progress <= _highestProgressSent) return;
    _highestProgressSent = progress;
    try {
      final bool isNowCompleted = progress >= 0.99;
      final String effectiveContentId = widget.contentId ?? widget.importId;
      final orderIndex = widget.lesson['order_index'] as int? ?? 0;
      final contentService = ContentService();

      await contentService.updateLessonProgress(
        contentId: effectiveContentId,
        orderIndex: orderIndex,
        position: progress,
        immediateSync: isNowCompleted,
      );

      if (isNowCompleted && !_isCompleted) {
        await contentService.onPartCompleted(
          contentId: effectiveContentId,
          orderIndex: orderIndex,
        );
        _isCompleted = true;
        if (mounted) {
          _practiceButtonPulseController.forward();
        }
      }
    } catch (e) {
      Logger.error(
        'Failed to save progress for ${widget.contentId ?? widget.importId}',
        e,
      );
      if (progress >= 1.0) _isCompleted = false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // PRACTICE / QUIZ NAVIGATION
  // ═══════════════════════════════════════════════════════════════════════

  String _extractCleanContentText(String rawText) {
    if (widget.isVideo) {
      final videoTranscript = _videoViewKey.currentState?.plainTextTranscript;
      if (videoTranscript != null && videoTranscript.trim().isNotEmpty) {
        return videoTranscript;
      }
      if (rawText.trim().startsWith('[')) {
        try {
          final decoded = jsonDecode(rawText);
          if (decoded is List) {
            final parsed = decoded
                .map((item) => (item is Map && item['text'] != null)
                    ? item['text'].toString()
                    : '')
                .where((t) => t.trim().isNotEmpty)
                .join(' ');
            if (parsed.isNotEmpty) return parsed;
          }
        } catch (_) {}
      }
    }
    return rawText;
  }

  Future<void> _navigateToLessonPaths() async {
    if (widget.contentId == null) return;

    final orderIndex = widget.lesson['order_index'] as int? ?? 0;
    final topicId = '${widget.contentId}_part_$orderIndex';
    final subjectTitle =
        'Part ${orderIndex + 1}: ${widget.lesson['title']?.toString() ?? ''}';

    final contentService = ContentService();
    final content = await contentService.getContent(widget.contentId!);
    final contentLanguage = content?.language ?? widget.language;

    if (widget.isVideo) {
      _videoViewKey.currentState?.pause();
    }

    final rawText = (widget.lesson['text_content'] ?? '').toString();
    final cleanContentText = _extractCleanContentText(rawText);

    final vocabService = VocabReviewService();
    final scopeId = VocabReviewService.topicScopeId(topicId, contentLanguage);
    var wordStates = await vocabService.getAllWords(
      scope: VocabReviewService.scopeTopic,
      scopeId: scopeId,
    );
    var wordsList = wordStates.map((w) => w.word).toList();

    if (wordsList.isEmpty && cleanContentText.isNotEmpty) {
      final adkService = AdkService();
      final difficulty = content?.metadata?['difficulty'] as String? ?? 'intermediate';

      await adkService.generateAndCacheWords(
        topicId: topicId,
        subject: subjectTitle,
        description: cleanContentText.length > 200
            ? '${cleanContentText.substring(0, 200)}...'
            : cleanContentText,
        language: contentLanguage,
        difficulty: difficulty,
        userId: widget.userId,
      );

      wordStates = await vocabService.getAllWords(
        scope: VocabReviewService.scopeTopic,
        scopeId: scopeId,
      );
      wordsList = wordStates.map((w) => w.word).toList();
    }

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LessonPathsPage(
          subjectTitle: subjectTitle,
          description:
              content?.description ??
              (widget.lesson['title']?.toString() ?? ''),
          topicId: topicId,
          currentLanguage: contentLanguage,
          difficulty: content?.metadata?['difficulty'] as String? ?? 'intermediate',
          isImportedContent: true,
          importedContentId: widget.contentId,
          importedContentText: cleanContentText,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          if (widget.isVideo) {
            _videoViewKey.currentState?.saveProgress();
          }
          _definitionController.saveHistory().catchError((e) {
            Logger.error('Error saving definition history on pop', e);
          });
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        onEndDrawerChanged: (isOpen) {
          if (!isOpen) _definitionController.onDrawerClosed();
        },
        endDrawer: _definitionController.buildEndDrawer(
          onClose: () => _scaffoldKey.currentState?.closeEndDrawer(),
        ),
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text(
            widget.lesson['title']?.toString() ?? '',
            style: GoogleFonts.nunito(
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            if (widget.contentId != null)
              AnimatedBuilder(
                animation: _practiceButtonPulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _practiceButtonPulseAnimation.value,
                    child: Container(
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6C5CE7), Color(0xFFA29BFE)],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6C5CE7).withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: _navigateToLessonPaths,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.school_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Practice Lessons',
                                  style: GoogleFonts.nunito(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: widget.isVideo
              ? ImportedVideoView(
                  key: _videoViewKey,
                  importId: widget.importId,
                  contentId: widget.contentId,
                  lesson: widget.lesson,
                  userId: widget.userId,
                  language: widget.language,
                  nativeLanguage: widget.nativeLanguage,
                  sourceUrl: widget.sourceUrl,
                  originalUrl: widget.originalUrl,
                  readerSettings: _readerSettings,
                  onAction: _handleAction,
                  onDefinitionTap: () => _definitionController.openPanel(
                    () => _scaffoldKey.currentState?.openEndDrawer(),
                  ),
                  onFontTap: _showReaderSettings,
                  onProgressChanged: _markProgress,
                  onCompleted: () => _markProgress(1.0),
                )
              : ImportedTextView(
                  textContent: (widget.lesson['text_content'] ?? '').toString(),
                  readerSettings: _readerSettings,
                  onAction: _handleAction,
                  onDefinitionTap: () => _definitionController.openPanel(
                    () => _scaffoldKey.currentState?.openEndDrawer(),
                  ),
                  onFontTap: _showReaderSettings,
                  onProgressChanged: _markProgress,
                  onCompleted: () => _markProgress(1.0),
                ),
        ),
      ),
    );
  }
}
