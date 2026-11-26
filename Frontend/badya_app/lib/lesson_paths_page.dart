import 'dart:convert';
import 'package:Badya/config/local_mode.dart';
import 'package:Badya/services/content_service.dart';
import 'package:Badya/services/lesson_session_service.dart';
import 'package:Badya/services/adk_service.dart';
import 'package:Badya/services/coin_service.dart';
import 'package:Badya/services/user_preferences_service.dart';
import 'package:Badya/services/vocab_review_service.dart';
import 'package:Badya/models/transaction_model.dart';
import 'package:Badya/chat_page.dart';
import 'package:Badya/story_page.dart';
import 'package:Badya/video_page.dart';
import 'package:Badya/topic_words_page.dart';
import 'package:Badya/voice_chat_page.dart';
import 'package:Badya/widgets/custom_app_bar.dart';
import 'package:Badya/widgets/insufficient_balance_dialog.dart';
import 'package:Badya/wallet_page.dart';
import 'package:Badya/utils/score_service.dart' as score;
import 'package:Badya/utils/logger.dart';
import 'package:Badya/utils/ui_utils.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _wordSmithIconPath = 'assets/lessonsIcons/bookmount.png';
const String _storyWeaverIconPath = 'assets/lessonsIcons/chatIcon.png';
const String _echoChamberIconPath = 'assets/lessonsIcons/micmount.png';
const String _roleMasterIconPath = 'assets/lessonsIcons/rolemount.png';

class _LessonGuideItem {
  final String iconPath;
  final String title;
  final String tagline;
  final IconData fallbackIcon;
  final Color accentColor;
  final int coinCost;
  final int importedCoinCost;
  final String summary;
  final String? aiDetail;
  final String? importedDetail;

  const _LessonGuideItem({
    required this.iconPath,
    required this.title,
    required this.tagline,
    required this.fallbackIcon,
    required this.accentColor,
    required this.coinCost,
    required this.importedCoinCost,
    required this.summary,
    this.aiDetail,
    this.importedDetail,
  });
}

class LessonPathsPage extends StatefulWidget {
  final String subjectTitle;
  final String description;
  final String topicId;
  final String currentLanguage;
  final String difficulty;
  final String? topicImagePath;

  /// Whether this lesson was started from imported content.
  final bool isImportedContent;

  /// The parent user_content doc ID when [isImportedContent] is true.
  final String? importedContentId;

  /// The imported text or video transcript when [isImportedContent] is true.
  final String? importedContentText;

  const LessonPathsPage({
    super.key,
    required this.subjectTitle,
    required this.description,
    required this.topicId,
    required this.currentLanguage,
    this.difficulty = 'intermediate',
    this.topicImagePath,
    this.isImportedContent = false,
    this.importedContentId,
    this.importedContentText,
  });

  @override
  State<LessonPathsPage> createState() => _LessonPathsPageState();
}

class _LessonPathsPageState extends State<LessonPathsPage>
    with TickerProviderStateMixin {
  List<String> _words = [];

  /// True while [_loadWords] is fetching from Firestore. Prevents the badge
  /// from flashing "Generate Cards" during the initial async load.
  bool _wordsLoading = true;

  /// Guards against duplicate taps on any lesson-type button while
  /// session creation / payment is in flight.
  bool _isStartingLesson = false;

  /// False until the first open-session check finishes. Chips stay hidden
  /// so a path that already has a session does not flash its price.
  bool _openSessionsLoaded = false;

  /// Per-lesson badge visibility: true = show coin cost, false = hide.
  /// A chip is shown only when that path has no open ADK session.
  final Map<String, bool> _showCoinBadge = {
    LessonTypes.wordSmith: true,
    LessonTypes.storyWeaver: true,
    LessonTypes.echoChamber: true,
    LessonTypes.roleMaster: true,
  };

  /// Bumped per lesson type so a slow [sessionExists] cannot overwrite a
  /// newer hide or a newer sync for the same path.
  final Map<String, int> _sessionSyncTokens = {};

  static const List<String> _trackedLessonTypes = [
    LessonTypes.wordSmith,
    LessonTypes.storyWeaver,
    LessonTypes.echoChamber,
    LessonTypes.roleMaster,
  ];

  late AnimationController _shimmerController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  LessonSessionService get _sessionService => LessonSessionService();
  CoinService get _coinService => CoinService();

  /// App name whose session means this path is already in progress.
  /// Matches the app used when the path is started.
  String _appNameFor(String lessonType) {
    switch (lessonType) {
      case LessonTypes.wordSmith:
        return 'word_smith_agent';
      case LessonTypes.roleMaster:
        return 'role_master_agent';
      case LessonTypes.storyWeaver:
        return widget.isImportedContent ? 'text_chat' : 'story_agent';
      case LessonTypes.echoChamber:
        return widget.isImportedContent ? 'voice_chat' : 'video_agent';
      default:
        throw ArgumentError('Unknown lesson type: $lessonType');
    }
  }

  /// Hide this path's price as the user enters it, and invalidate any
  /// session check that started before the session was created.
  void _hideCoinBadge(String lessonType) {
    _sessionSyncTokens[lessonType] = (_sessionSyncTokens[lessonType] ?? 0) + 1;
    setState(() => _showCoinBadge[lessonType] = false);
  }

  /// Sets [_showCoinBadge] from [AdkService.sessionExists].
  /// Pass [only] to refresh a single path after its lesson route closes.
  Future<void> _syncOpenSessions({String? only}) async {
    final types = only == null ? _trackedLessonTypes : [only];
    final tokens = <String, int>{};
    for (final type in types) {
      final next = (_sessionSyncTokens[type] ?? 0) + 1;
      _sessionSyncTokens[type] = next;
      tokens[type] = next;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _openSessionsLoaded = true);
      return;
    }

    final adk = AdkService();
    final results = await Future.wait(types.map((type) async {
      try {
        final snapshot = _sessionService.getSession(
          topicId: widget.topicId,
          lessonType: type,
        );
        final targetSessionId = (type == LessonTypes.storyWeaver && !widget.isImportedContent)
            ? (snapshot.storySessionId ?? snapshot.sessionId)
            : snapshot.sessionId;
        final exists = await adk.sessionExists(
          appName: _appNameFor(type),
          userId: uid,
          sessionId: targetSessionId,
        );
        return MapEntry(type, exists);
      } catch (e) {
        Logger.warn('Failed to check open session for $type: $e');
        return null;
      }
    }));

    if (!mounted) return;
    setState(() {
      for (final entry in results) {
        if (entry == null) continue;
        if (_sessionSyncTokens[entry.key] != tokens[entry.key]) continue;
        _showCoinBadge[entry.key] = !entry.value;
      }
      _openSessionsLoaded = true;
    });
  }

  int? _pathCoinCost(String lessonType, ContentType contentType) {
    if (!_openSessionsLoaded || _showCoinBadge[lessonType] != true) {
      return null;
    }
    return contentType.costFor(isImportedContent: widget.isImportedContent);
  }

  @override
  void initState() {
    super.initState();
    _loadWords();
    // Show lesson guide on first visit, after the frame renders.
    // Session check runs in the same frame so price chips follow open sessions.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndShowGuideOnFirstVisit();
      _syncOpenSessions();
    });

    // Shimmer gradient animation — loops forever
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();

    // Subtle breathing pulse on the outer glow
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  /// Shows an immediate loading dialog and returns a [ValueNotifier] for
  /// updating the displayed message. The caller MUST dispose the notifier
  /// and pop the dialog when done.
  ValueNotifier<String> _showLoadingDialog(BuildContext context, String message) {
    final loadingStatus = ValueNotifier<String>(message);
    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return ValueListenableBuilder<String>(
            valueListenable: loadingStatus,
            builder: (context, msg, _) {
              return Center(
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 28,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(strokeWidth: 3),
                        const SizedBox(height: 20),
                        Text(
                          msg,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    }
    return loadingStatus;
  }

  Future<void> _loadWords() async {
    final vocabService = VocabReviewService();
    final scopeId = VocabReviewService.topicScopeId(
      widget.topicId,
      widget.currentLanguage,
    );
    final loadedWords = await vocabService.getAllWords(
      scope: VocabReviewService.scopeTopic,
      scopeId: scopeId,
    );
    if (mounted) {
      setState(() {
        _words = loadedWords.map((w) => w.word).toList();
      });
    }
  }

  /// Generate the topic word list using the AI word_generator_agent.
  /// Called when the user taps "Generate Cards" — shows a snackbar while
  /// generating, then refreshes the word list.
  Future<void> _generateWords() async {
    if (_words.isNotEmpty) return;

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ??
          ((LocalMode.enabled || kDebugMode) ? LocalMode.guestUid : null);
      if (uid == null) return;

      await AdkService().generateAndCacheWords(
        topicId: widget.topicId,
        subject: widget.subjectTitle,
        description: widget.description,
        language: widget.currentLanguage,
        difficulty: widget.difficulty,
        userId: uid,
      );

      await _loadWords();
    } catch (e) {
      if (mounted) {
        UiUtils.showErrorSnackbar(context, 'Word generation failed: $e');
      }
    }
  }

  /// Attempt to spend coins for a piece of content before starting the lesson.
  /// Returns true if spending succeeded or the content is free.
  Future<bool> _ensureContentPaid(
    BuildContext context, {
    required ContentType contentType,
    required String contentId,
    required String contentTitle,
    bool isImported = false,
  }) async {
    // Bypass Firebase Auth and coin checks in local/debug mode when unauthenticated.
    if (LocalMode.enabled ||
        (kDebugMode && FirebaseAuth.instance.currentUser == null)) {
      return true;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      UiUtils.showErrorSnackbar(context, 'User not authenticated');
      return false;
    }

    // Check if user can access this content
    final accessResult = await _coinService.canAccessContent(
      contentType,
      isImportedContent: isImported,
    );

    if (accessResult.canAccess) {
      // Spend the coins
      final spendResult = await _coinService.spendForContent(
        contentType,
        contentId,
        isImportedContent: isImported,
      );
      return spendResult.success;
    }

    // Not enough coins — show insufficient balance dialog
    if (context.mounted) {
      showInsufficientBalanceDialog(
        context: context,
        contentType: contentType,
        contentTitle: contentTitle,
        currentBalance: accessResult.currentBalance ?? 0,
        actualCost: accessResult.cost,
        onBuyCoins: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const WalletPage()),
          );
        },
        onViewStore: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const WalletPage()),
          );
        },
      );
    }
    return false;
  }

  Future<List<String>> _getTopicWords(
    String topicId,
    String uid,
    String language,
  ) async {
    final vocabService = VocabReviewService();
    final scopeId = VocabReviewService.topicScopeId(topicId, language);
    final words = await vocabService.getAllWords(
      scope: VocabReviewService.scopeTopic,
      scopeId: scopeId,
    );
    return words.map((w) => w.word).toList();
  }

  String? _cachedImportedText;

  Future<String> _getImportedContentText() async {
    if (_cachedImportedText != null && _cachedImportedText!.isNotEmpty) {
      return _cachedImportedText!;
    }
    if (widget.importedContentText != null &&
        widget.importedContentText!.isNotEmpty) {
      _cachedImportedText = widget.importedContentText;
      return _cachedImportedText!;
    }

    if (widget.importedContentId != null) {
      try {
        final lessons = await ContentService().getContentSegmentsOnce(
          widget.importedContentId!,
        );
        if (lessons.isNotEmpty) {
          final partIndexStr = widget.topicId.split('_part_').lastOrNull;
          final orderIndex = int.tryParse(partIndexStr ?? '') ?? 0;
          final lesson = lessons.firstWhere(
            (l) => (l['order_index'] as int? ?? 0) == orderIndex,
            orElse: () => lessons.first,
          );
          final rawText = (lesson['text_content'] ?? '').toString();
          if (rawText.trim().startsWith('[')) {
            try {
              final decoded = jsonDecode(rawText);
              if (decoded is List) {
                final parsed = decoded
                    .map(
                      (item) =>
                          (item is Map && item['text'] != null)
                              ? item['text'].toString()
                              : '',
                    )
                    .where((t) => t.trim().isNotEmpty)
                    .join(' ');
                if (parsed.isNotEmpty) {
                  _cachedImportedText = parsed;
                  return parsed;
                }
              }
            } catch (_) {}
          }
          _cachedImportedText = rawText;
          return rawText;
        }
      } catch (e) {
        Logger.warn('Failed to load fallback imported content text: $e');
      }
    }
    return widget.description;
  }

  Future<void> _startReadAndWrite(BuildContext context) async {
    if (_isStartingLesson) return;
    _isStartingLesson = true;

    try {
      final String uid =
          FirebaseAuth.instance.currentUser?.uid ?? 'default_user';
      final adkService = AdkService();

      // Check session existence first (no cost for resuming)
      // Show loading dialog immediately so the user gets instant feedback
      final loadingStatus = _showLoadingDialog(
        context,
        'Preparing your story lesson...',
      );

      final snapshot = _sessionService.getSession(
        topicId: widget.topicId,
        lessonType: LessonTypes.storyWeaver,
      );

      final String appName =
          widget.isImportedContent ? 'text_chat' : 'story_agent';

      final String resolvedSessionId = (!widget.isImportedContent && snapshot.storySessionId != null)
          ? snapshot.storySessionId!
          : snapshot.sessionId;

      final exists = await adkService.sessionExists(
        appName: appName,
        userId: uid,
        sessionId: resolvedSessionId,
      );

      String? sessionId = resolvedSessionId;
      bool isResuming = exists;

      // Only deduct coins for NEW sessions
      if (!isResuming) {
        final canProceed = await _ensureContentPaid(
          context,
          contentType: ContentType.storyWeaver,
          contentId: widget.topicId,
          contentTitle: widget.subjectTitle,
          isImported: widget.isImportedContent,
        );
        if (!canProceed) {
          loadingStatus.dispose();
          if (context.mounted) Navigator.pop(context);
          return;
        }
      }

      // Update dialog message based on state
      loadingStatus.value =
          isResuming ? 'Resuming your story...' : 'Preparing your story lesson...';

      try {
        final userPrefs = UserPreferencesService();
        final languageBase = await userPrefs.getCurrentLanguage();
        final dialects = await userPrefs.getLearningDialects();
        String language = languageBase;
        final dialect = dialects[languageBase] ?? '';
        if (dialect.isNotEmpty) {
          language = '$languageBase ($dialect)';
        }
        final nativeLanguage = await userPrefs.getNativeLanguage();
        final userId = uid;

        var wordsList = await _getTopicWords(
          widget.topicId,
          uid,
          widget.currentLanguage,
        );

        final performanceSummary =
            await score.ScoreService.getLatestPerformanceSummary(
              userId,
              widget.currentLanguage,
            );
        final languageLevel = await score.ScoreService.getLatestLanguageLevel(
          userId,
          widget.currentLanguage,
        );

        if (widget.isImportedContent) {
          // FOR IMPORTED CONTENT: Bypass story_agent & StoryPage.
          // Call text_chat directly with the imported content text!
          final contentText = await _getImportedContentText();

          if (!isResuming) {
            loadingStatus.value = 'Setting up your session...';
            final result = await adkService.createSession(
              appName: 'text_chat',
              userId: userId,
              sessionId: snapshot.sessionId,
              state: {
                'topic_id': widget.topicId,
                'story': contentText,
                'story_subject': widget.subjectTitle,
                'language': language,
                'words_list': wordsList.join(', '),
                'language_level': languageLevel ?? '',
                'difficulty': widget.difficulty,
                'description': widget.description,
              },
            );

            if (result == null) {
              throw Exception('Failed to create chat session');
            }
            sessionId = result.sessionId;
          }

          loadingStatus.dispose();
          if (!context.mounted) return;
          Navigator.pop(context);

          // Hide the coin badge — user is entering the lesson
          _hideCoinBadge(LessonTypes.storyWeaver);

          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatPage(
                appName: 'text_chat',
                sessionId: sessionId!,
                userId: userId,
                initialAgent: 'QuizPresenter',
                initialStory: contentText,
                storySubject: widget.subjectTitle,
                topicId: widget.topicId,
                language: language,
                nativeLanguage: nativeLanguage,
                description: widget.description,
                wordsList: wordsList,
                currentLanguage: widget.currentLanguage,
                lessonType: LessonTypes.storyWeaver,
              ),
            ),
          );
          if (mounted) {
            await _syncOpenSessions(only: LessonTypes.storyWeaver);
          }
          return;
        }

        if (!isResuming) {
          loadingStatus.value = 'Creating your story session...';
          final result = await adkService.createSession(
            appName: 'story_agent',
            userId: userId,
            sessionId: resolvedSessionId,
            state: {
              'story_subject': widget.subjectTitle,
              'description': widget.description,
              'language': language,
              'words_list': wordsList.join(', '),
              'language_level': languageLevel ?? '',
              'difficulty': widget.difficulty,
            },
          );

          if (result == null) throw Exception('Failed to create story session');
          sessionId = result.sessionId;
        }

        loadingStatus.value = 'Almost ready...';
        await Future.delayed(const Duration(seconds: 2));

        loadingStatus.dispose();
        if (!context.mounted) return;
        Navigator.pop(context);

        // Hide the coin badge — user is entering the lesson
        _hideCoinBadge(LessonTypes.storyWeaver);

        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => StoryPage(
              story: '',
              subjectTitle: widget.subjectTitle,
              sessionId: sessionId!,
              description: widget.description,
              topicId: widget.topicId,
              userId: userId,
              appName: 'story_agent',
              language: language,
              nativeLanguage: nativeLanguage,
              wordsList: wordsList,
            ),
          ),
        );
        if (mounted) {
          await _syncOpenSessions(only: LessonTypes.storyWeaver);
        }
      } catch (e) {
        loadingStatus.dispose();
        Logger.error('Error in _startReadAndWrite', e);
        if (!context.mounted) return;
        Navigator.pop(context);
        if (!context.mounted) return;
        UiUtils.showErrorSnackbar(context, 'Error: $e');
      }
    } finally {
      _isStartingLesson = false;
    }
  }

  Future<void> _startEchoChamber(BuildContext context) async {
    if (_isStartingLesson) return;
    _isStartingLesson = true;

    try {
      final String uid =
          FirebaseAuth.instance.currentUser?.uid ?? 'default_user';
      final adkService = AdkService();

      // Show loading dialog immediately so the user gets instant feedback
      final loadingStatus = _showLoadingDialog(
        context,
        'Preparing your video lesson...',
      );

      // Check session existence first (no cost for resuming)
      final snapshot = _sessionService.getSession(
        topicId: widget.topicId,
        lessonType: LessonTypes.echoChamber,
      );

      final String appName =
          widget.isImportedContent ? 'voice_chat' : 'video_agent';

      final exists = await adkService.sessionExists(
        appName: appName,
        userId: uid,
        sessionId: snapshot.sessionId,
      );

      String? sessionId = snapshot.sessionId;
      bool isResuming = exists;

      // Only deduct coins for NEW sessions
      if (!isResuming) {
        final canProceed = await _ensureContentPaid(
          context,
          contentType: ContentType.echoChamber,
          contentId: widget.topicId,
          contentTitle: widget.subjectTitle,
          isImported: widget.isImportedContent,
        );
        if (!canProceed) {
          loadingStatus.dispose();
          if (context.mounted) Navigator.pop(context);
          return;
        }
      }

      // Update dialog message based on state
      loadingStatus.value =
          isResuming ? 'Resuming your lesson...' : 'Preparing your video lesson...';

      try {
        final userPrefs = UserPreferencesService();
        final languageBase = await userPrefs.getCurrentLanguage();
        final dialects = await userPrefs.getLearningDialects();
        String language = languageBase;
        final dialect = dialects[languageBase] ?? '';
        if (dialect.isNotEmpty) {
          language = '$languageBase ($dialect)';
        }
        final nativeLanguage = await userPrefs.getNativeLanguage();
        final userId = uid;

        var wordsList = await _getTopicWords(
          widget.topicId,
          uid,
          widget.currentLanguage,
        );

        final performanceSummary =
            await score.ScoreService.getLatestPerformanceSummary(
              userId,
              widget.currentLanguage,
            );
        final languageLevel = await score.ScoreService.getLatestLanguageLevel(
          userId,
          widget.currentLanguage,
        );

        if (widget.isImportedContent) {
          // FOR IMPORTED CONTENT: Bypass video_agent & VideoPage.
          // Call voice_chat directly with the imported content text!
          final contentText = await _getImportedContentText();

          loadingStatus.dispose();
          if (!context.mounted) return;
          Navigator.pop(context);

          // Hide the coin badge — user is entering the lesson
          _hideCoinBadge(LessonTypes.echoChamber);

          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VoiceChatPage(
                subjectTitle: widget.subjectTitle,
                description: widget.description,
                agentName: 'Discussion Bot',
                appName: 'voice_chat',
                topicId: widget.topicId,
                storySubject: widget.subjectTitle,
                story: contentText,
                learningLanguage: language,
                nativeLanguage: nativeLanguage,
                userId: userId,
                wordsList: wordsList,
                currentLanguage: widget.currentLanguage,
                lessonType: LessonTypes.echoChamber,
                isImportedContent: true,
                importedContentId: widget.importedContentId,
              ),
            ),
          );
          if (mounted) {
            await _syncOpenSessions(only: LessonTypes.echoChamber);
          }
          return;
        }

        if (!isResuming) {
          loadingStatus.value = 'Setting up your video session...';
          final result = await adkService.createSession(
            appName: 'video_agent',
            userId: userId,
            sessionId: snapshot.sessionId,
            state: {
              'story_subject': widget.subjectTitle,
              'description': widget.description,
              'language': language,
              'words_list': wordsList.join(', '),
              'language_level': languageLevel ?? '',
              'difficulty': widget.difficulty,
            },
          );

          if (result == null) throw Exception('Failed to create video session');
          sessionId = result.sessionId;
        }

        loadingStatus.value = 'Almost ready...';
        await Future.delayed(const Duration(seconds: 2));

        loadingStatus.dispose();
        if (!context.mounted) return;
        Navigator.pop(context);

        // Hide the coin badge — user is entering the lesson
        _hideCoinBadge(LessonTypes.echoChamber);

        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VideoPage(
              subjectTitle: widget.subjectTitle,
              description: widget.description,
              topicId: widget.topicId,
              sessionId: sessionId!,
              userId: userId,
              appName: 'video_agent',
              language: language,
              nativeLanguage: nativeLanguage,
              wordsList: wordsList,
            ),
          ),
        );
        if (mounted) {
          await _syncOpenSessions(only: LessonTypes.echoChamber);
        }
      } catch (e) {
        loadingStatus.dispose();
        Logger.error('Error in _startEchoChamber', e);
        if (!context.mounted) return;
        Navigator.pop(context);
        if (!context.mounted) return;
        UiUtils.showErrorSnackbar(context, 'Error: $e');
      }
    } finally {
      _isStartingLesson = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          CustomAppBar(
            title: widget.subjectTitle,
            showMenuButton: false,
            showLanguageButton: false,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: _showLessonGuideDialog,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.help_outline_rounded,
                              size: 16,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Guide',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          SliverToBoxAdapter(child: _buildTopSection(context)),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Row 1: Word Smith
                _buildCompactPathNode(
                  context,
                  imagePath: _wordSmithIconPath,
                  coinCost: _pathCoinCost(
                    LessonTypes.wordSmith,
                    ContentType.wordSmith,
                  ),
                  onTap: () async {
                    if (_isStartingLesson) return;
                    _isStartingLesson = true;

                    try {
                    final String uid =
                        FirebaseAuth.instance.currentUser?.uid ??
                        'default_user';
                    final adkService = AdkService();

                    // Show loading dialog immediately so the user gets instant feedback
                    final loadingStatus = _showLoadingDialog(
                      context,
                      'Preparing your word lesson...',
                    );

                    // Check session existence first (no cost for resuming)
                    final snapshot = _sessionService.getSession(
                      topicId: widget.topicId,
                      lessonType: LessonTypes.wordSmith,
                    );

                    final exists = await adkService.sessionExists(
                      appName: 'word_smith_agent',
                      userId: uid,
                      sessionId: snapshot.sessionId,
                    );

                    String? sessionId = snapshot.sessionId;
                    bool isResuming = exists;

                    // Only deduct coins for NEW sessions
                    if (!isResuming) {
                      final canProceed = await _ensureContentPaid(
                        context,
                        contentType: ContentType.wordSmith,
                        contentId: widget.topicId,
                        contentTitle: widget.subjectTitle,
                        isImported: widget.isImportedContent,
                      );
                      if (!canProceed) {
                        loadingStatus.dispose();
                        if (context.mounted) Navigator.pop(context);
                        return;
                      }
                    }

                    final wordsList = await _getTopicWords(
                      widget.topicId,
                      uid,
                      widget.currentLanguage,
                    );

                    final performanceSummary =
                        await score.ScoreService.getLatestPerformanceSummary(
                          uid,
                          widget.currentLanguage,
                        );
                    final languageLevel =
                        await score.ScoreService.getLatestLanguageLevel(
                          uid,
                          widget.currentLanguage,
                        );

                    if (!isResuming) {
                      loadingStatus.value = 'Setting up your session...';
                      try {
                        final result = await adkService.createSession(
                          appName: 'word_smith_agent',
                          userId: uid,
                          sessionId: snapshot.sessionId,
                          state: {
                            'story_subject': widget.subjectTitle,
                            'words_list': wordsList.join(', '),
                            'language': widget.currentLanguage,
                            'language_level': languageLevel ?? '',
                            'difficulty': widget.difficulty,
                          },
                        );
                        sessionId = result?.sessionId;
                      } catch (e) {
                        loadingStatus.dispose();
                        if (context.mounted) {
                          Navigator.pop(context);
                          UiUtils.showErrorSnackbar(
                            context,
                            'Backend unavailable: $e',
                          );
                        }
                        return;
                      }
                    }

                    loadingStatus.dispose();

                    if (!context.mounted) return;
                    Navigator.pop(context);

                    if (sessionId == null) {
                      UiUtils.showErrorSnackbar(context, 'Failed to create session');
                      return;
                    }

                    // Hide the coin badge — user is entering the lesson
                    _hideCoinBadge(LessonTypes.wordSmith);

                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => VoiceChatPage(
                          subjectTitle: widget.subjectTitle,
                          storySubject: widget.subjectTitle,
                          description: widget.description,
                          agentName: 'Word Smith',
                          appName: 'word_smith_agent',
                          topicId: widget.topicId,
                          userId: uid,
                          wordsList: wordsList,
                          currentLanguage: widget.currentLanguage,
                          lessonType: LessonTypes.wordSmith,
                          isImportedContent: widget.isImportedContent,
                          importedContentId: widget.importedContentId,
                        ),
                      ),
                    );
                    if (mounted) {
                      await _syncOpenSessions(only: LessonTypes.wordSmith);
                    }
                    } finally {
                      _isStartingLesson = false;
                    }
                  },
                ),

                const SizedBox(height: 12),

                // Row 2: Story Weaver & Echo Chamber
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildCompactPathNode(
                      context,
                      imagePath: _storyWeaverIconPath,
                      coinCost: _pathCoinCost(
                        LessonTypes.storyWeaver,
                        ContentType.storyWeaver,
                      ),
                      onTap: () => _startReadAndWrite(context),
                    ),
                    const SizedBox(width: 40),
                    _buildCompactPathNode(
                      context,
                      imagePath: _echoChamberIconPath,
                      coinCost: _pathCoinCost(
                        LessonTypes.echoChamber,
                        ContentType.echoChamber,
                      ),
                      onTap: () => _startEchoChamber(context),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Row 3: Role Master
                _buildCompactPathNode(
                  context,
                  imagePath: _roleMasterIconPath,
                  coinCost: _pathCoinCost(
                    LessonTypes.roleMaster,
                    ContentType.roleMaster,
                  ),
                  onTap: () async {
                    if (_isStartingLesson) return;
                    _isStartingLesson = true;

                    try {
                    final String uid =
                        FirebaseAuth.instance.currentUser?.uid ??
                        'default_user';
                    final adkService = AdkService();

                    // Show loading dialog immediately so the user gets instant feedback
                    final loadingStatus = _showLoadingDialog(
                      context,
                      'Preparing your lesson...',
                    );

                    // Check session existence first (no cost for resuming)
                    final snapshot = _sessionService.getSession(
                      topicId: widget.topicId,
                      lessonType: LessonTypes.roleMaster,
                    );

                    final exists = await adkService.sessionExists(
                      appName: 'role_master_agent',
                      userId: uid,
                      sessionId: snapshot.sessionId,
                    );

                    String? sessionId = snapshot.sessionId;
                    bool isResuming = exists;

                    // Only deduct coins for NEW sessions
                    if (!isResuming) {
                      final canProceed = await _ensureContentPaid(
                        context,
                        contentType: ContentType.roleMaster,
                        contentId: widget.topicId,
                        contentTitle: widget.subjectTitle,
                        isImported: widget.isImportedContent,
                      );
                      if (!canProceed) {
                        loadingStatus.dispose();
                        if (context.mounted) Navigator.pop(context);
                        return;
                      }
                    }

                    final wordsList = await _getTopicWords(
                      widget.topicId,
                      uid,
                      widget.currentLanguage,
                    );

                    final performanceSummary =
                        await score.ScoreService.getLatestPerformanceSummary(
                          uid,
                          widget.currentLanguage,
                        );
                    final languageLevel =
                        await score.ScoreService.getLatestLanguageLevel(
                          uid,
                          widget.currentLanguage,
                        );

                    if (!isResuming) {
                      try {
                        // Step 1: Generate scenario via standalone scenario_writer_agent
                        loadingStatus.value = 'Generating scenario...';
                        final scenario = await adkService.runScenarioWriter(
                          userId: uid,
                          topicSubject: widget.subjectTitle,
                          wordsList: wordsList,
                          language: widget.currentLanguage,
                          languageLevel: languageLevel ?? '',
                          difficulty: widget.difficulty,
                          description: widget.description,
                        );

                        if (scenario == null || scenario.isEmpty) {
                          loadingStatus.dispose();
                          if (context.mounted) {
                            Navigator.pop(context); // dismiss dialog
                            UiUtils.showErrorSnackbar(context, 'Failed to generate scenario. Please try again.');
                          }
                          return;
                        }

                        // Step 2: Create role_master session with the scenario
                        loadingStatus.value = 'Setting up role play session...';
                        final result = await adkService.createSession(
                          appName: 'role_master_agent',
                          userId: uid,
                          sessionId: snapshot.sessionId,
                          state: {
                            'story_subject': widget.subjectTitle,
                            'description': widget.description,
                            'words_list': wordsList.join(', '),
                            'language': widget.currentLanguage,
                            'language_level': languageLevel ?? '',
                            'difficulty': widget.difficulty,
                            'scenario': scenario,
                          },
                        );
                        sessionId = result?.sessionId;
                      } catch (e) {
                        loadingStatus.dispose();
                        if (context.mounted) {
                          Navigator.pop(context);
                          UiUtils.showErrorSnackbar(
                            context,
                            'Backend unavailable: $e',
                          );
                        }
                        return;
                      }
                    }

                    loadingStatus.dispose();

                    if (!context.mounted) return;
                    Navigator.pop(context);

                    if (sessionId == null) {
                      UiUtils.showErrorSnackbar(context, 'Failed to create session');
                      return;
                    }

                    // Hide the coin badge — user is entering the lesson
                    _hideCoinBadge(LessonTypes.roleMaster);

                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => VoiceChatPage(
                          subjectTitle: widget.subjectTitle,
                          storySubject: widget.subjectTitle,
                          description: widget.description,
                          agentName: 'Role Master',
                          appName: 'role_master_agent',
                          topicId: widget.topicId,
                          userId: uid,
                          wordsList: wordsList,
                          currentLanguage: widget.currentLanguage,
                          lessonType: LessonTypes.roleMaster,
                          isImportedContent: widget.isImportedContent,
                          importedContentId: widget.importedContentId,
                        ),
                      ),
                    );
                    if (mounted) {
                      await _syncOpenSessions(only: LessonTypes.roleMaster);
                    }
                    } finally {
                      _isStartingLesson = false;
                    }
                  }
                ),

                const SizedBox(height: 60),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ─── TOPIC IMAGE ──────────────────────────────────────────────

  Widget _buildTopSection(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasImage =
        widget.topicImagePath != null && widget.topicImagePath!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF222220) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? const Color(0x22FFFFFF) : const Color(0x1A2D3436),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(
              0xFF2D3436,
            ).withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasImage)
            SizedBox(
              width: double.infinity,
              height: 160,
              child: Hero(
                tag: 'topic-image-${widget.topicId}',
                child: widget.topicImagePath!.startsWith('http')
                    ? Image.network(
                        widget.topicImagePath!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _imageFallback(context),
                      )
                    : Image.asset(
                        widget.topicImagePath!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _imageFallback(context),
                      ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                _buildWordCountBadge(),
                const Spacer(),
                _words.isEmpty
                    ? _buildFancyIconButton(
                        icon: Icons.auto_awesome_rounded,
                        color: const Color(0xFF9B59B6),
                        onTap: _generateWords,
                      )
                    : _buildFancyIconButton(
                        icon: Icons.edit_rounded,
                        color: const Color(0xFFFF6B6B),
                        onTap: _navigateToWordsPage,
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _imageFallback(BuildContext context) {
    return Container(
      color: Theme.of(context).cardTheme.color,
      child: Icon(
        Icons.image_not_supported_rounded,
        size: 40,
        color: Theme.of(context).iconTheme.color,
      ),
    );
  }

  Widget _buildWordCountBadge() {
    return GestureDetector(
      onTap: _words.isEmpty ? _generateWords : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _words.isEmpty
              ? const Color(0xFF9B59B6).withValues(alpha: 0.1)
              : const Color(0xFFFF6B6B).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _words.isEmpty
                  ? Icons.auto_awesome_rounded
                  : Icons.style_rounded,
              size: 16,
              color: _words.isEmpty
                  ? const Color(0xFF9B59B6)
                  : const Color(0xFFFF6B6B),
            ),
            const SizedBox(width: 6),
            Text(
              _words.isEmpty ? 'Generate Cards' : '${_words.length} Cards',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _words.isEmpty
                    ? const Color(0xFF9B59B6)
                    : const Color(0xFFFF6B6B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFancyIconButton({
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Center(child: Icon(icon, size: 18, color: color)),
      ),
    );
  }

  void _navigateToWordsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TopicWordsPage(
          subjectTitle: widget.subjectTitle,
          topicId: widget.topicId,
          description: widget.description,
          currentLanguage: widget.currentLanguage,
        ),
      ),
    ).then((_) => _loadWords());
  }

  // ─── LESSON GUIDE DIALOG ──────────────────────────────────────

  static const String _guideSeenKey = 'lesson_types_guide_seen';

  Future<void> _checkAndShowGuideOnFirstVisit() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(_guideSeenKey) ?? false;
    if (!seen && mounted) {
      _showLessonGuideDialog(markAsSeen: true);
    }
  }

  void _showLessonGuideDialog({bool markAsSeen = false}) {
    final guideItems = [
      _LessonGuideItem(
        iconPath: _wordSmithIconPath,
        title: 'Word Smith',
        tagline: 'Vocabulary & Sentences',
        fallbackIcon: Icons.record_voice_over_rounded,
        accentColor: const Color(0xFF9B59B6),
        coinCost: ContentType.wordSmith.coinCost,
        importedCoinCost: ContentType.wordSmith.importedCoinCost,
        summary:
            'Memorize words and sentences by putting them to use in practical examples and real speech.',
        aiDetail: 'Converses using vocabulary from topic cards and gives real-time feedback.',
        importedDetail:
            'Practices vocabulary extracted directly from your imported media or documents.',
      ),
      _LessonGuideItem(
        iconPath: _storyWeaverIconPath,
        title: 'Story Weaver',
        tagline: 'Reading Comprehension',
        fallbackIcon: Icons.auto_stories_rounded,
        accentColor: const Color(0xFF2196F3),
        coinCost: ContentType.storyWeaver.coinCost,
        importedCoinCost: ContentType.storyWeaver.importedCoinCost,
        summary:
            'Dedicated to reading comprehension through interactive story and dialogue testing.',
        aiDetail:
            'Generates a story first, then tests your understanding in an interactive chat.',
        importedDetail:
            'Skips generation and takes you directly to the chat to test understanding.',
      ),
      _LessonGuideItem(
        iconPath: _echoChamberIconPath,
        title: 'Echo Chamber',
        tagline: 'Listening & Pronunciation',
        fallbackIcon: Icons.hearing_rounded,
        accentColor: const Color(0xFFFF6B6B),
        coinCost: ContentType.echoChamber.coinCost,
        importedCoinCost: ContentType.echoChamber.importedCoinCost,
        summary:
            'Dedicated to listening and voice repetition with instant pronunciation feedback.',
        aiDetail:
            'Generates an audio story first, then tests your understanding in a voice conversation.',
        importedDetail:
            'Skips generation and takes you directly to the voice conversation.',
      ),
      _LessonGuideItem(
        iconPath: _roleMasterIconPath,
        title: 'Role Master',
        tagline: 'Real-World Role Play',
        fallbackIcon: Icons.theater_comedy_rounded,
        accentColor: const Color(0xFF10B981),
        coinCost: ContentType.roleMaster.coinCost,
        importedCoinCost: ContentType.roleMaster.importedCoinCost,
        summary:
            'Simulate real-life conversations (ordering food, interviews, negotiations) in a safe environment. Works identically for both AI and imported lessons.',
      ),
    ];

    final pageController = PageController();
    int currentPage = 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (markAsSeen) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool(_guideSeenKey, true);
          }
          if (sheetContext.mounted) Navigator.pop(sheetContext);
        },
        child: StatefulBuilder(
          builder: (innerContext, setModalState) {
            final isDark = Theme.of(innerContext).brightness == Brightness.dark;
            final textPrimary = Theme.of(innerContext).textTheme.titleLarge?.color;
            final textMuted = Theme.of(innerContext)
                .textTheme
                .bodySmall
                ?.color
                ?.withValues(alpha: 0.7);

            return Container(
              height: MediaQuery.of(sheetContext).size.height * 0.72,
              decoration: BoxDecoration(
                color: Theme.of(sheetContext).scaffoldBackgroundColor,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                children: [
                  // Drag handle
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 6),
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Header with close icon
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 16, 4),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.auto_awesome_rounded,
                            size: 18,
                            color: Color(0xFF6366F1),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Lesson Types Guide',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: textPrimary,
                                ),
                              ),
                              Text(
                                'Swipe horizontally to explore paths',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () async {
                            if (markAsSeen) {
                              final prefs =
                                  await SharedPreferences.getInstance();
                              await prefs.setBool(_guideSeenKey, true);
                            }
                            if (sheetContext.mounted) Navigator.pop(sheetContext);
                          },
                          icon: const Icon(Icons.close_rounded, size: 20),
                          visualDensity: VisualDensity.compact,
                          color: textMuted,
                        ),
                      ],
                    ),
                  ),

                  // Horizontal PageView for paths
                  Expanded(
                    child: PageView.builder(
                      controller: pageController,
                      itemCount: guideItems.length,
                      physics: const BouncingScrollPhysics(),
                      onPageChanged: (index) {
                        setModalState(() {
                          currentPage = index;
                        });
                      },
                      itemBuilder: (context, index) {
                        final item = guideItems[index];
                        return _buildGuidePageViewItem(
                          item: item,
                          isDark: isDark,
                          textPrimary: textPrimary,
                          textMuted: textMuted,
                        );
                      },
                    ),
                  ),

                  // Page Indicator Dots
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(guideItems.length, (index) {
                        final isSelected = index == currentPage;
                        final activeColor = guideItems[currentPage].accentColor;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: isSelected ? 22 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? activeColor
                                : (isDark ? Colors.white24 : Colors.black12),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        );
                      }),
                    ),
                  ),

                  // Bottom actions: Got it / Next
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: Row(
                      children: [
                        if (currentPage > 0)
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: IconButton.filledTonal(
                              onPressed: () {
                                pageController.previousPage(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeInOut,
                                );
                              },
                              icon: const Icon(Icons.arrow_back_rounded, size: 20),
                              style: IconButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: FilledButton(
                              onPressed: () async {
                                if (currentPage < guideItems.length - 1) {
                                  pageController.nextPage(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeInOut,
                                  );
                                } else {
                                  if (markAsSeen) {
                                    final prefs =
                                        await SharedPreferences.getInstance();
                                    await prefs.setBool(_guideSeenKey, true);
                                  }
                                  if (sheetContext.mounted) {
                                    Navigator.pop(sheetContext);
                                  }
                                }
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor:
                                    guideItems[currentPage].accentColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                              child: Text(
                                currentPage < guideItems.length - 1
                                    ? 'Next (${currentPage + 1}/${guideItems.length})'
                                    : 'Got it!',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildGuidePageViewItem({
    required _LessonGuideItem item,
    required bool isDark,
    required Color? textPrimary,
    required Color? textMuted,
  }) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF202022) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: item.accentColor.withValues(alpha: isDark ? 0.25 : 0.15),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: item.accentColor.withValues(alpha: isDark ? 0.08 : 0.06),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Centered icon in glowing circular container
            Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    item.accentColor.withValues(alpha: 0.22),
                    item.accentColor.withValues(alpha: 0.04),
                  ],
                ),
                border: Border.all(
                  color: item.accentColor.withValues(alpha: 0.35),
                  width: 2,
                ),
              ),
              child: Center(
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: Image.asset(
                    item.iconPath,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Icon(
                      item.fallbackIcon,
                      size: 34,
                      color: item.accentColor,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Title & Tagline
            Text(
              item.title,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.tagline,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: item.accentColor,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 12),

            // Costs row chips
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildCoinCostChip(item.coinCost, item.accentColor, 'AI'),
                const SizedBox(width: 8),
                _buildCoinCostChip(
                  item.importedCoinCost,
                  const Color(0xFF10B981),
                  'Imported',
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Compressed Core summary
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: item.accentColor.withValues(alpha: isDark ? 0.12 : 0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                item.summary,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                  color: textPrimary,
                ),
              ),
            ),
            // Compressed AI vs Imported row (if applicable)
            if (item.aiDetail != null && item.importedDetail != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildMiniSourceBlock(
                      label: 'AI-Generated',
                      text: item.aiDetail!,
                      icon: Icons.auto_awesome_rounded,
                      color: const Color(0xFF6366F1),
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMiniSourceBlock(
                      label: 'Imported',
                      text: item.importedDetail!,
                      icon: Icons.upload_file_rounded,
                      color: const Color(0xFF10B981),
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMiniSourceBlock({
    required String label,
    required String text,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.1 : 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            text,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.color
                  ?.withValues(alpha: 0.8),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoinCostChip(int cost, Color color, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.monetization_on_outlined,
            size: 11,
            color: color,
          ),
          const SizedBox(width: 2),
          Text(
            '$cost',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: color.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  // ─── COMPACT PATH NODE (Circular Image) ───────────────────────

  Widget _buildCompactPathNode(
    BuildContext context, {
    required String imagePath,
    required VoidCallback onTap,
    int? coinCost,
  }) {
    const double imageSize = 100;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: imageSize,
            height: imageSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  isDark ? Colors.white10 : Colors.white,
                  isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.grey.shade100,
                ],
              ),
            ),
            padding: const EdgeInsets.all(12),
            child: Image.asset(
              imagePath,
              width: imageSize - 24,
              height: imageSize - 24,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.image, size: 30),
                );
              },
            ),
          ),
        ),
        if (coinCost != null) ...[
          const SizedBox(height: 8),
          Builder(
            builder: (context) {
              final coinColor = isDark
                  ? const Color(0xFFFFD93D)
                  : const Color(0xFFF5A623);
              final coinTextColor = isDark
                  ? const Color(0xFFFFD93D)
                  : const Color(0xFF2A2A28);
              final coinBorderColor = isDark
                  ? const Color(0xFFFFD93D).withValues(alpha: 0.25)
                  : const Color(0x1A2D3436);

              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    stops: const [0.0, 0.5, 1.0],
                    colors: [
                      isDark
                          ? const Color(0xFF2A2A28)
                          : const Color(0xFFF8F6F3),
                      isDark
                          ? const Color(0xFF222220)
                          : const Color(0xFFF3EFE9),
                      isDark
                          ? const Color(0xFF2A2A28)
                          : const Color(0xFFF8F6F3),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: coinBorderColor, width: 1.0),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      const IconData(0xe800, fontFamily: 'MyFlutterApp'),
                      size: 20,
                      color: coinColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$coinCost',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: coinTextColor,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}
