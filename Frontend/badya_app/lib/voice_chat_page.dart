import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:async';

import 'package:Badya/lesson_completion_page.dart';
import 'package:Badya/services/adk_service.dart';
import 'package:Badya/services/content_service.dart';
import 'package:Badya/services/lesson_session_service.dart';
import 'package:Badya/services/user_preferences_service.dart';
import 'package:Badya/services/vocab_review_service.dart';
import 'package:Badya/services/voice_service.dart';
import 'package:Badya/utils/ui_utils.dart';
import 'package:Badya/utils/score_service.dart' as score;
import 'package:Badya/utils/logger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'widgets/assistant_chat_panel.dart';
import 'widgets/custom_selection_toolbar.dart';
import 'package:google_fonts/google_fonts.dart';

class VoiceChatPage extends StatefulWidget {
  final String subjectTitle;
  final String description;
  final String agentName;
  final String appName;
  final String topicId;
  final String? storySubject;
  final String? story;
  final String? analysisResult;
  final String? learningLanguage;
  final String? nativeLanguage;
  final String userId;
  final List<String>? wordsList;
  final List<String>? sessionIdsToDelete;
  final String currentLanguage;

  /// Whether this lesson was started from imported content.
  final bool isImportedContent;

  /// The parent user_content doc ID when [isImportedContent] is true.
  final String? importedContentId;

  const VoiceChatPage({
    super.key,
    required this.subjectTitle,
    required this.description,
    this.agentName = 'AI Tutor',
    required this.appName,
    required this.topicId,
    this.storySubject,
    this.story,
    this.analysisResult,
    this.learningLanguage,
    this.nativeLanguage,
    required this.userId,
    this.wordsList,
    this.sessionIdsToDelete,
    required this.currentLanguage,
    required this.lessonType,
    this.isImportedContent = false,
    this.importedContentId,
  });

  final String lessonType;

  @override
  State<VoiceChatPage> createState() => _VoiceChatPageState();
}

class _VoiceChatPageState extends State<VoiceChatPage>
    with TickerProviderStateMixin {
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _showCaptions = false;
  late AnimationController _waveController;
  late AnimationController _visualizerController;
  late AnimationController _colorShiftController;
  late AnimationController _pulseController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String? _latestAssistantMessage;
  bool _showAssistantBubble = false;

  final VoiceService _voiceService = VoiceService();
  final AdkService _adkService = AdkService();
  final LessonSessionService _sessionService = LessonSessionService();
  String? _sessionId;
  late final String _userId;
  bool _isConnecting = true;

  // Volume State
  final ValueNotifier<double> _userVolume = ValueNotifier(0.0);
  final ValueNotifier<double> _botVolume = ValueNotifier(0.0);
  final ValueNotifier<bool> _isVoiceActive = ValueNotifier(false);

  // Assistant Data
  final List<Map<String, String>> _assistantMessages = [];

  // Chat/Caption Data
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];

  String? _selectedText;

  @override
  void initState() {
    super.initState();
    _userId = widget.userId;

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    _visualizerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Color shift animation for user speaking
    _colorShiftController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    // Pulse animation for mic button
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    // Listen to volume streams
    _voiceService.userVolume.listen((vol) {
      if (mounted) _userVolume.value = vol;
    });

    _voiceService.botVolume.listen((vol) {
      if (mounted) _botVolume.value = vol;
    });

    _voiceService.voiceActivity.listen((isActive) {
      if (mounted) _isVoiceActive.value = isActive;
    });

    _initVoiceChat();
  }

  Future<void> _initVoiceChat() async {
    final userPrefs = UserPreferencesService();
    List<String> words = widget.wordsList ?? [];
    if (words.isEmpty && !widget.topicId.startsWith('strange_words_')) {
      final vocabService = VocabReviewService();
      final scopeId = VocabReviewService.topicScopeId(
        widget.topicId,
        widget.currentLanguage,
      );
      final loadedWords = await vocabService.getAllWords(
        scope: VocabReviewService.scopeTopic,
        scopeId: scopeId,
      );
      words = loadedWords.map((w) => w.word).toList();
    }

    final languageBase =
        widget.learningLanguage ?? await userPrefs.getCurrentLanguage();
    final dialects = await userPrefs.getLearningDialects();
    String learningLanguage = languageBase;
    final dialect = dialects[languageBase] ?? '';
    if (dialect.isNotEmpty) {
      learningLanguage = '$languageBase ($dialect)';
    }
    final nativeLanguage =
        widget.nativeLanguage ?? await userPrefs.getNativeLanguage();

    // ------------------------------------------------------------------
    // Determine the lesson-type key for this voice agent
    // ------------------------------------------------------------------
    final lessonType = _lessonTypeKey();

    // ------------------------------------------------------------------
    // 1. Deterministic session discovery
    // ------------------------------------------------------------------
    final snapshot = _sessionService.getSession(
      topicId: widget.topicId,
      lessonType: widget.lessonType,
    );

    // ------------------------------------------------------------------
    // Fetch SRS state for the word_smith_agent
    // ------------------------------------------------------------------
    String? wordsSrsStateJson;

    if (widget.appName == 'word_smith_agent') {
      // Try to fetch existing SRS state from the source document
      try {
        final sourceDocId = widget.topicId.startsWith('strange_words_')
            ? widget
                  .currentLanguage // strange_words/{language}
            : '${widget.topicId}_${widget.currentLanguage}'; // topics/{topicId}_{language}

        final sourceCollection = widget.topicId.startsWith('strange_words_')
            ? 'strange_words'
            : 'topics';

        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(_userId)
            .collection(sourceCollection)
            .doc(sourceDocId)
            .get();

        if (doc.exists && doc.data() != null) {
          final wordMap = doc.data()!['words'];
          if (wordMap is Map) {
            wordsSrsStateJson = jsonEncode(wordMap);
          } else if (wordMap == null) {
            // Fallback: flat dotted keys like "words.apple.score"
            final flat = VocabReviewService.extractWordsFromFlatKeys(
              doc.data()!,
            );
            if (flat != null) {
              wordsSrsStateJson = jsonEncode(flat);
            }
          }
          // If neither format matched, leave as null (agent defaults to teach mode).
        }
      } catch (e) {
        Logger.warn('VoiceChatPage: Could not fetch SRS state: $e');
      }
    }

    // Fetch adaptive context
    final performanceSummary =
        await score.ScoreService.getLatestPerformanceSummary(
          _userId,
          widget.currentLanguage,
        );
    final languageLevel = await score.ScoreService.getLatestLanguageLevel(
      _userId,
      widget.currentLanguage,
    );

    // 2. Try to create session (if exists, it will return wasResumed: true)
    SessionCreationResult? result;
    try {
      result = await _adkService.createSession(
        appName: widget.appName,
        userId: _userId,
        sessionId: snapshot.sessionId,
        state: {
          'story_subject': widget.storySubject ?? widget.subjectTitle,
          'description': widget.description,
          'words_list': words.join(', '),
          'language': learningLanguage,
          'language_level': languageLevel ?? '',
          if (widget.story != null) 'story': widget.story,
          if (widget.analysisResult != null)
            'analysis_result': widget.analysisResult,
          if (wordsSrsStateJson != null) 'words_srs_state': wordsSrsStateJson,
        },
      );
    } catch (e) {
      Logger.error('VoiceChatPage: Exception during session creation', e);
    }

    if (result == null) {
      if (mounted) {
        setState(() => _isConnecting = false);
        UiUtils.showErrorDialog(
          context,
          message: 'Failed to initialize session. Please try again.',
          error: 'Session creation failed',
          onDismiss: () => Navigator.pop(context),
        );
      }
      return;
    }

    _sessionId = result.sessionId;
    bool isResuming = result.isResumed;

    if (isResuming) {
      // Restore previous messages for captions if possible
      final sessionData = await _adkService.fetchSession(
        appName: widget.appName,
        userId: _userId,
        sessionId: _sessionId!,
      );
      if (sessionData != null) {
        for (var turn in sessionData.history) {
          final author = turn.author;
          final text = turn.contentText;
          if (text != null && text != 'start') {
            _messages.add({
              'role': author == 'user' ? 'user' : 'bot',
              'content': text,
            });
          }
        }
      }
      Logger.info(
        'VoiceChatPage: Resumed session with ${_messages.length} captions',
      );
    }

    try {
      await _voiceService.connect(
        appName: widget.appName,
        userId: _userId,
        sessionId: _sessionId!,
      );

      await Future.delayed(const Duration(seconds: 2));

      if (!mounted) return;

      _toggleListening();

      setState(() {
        _isConnecting = false;
      });

      _voiceService.messages.listen(
        (event) {
          if (!mounted) return;
          _handleVoiceEvent(event);
        },
        onError: (e) {
          Logger.error('WebSocket error', e);
          if (mounted) {
            UiUtils.showErrorDialog(
              context,
              message:
                  'The voice connection was interrupted. Please check your connection and try again.',
              error: e.toString(),
              onDismiss: () => Navigator.pop(context),
              onStay: () {},
            );
          }
        },
        onDone: () {
          Logger.warn('WebSocket stream closed');
          if (mounted && _isConnecting == false && _voiceService.isConnected) {
            UiUtils.showErrorDialog(
              context,
              message:
                  'The voice connection was lost. Please check your connection and try again.',
              error: 'Voice WebSocket closed',
              onDismiss: () => Navigator.pop(context),
            );
          }
        },
      );
    } catch (e) {
      Logger.error('Error connecting voice chat', e);
      if (mounted) {
        setState(() => _isConnecting = false);
        UiUtils.showErrorDialog(
          context,
          message:
              'We could not start the voice call. Please check your connection and try again.',
          error: e.toString(),
          onDismiss: () => Navigator.pop(context),
          onStay: () {},
        );
      }
    }
  }

  /// Maps the current [widget.appName] to a canonical [LessonTypes] key.
  String _lessonTypeKey() {
    switch (widget.appName) {
      case 'word_smith_agent':
        return LessonTypes.wordSmith;
      case 'role_master_agent':
        return LessonTypes.roleMaster;
      default:
        return LessonTypes.echoChamber;
    }
  }

  void _handleVoiceEvent(Map<String, dynamic> event) {
    final author = event['author'] as String?;
    final isAgent = author != null && author.isNotEmpty && author != 'user';

    if (isAgent) {
      if (!_isSpeaking) setState(() => _isSpeaking = true);
      // Audio is now handled via binary frames in VoiceService automatically.
      // Metadata (captions, tool calls) still comes through here in the JSON event.
    } else {
      if (_isSpeaking) setState(() => _isSpeaking = false);
    }

    // --- User transcript ---
    // ADK sends the full running transcript (not deltas) in each event.
    // We replace the bubble text each time. This works correctly because
    // each event carries the complete text so far.
    final inputTrans = event['inputTranscription'];
    if (inputTrans != null &&
        inputTrans['text'] != null &&
        inputTrans['text'].toString().isNotEmpty) {
      _updateLastMessage('user', inputTrans['text'].toString());
    }

    // --- Bot transcript ---
    // Same pattern: running total, replace each time.
    final outputTrans = event['outputTranscription'];
    if (outputTrans != null &&
        outputTrans['text'] != null &&
        outputTrans['text'].toString().isNotEmpty) {
      _updateLastMessage('bot', outputTrans['text'].toString());
    }

    // --- content.parts ---
    // Only process functionResponse entries (e.g. corrector_agent feedback).
    // Intentionally skip plain text parts — they duplicate outputTranscription
    // on the final turn event and would cause the bot bubble to appear twice.
    if (event['content'] != null) {
      for (var part in (event['content']['parts'] as List? ?? [])) {
        if (part['functionResponse'] != null &&
            part['functionResponse']['name'] == 'corrector_agent') {
          final result = part['functionResponse']['response']?['result'];
          if (result != null) {
            _addAssistantMessage(result);
          }
        }
        // Explicitly skip part['text'] — it duplicates outputTranscription.
        // ignore: avoid_unused_element
      }
    }
  }

  void _addAssistantMessage(String text) {
    setState(() {
      _assistantMessages.add({'role': 'corrector_agent', 'content': text});
      _latestAssistantMessage = text;
      _showAssistantBubble = true;
    });
  }

  /// Updates or replaces the last chat message for [role].
  ///
  /// ADK sends the full running transcript in each event, so we always replace
  /// the bubble content with the latest complete text.
  void _updateLastMessage(String role, String text) {
    setState(() {
      if (_messages.isEmpty || _messages.last['role'] != role) {
        _messages.add({'role': role, 'content': text});
      } else {
        _messages.last['content'] = text;
      }
    });
    if (_showCaptions) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  @override
  void dispose() {
    _waveController.dispose();
    _visualizerController.dispose();
    _colorShiftController.dispose();
    _pulseController.dispose();
    _scrollController.dispose();
    _voiceService.dispose();
    _userVolume.dispose();
    _botVolume.dispose();
    // NOTE: we intentionally do NOT delete the ADK session here.
    // If the user pressed back we want to resume it next time.
    // The session is only deleted in _finishSession() after analysis.
    super.dispose();
  }

  void _toggleListening() async {
    if (_isListening) {
      await _voiceService.stopRecording();
    } else {
      await _voiceService.startRecording();
    }

    setState(() {
      _isListening = !_isListening;
      if (_isListening) _isSpeaking = false;
    });
  }

  void _toggleCaptions() {
    setState(() {
      _showCaptions = !_showCaptions;
    });
    if (_showCaptions) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _sendAssistantMessage(String text) async {
    if (text.isEmpty || _sessionId == null) return;

    setState(() {
      _assistantMessages.add({'role': 'user', 'content': text});
    });

    final response = await _adkService.runAgent(
      appName: 'corrector_agent',
      userId: _userId,
      sessionId: _sessionId!,
      message: text,
    );

    if (response != null) {
      final content = response['content']?['parts']?[0];
      String? resultText;
      if (content != null) {
        if (content['text'] != null) {
          resultText = content['text'];
        } else if (content['functionResponse'] != null &&
            content['functionResponse']['name'] == 'corrector_agent') {
          resultText = content['functionResponse']['response']?['result'];
        }
      }

      if (mounted && resultText != null) {
        _addAssistantMessage(resultText);
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _handleAction(
    BuildContext context,
    String action,
    String text,
    SelectableRegionState state,
  ) async {
    state.hideToolbar();
    final userPrefs = UserPreferencesService();
    final learningLanguage =
        widget.learningLanguage ?? await userPrefs.getCurrentLanguage();
    final nativeLanguage =
        widget.nativeLanguage ?? await userPrefs.getNativeLanguage();

    await CustomSelectionToolbar.handleAction(
      context,
      action,
      text,
      learningLanguage: learningLanguage,
      nativeLanguage: nativeLanguage,
    );
  }

  void _openAssistantPanel() {
    _scaffoldKey.currentState?.openEndDrawer();
  }

  Future<void> _finishSession() async {
    final transcript = _messages
        .map((m) => {'role': m['role']!, 'content': m['content']!})
        .toList();

    final learningLanguage =
        widget.learningLanguage ??
        await UserPreferencesService().getCurrentLanguage();

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Fetch XP BEFORE saveLessonScore so we can calculate the delta
      final oldTotalXp = await score.ScoreService.getTotalXP();

      // Fetch previous analysis to merge with new review
      final previousAnalysis = await score.ScoreService.getLatestFullAnalysis(
        _userId,
        learningLanguage,
      );

      // Derive lesson type and analysis mode from the app name
      score.LessonType type = score.LessonType.storyWeaver;
      String lessonTypeString = 'story_weaver';
      String analysisMode = 'full';
      if (widget.appName == 'role_master_agent') {
        type = score.LessonType.rolePlay;
        lessonTypeString = 'role_master';
        analysisMode = 'full';
      } else if (widget.appName == 'word_smith_agent') {
        type = score.LessonType.wordSmith;
        lessonTypeString = 'word_smith';
        analysisMode = 'word_smith';
      } else if (widget.appName == 'voice_chat' ||
          widget.appName == 'echo_chamber_agent') {
        type = score.LessonType.echoChamber;
        lessonTypeString = 'echo_chamber';
        analysisMode = 'full';
      }

      final analysisJson = await _adkService.runAnalyzeAgent(
        topicId: widget.topicId,
        transcript: transcript,
        language: learningLanguage,
        userId: _userId,
        wordsList: widget.wordsList,
        previousAnalysis: previousAnalysis,
        lessonType: analysisMode,
      );

      Logger.info('Analysis Response: $analysisJson');

      score.AnalysisResult? result;
      final bool isWordReview = widget.topicId.startsWith('strange_words_');
      int lessonScore = 0;

      if (analysisJson != null) {
        result = score.AnalysisResult.fromJson(analysisJson);

        lessonScore = score.ScoreService.calculateLessonScore(result, type);

        // Determine if this is imported content by parsing topicId
        final partPrefix = widget.topicId.lastIndexOf('_part_');
        final backToContentId = partPrefix >= 0
            ? widget.topicId.substring(0, partPrefix)
            : null;
        final bool isImportedContent = partPrefix >= 0;

        // Save lesson score to Firestore progress doc for all lesson types.
        // For word reviews this creates a progress doc for strange_words_{language}.
        await score.ScoreService.saveLessonScore(
          widget.userId,
          widget.topicId,
          learningLanguage,
          lessonTypeString,
          lessonScore,
          wordScores: result.wordScores,
          isImported: isImportedContent,
          contentId: backToContentId,
        );

        // Sync combined score back to per-part progress doc if this is imported content
        await score.ScoreService.syncPartScoreAfterLesson(
          userId: widget.userId,
          topicId: widget.topicId,
          language: learningLanguage,
        );

        await score.ScoreService.saveAnalysisResult(
          _userId,
          widget.topicId,
          learningLanguage,
          result,
        );

        // Word scores are saved via saveLessonScore(wordScores: ...) above
        // to the progress/{topicId}_{language} document. SRS state is managed
        // by VocabReviewService below. The deprecated updateWordPriority()
        // call that wrote Format B (flat dotted keys) has been removed.

        // ── Map word_scores (0-100) to SRS ratings (0-3) ──
        if (result.wordScores.isNotEmpty) {
          final Map<String, int> srsRatings = {};
          for (final entry in result.wordScores.entries) {
            srsRatings[entry.key] = (entry.value ~/ 25).clamp(0, 3);
          }

          final vocabService = VocabReviewService();
          if (widget.topicId.startsWith('strange_words_')) {
            // Strange words scope
            await vocabService.submitSessionRatings(
              language: widget.currentLanguage,
              wordRatings: srsRatings,
            );
          } else {
            // Topic scope
            final topicScopeId = VocabReviewService.topicScopeId(
              widget.topicId,
              widget.currentLanguage,
            );
            await vocabService.submitTopicSessionRatings(
              topicScopeId: topicScopeId,
              wordRatings: srsRatings,
            );
          }
        }
      }

      // Cleanup: delete the session from ADK backend as it is completed.
      if (_sessionId != null) {
        await _sessionService.clearSession(
          appName: widget.appName,
          userId: _userId,
          sessionId: _sessionId!,
        );
      }
      if (widget.sessionIdsToDelete != null) {
        if (widget.appName == 'voice_chat' ||
            widget.appName == 'echo_chamber_agent') {
          for (final sid in widget.sessionIdsToDelete!) {
            await _adkService.deleteSession(
              appName: 'video_agent',
              userId: _userId,
              sessionId: sid,
            );
          }
        }
      }

      if (!mounted) return;
      Navigator.pop(context);

      // Fetch XP and topic score AFTER saveLessonScore to calculate the delta
      final newTotalXp = await score.ScoreService.getTotalXP();
      final xpEarned = newTotalXp - oldTotalXp;

      // Derive backToContentId from topicId for imported content
      final partPrefix = widget.topicId.lastIndexOf('_part_');
      final backToContentId = partPrefix >= 0
          ? widget.topicId.substring(0, partPrefix)
          : null;

      // ── Phase 5: Compute SRS stats for word_smith ──
      int easyCount = 0;
      int goodCount = 0;
      int hardCount = 0;
      int forgotCount = 0;
      int? nextReviewCount;

      if (widget.appName == 'word_smith_agent' &&
          result != null &&
          result.wordScores.isNotEmpty) {
        for (final entry in result.wordScores.entries) {
          final rating = (entry.value ~/ 25).clamp(0, 3);
          if (rating == 3) {
            easyCount++;
          } else if (rating == 2) {
            goodCount++;
          } else if (rating == 1) {
            hardCount++;
          } else {
            forgotCount++;
          }
        }
        // Compute next review count for both strange_words and topic scope
        final vocabService = VocabReviewService();
        if (isWordReview) {
          nextReviewCount = await vocabService.getDueCount(
            widget.currentLanguage,
          );
        } else {
          nextReviewCount = await vocabService.getDueCountForTopic(
            topicId: widget.topicId,
            language: widget.currentLanguage,
          );
        }
      }

      // Fetch course-level title from Firestore when available
      String? backToContentTitle;
      if (backToContentId != null) {
        final content = await ContentService().getContent(backToContentId);
        backToContentTitle = content?.title;
      }
      backToContentTitle ??= widget.storySubject;

      int finalTopicScore = lessonScore;
      if (isWordReview) {
        final stats = await VocabReviewService().getStats(
          widget.currentLanguage,
          userId: widget.userId,
        );
        finalTopicScore = (stats.recallRate * 100).toInt();
      }

      // Navigate to LessonCompletionPage with SRS stats for both
      // strange_words reviews and topic scope word_smith lessons.
      // Use pushReplacement so the source page (StrangeWordsPage or
      // TopicWordsPage) remains in the stack — LessonCompletionPage's
      // Continue button will pop back to it (isWordReview: true) or
      // navigate to LessonPathsPage (isWordReview: false).
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(              builder: (context) => LessonCompletionPage(
            subjectTitle: widget.storySubject ?? widget.subjectTitle,
            topicId: widget.topicId,
            currentLanguage: widget.currentLanguage,
            xpEarned: xpEarned,
            oldTotalXp: oldTotalXp,
            analysisResult: result,
            topicScore: finalTopicScore,
            isWordReview: isWordReview,
            easyCount: easyCount,
            goodCount: goodCount,
            hardCount: hardCount,
            forgotCount: forgotCount,
            nextReviewCount: nextReviewCount,
            backToContentId: backToContentId,
            backToContentTitle: backToContentTitle,
            difficulty: 'intermediate',
          ),
        ),
      );
    } catch (e) {
      Logger.error('Error finishing voice session', e);
      if (mounted) {
        Navigator.pop(context);
        UiUtils.showErrorDialog(
          context,
          message: 'Failed to analyze session',
          error: e.toString(),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor = Theme.of(context).scaffoldBackgroundColor;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color accentColor = const Color(0xFF1ABC9C);

    // Theme-aware colors for speaking states
    final Color userSpeakingColor = isDark
        ? const Color(0xFF6366F1)
        : const Color(0xFF8B5CF6);
    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: false,
      backgroundColor: backgroundColor,
      endDrawer: Drawer(
        width: MediaQuery.of(context).size.width * 0.85,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        child: FutureBuilder<Map<String, String>>(
          future: () async {
            final userPrefs = UserPreferencesService();
            return {
              'learning': await userPrefs.getCurrentLanguage(),
              'native': await userPrefs.getNativeLanguage(),
            };
          }(),
          builder: (context, snapshot) {
            final learningLanguage =
                widget.learningLanguage ??
                snapshot.data?['learning'] ??
                'English';
            final nativeLanguage =
                widget.nativeLanguage ?? snapshot.data?['native'] ?? 'Arabic';

            return Scaffold(
              backgroundColor: Colors.transparent,
              resizeToAvoidBottomInset: true,
              body: AssistantChatPanel(
                messages: _assistantMessages,
                onSendMessage: _sendAssistantMessage,
                learningLanguage: learningLanguage,
                nativeLanguage: nativeLanguage,
              ),
            );
          },
        ),
      ),
      body: Stack(
        children: [
          // Animated Gradient Background - activates when user speaks
          Positioned.fill(
            child: AnimatedBuilder(
              animation: Listenable.merge([_colorShiftController, _userVolume]),
              builder: (context, child) {
                // Boost sensitivity for normal speaking levels
                final double rawVolume = _isListening ? _userVolume.value : 0.0;
                // Square root curve plus multiplier makes it much more sensitive
                final double sensitivityBoost = math.sqrt(
                  (rawVolume * 3.0).clamp(0.0, 1.0),
                );

                // Gradually transition background based on activity
                final double transitionFactor = sensitivityBoost.clamp(
                  0.0,
                  1.0,
                );

                final Color startColor = isDark
                    ? const Color(0xFF1E1B4B)
                    : const Color(0xFFF8FAFC);
                final Color endColor = isDark
                    ? const Color(0xFF0F172A)
                    : const Color(0xFFEFF6FF);

                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color.lerp(
                          startColor,
                          userSpeakingColor,
                          0.2 * transitionFactor,
                        )!,
                        Color.lerp(
                          startColor,
                          const Color(0xFF06B6D4),
                          0.1 * transitionFactor,
                        )!,
                        Color.lerp(
                          endColor,
                          const Color(0xFF4F46E5),
                          0.05 * transitionFactor,
                        )!,
                        endColor,
                      ],
                      stops: [
                        0.0 + (_colorShiftController.value * 0.1),
                        0.3 + (_colorShiftController.value * 0.2),
                        0.6 + (_colorShiftController.value * 0.15),
                        1.0,
                      ],
                    ),
                  ),
                  child: sensitivityBoost > 0.01
                      ? CustomPaint(
                          painter: SpeakingBackgroundPainter(
                            animationValue: _colorShiftController.value,
                            volume: sensitivityBoost,
                            isDark: isDark,
                          ),
                        )
                      : null,
                );
              },
            ),
          ),
          // Decorative orbs for atmosphere
          Positioned.fill(
            child: AnimatedBuilder(
              animation: Listenable.merge([
                _waveController,
                _userVolume,
                _botVolume,
              ]),
              builder: (context, child) {
                final double rawVolume = _isSpeaking
                    ? _botVolume.value
                    : (_isListening ? _userVolume.value : 0.0);
                // Boost sensitivity for orbs too
                final double displayVolume = math.sqrt(
                  (rawVolume * 1.5).clamp(0.0, 1.0),
                );

                return CustomPaint(
                  painter: AmbientOrbsPainter(
                    animationValue: _waveController.value,
                    isDark: isDark,
                    isUserSpeaking: _isListening && rawVolume > 0.01,
                    isBotSpeaking: _isSpeaking,
                    volume: displayVolume,
                  ),
                );
              },
            ),
          ),
          // End call button with gradient
          Positioned(
            top: 40,
            right: 16,
            child: GestureDetector(
              onTap: () async {
                final finish = await _showFinishWarning();
                if (finish && mounted) {
                  _finishSession();
                }
              },
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.black.withValues(alpha: 0.1),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xFFEF4444).withValues(alpha: 0.4),
                      blurRadius: 16,
                      spreadRadius: 2,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.call_end_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ),
          ),
          // Back button
          if (widget.agentName.toLowerCase() != 'word smith' &&
              widget.agentName.toLowerCase() != 'role master')
            Positioned(
              top: 40,
              left: 16,
              child: IconButton(
                icon: Icon(
                  Icons.arrow_back_ios_new,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ),
          // AI Assistant Avatar with wave animations when speaking
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeInOutCubic,
                      height: _showCaptions
                          ? constraints.maxHeight * 0.35
                          : constraints.maxHeight * 0.7,
                      child: AnimatedAlign(
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeInOutCubic,
                        alignment: _showCaptions
                            ? const Alignment(0, -0.6)
                            : Alignment.center,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.easeInOutCubic,
                          width: _showCaptions ? 110 : 220,
                          height: _showCaptions ? 110 : 220,
                          child: ValueListenableBuilder<double>(
                            valueListenable: _botVolume,
                            builder: (context, volume, _) {
                              return VoiceAssistantBall(
                                isSpeaking: _isSpeaking,
                                isDarkMode: isDark,
                                animationController: _visualizerController,
                                volume: volume,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    // Captions area (selectable with definition toolbar)
                    Expanded(
                      flex: _showCaptions ? 4 : 1,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 300),
                        opacity: _showCaptions ? 1.0 : 0.0,
                        child: _showCaptions
                            ? SelectionArea(
                                onSelectionChanged: (content) {
                                  _selectedText = content?.plainText;
                                },
                                contextMenuBuilder:
                                    (context, selectableRegionState) {
                                      return CustomSelectionToolbar(
                                        anchors: selectableRegionState
                                            .contextMenuAnchors,
                                        buttonItems: selectableRegionState
                                            .contextMenuButtonItems,
                                        onHide: () =>
                                            selectableRegionState.hideToolbar(),
                                        showDefinition: false,
                                        onCustomAction: (action) {
                                          _handleAction(
                                            context,
                                            action,
                                            _selectedText ?? '',
                                            selectableRegionState,
                                          );
                                        },
                                      );
                                    },
                                child: ListView.builder(
                                  controller: _scrollController,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 5,
                                  ),
                                  itemCount: _messages.length,
                                  itemBuilder: (context, index) {
                                    final message = _messages[index];
                                    final isUser = message['role'] == 'user';

                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: Row(
                                        mainAxisAlignment: isUser
                                            ? MainAxisAlignment.end
                                            : MainAxisAlignment.start,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Flexible(
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 20,
                                                    vertical: 14,
                                                  ),
                                              decoration: BoxDecoration(
                                                gradient: isUser
                                                    ? LinearGradient(
                                                        colors: isDark
                                                            ? [
                                                                const Color(
                                                                  0xFF6366F1,
                                                                ),
                                                                const Color(
                                                                  0xFF8B5CF6,
                                                                ),
                                                              ]
                                                            : [
                                                                const Color(
                                                                  0xFF1ABC9C,
                                                                ),
                                                                const Color(
                                                                  0xFF16A085,
                                                                ),
                                                              ],
                                                        begin:
                                                            Alignment.topLeft,
                                                        end: Alignment
                                                            .bottomRight,
                                                      )
                                                    : null,
                                                color: isUser
                                                    ? null
                                                    : isDark
                                                    ? Colors.white.withValues(
                                                        alpha: 0.1,
                                                      )
                                                    : Theme.of(
                                                        context,
                                                      ).cardTheme.color,
                                                borderRadius: BorderRadius.only(
                                                  topLeft:
                                                      const Radius.circular(24),
                                                  topRight:
                                                      const Radius.circular(24),
                                                  bottomLeft: isUser
                                                      ? const Radius.circular(
                                                          24,
                                                        )
                                                      : const Radius.circular(
                                                          4,
                                                        ),
                                                  bottomRight: isUser
                                                      ? const Radius.circular(4)
                                                      : const Radius.circular(
                                                          24,
                                                        ),
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color:
                                                        (isUser
                                                                ? (isDark
                                                                      ? const Color(
                                                                          0xFF6366F1,
                                                                        )
                                                                      : const Color(
                                                                          0xFF1ABC9C,
                                                                        ))
                                                                : Colors.black)
                                                            .withValues(
                                                              alpha: 0.1,
                                                            ),
                                                    blurRadius: 12,
                                                    offset: const Offset(0, 4),
                                                  ),
                                                ],
                                              ),
                                              child: MarkdownBody(
                                                data: message['content']!,
                                                styleSheet: MarkdownStyleSheet(
                                                  p: GoogleFonts.nunito(
                                                    fontSize: 16,
                                                    color: isUser
                                                        ? Colors.white
                                                        : isDark
                                                        ? Colors.white
                                                        : Theme.of(context)
                                                              .textTheme
                                                              .bodyLarge
                                                              ?.color,
                                                    fontWeight: FontWeight.w600,
                                                    height: 1.4,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                    // Assistant tip bubble
                    if (_showAssistantBubble && _latestAssistantMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 24, bottom: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _VoiceAssistantBubble(
                            message: _latestAssistantMessage!,
                            onClose: () =>
                                setState(() => _showAssistantBubble = false),
                          ),
                        ),
                      ).animate().fade().slideY(begin: 0.2, end: 0),
                    // Control buttons
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: 40,
                        left: 24,
                        right: 24,
                        top: 10,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Assistant panel button
                          _GlassButton(
                            isDark: isDark,
                            onTap: _openAssistantPanel,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: accentColor.withValues(alpha: 0.5),
                                  width: 2,
                                ),
                              ),
                              child: ClipOval(
                                child: Image.asset(
                                  'assets/images/assistant.png',
                                  width: 36,
                                  height: 36,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                          // Main mic button - Enhanced design without yellow light
                          GestureDetector(
                                onTap: _toggleListening,
                                child: AnimatedBuilder(
                                  animation: _pulseController,
                                  builder: (context, child) {
                                    final pulseScale = _isListening
                                        ? 1.0 + (_pulseController.value * 0.08)
                                        : 1.0;
                                    return Transform.scale(
                                      scale: pulseScale,
                                      child: Container(
                                        width: 80,
                                        height: 80,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: _isListening
                                                ? (isDark
                                                      ? [
                                                          const Color(
                                                            0xFF10B981,
                                                          ),
                                                          const Color(
                                                            0xFF059669,
                                                          ),
                                                        ]
                                                      : [
                                                          const Color(
                                                            0xFF2ECC71,
                                                          ),
                                                          const Color(
                                                            0xFF27AE60,
                                                          ),
                                                        ])
                                                : [
                                                    const Color(0xFFE74C3C),
                                                    const Color(0xFFC0392B),
                                                  ],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: isDark
                                                ? Colors.white.withValues(
                                                    alpha: 0.3,
                                                  )
                                                : Colors.black.withValues(
                                                    alpha: 0.1,
                                                  ),
                                            width: 2,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color:
                                                  (_isListening
                                                          ? (isDark
                                                                ? const Color(
                                                                    0xFF10B981,
                                                                  )
                                                                : const Color(
                                                                    0xFF2ECC71,
                                                                  ))
                                                          : const Color(
                                                              0xFFE74C3C,
                                                            ))
                                                      .withValues(alpha: 0.4),
                                              blurRadius: 20,
                                              spreadRadius: _isListening
                                                  ? 6
                                                  : 4,
                                              offset: const Offset(0, 6),
                                            ),
                                          ],
                                        ),
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            // Animated pulse rings when listening
                                            if (_isListening)
                                              AnimatedBuilder(
                                                animation: Listenable.merge([
                                                  _pulseController,
                                                  _userVolume,
                                                ]),
                                                builder: (context, _) {
                                                  return Stack(
                                                    alignment: Alignment.center,
                                                    children: [
                                                      // Rapid inner waves for "quick moving" feel
                                                      CustomPaint(
                                                        size: const Size(
                                                          80,
                                                          80,
                                                        ),
                                                        painter: MicWavePainter(
                                                          animationValue:
                                                              (DateTime.now()
                                                                      .millisecondsSinceEpoch %
                                                                  1000) /
                                                              1000.0,
                                                          volume:
                                                              _userVolume.value,
                                                          color: Colors.white
                                                              .withValues(
                                                                alpha: 0.5,
                                                              ),
                                                        ),
                                                      ),
                                                      Container(
                                                        width:
                                                            70 +
                                                            (_pulseController
                                                                    .value *
                                                                20),
                                                        height:
                                                            70 +
                                                            (_pulseController
                                                                    .value *
                                                                20),
                                                        decoration: BoxDecoration(
                                                          shape:
                                                              BoxShape.circle,
                                                          border: Border.all(
                                                            color:
                                                                (isDark
                                                                        ? const Color(
                                                                            0xFF10B981,
                                                                          )
                                                                        : const Color(
                                                                            0xFF2ECC71,
                                                                          ))
                                                                    .withValues(
                                                                      alpha:
                                                                          0.3 *
                                                                          (1 -
                                                                              _pulseController.value),
                                                                    ),
                                                            width: 2,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  );
                                                },
                                              ),
                                            Icon(
                                              _isListening
                                                  ? Icons.mic_rounded
                                                  : Icons.mic_off_rounded,
                                              color: Colors.white,
                                              size: 32,
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              )
                              .animate(target: _isListening ? 1 : 0)
                              .scale(
                                begin: const Offset(1, 1),
                                end: const Offset(1.05, 1.05),
                              ),
                          // Captions toggle
                          _GlassButton(
                            isDark: isDark,
                            onTap: _toggleCaptions,
                            isActive: _showCaptions,
                            child: Icon(
                              _showCaptions
                                  ? Icons.closed_caption
                                  : Icons.closed_caption_outlined,
                              color: _showCaptions
                                  ? Colors.white
                                  : (isDark ? Colors.white70 : Colors.black54),
                              size: 24,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          // Loading overlay
          if (_isConnecting)
            Positioned.fill(
              child: Container(
                color: backgroundColor,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 60,
                        height: 60,
                        child: CircularProgressIndicator(
                          color: accentColor,
                          strokeWidth: 3,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Establishing Connection...',
                        style: GoogleFonts.nunito(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Preparing your AI session',
                        style: GoogleFonts.nunito(
                          fontSize: 14,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Shows a dialog that warns the user their session and progress will be lost.
  Future<bool> _showFinishWarning() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1B4B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 10),
            Text('Finish lesson?'),
          ],
        ),
        content: const Text(
          'Are you sure you want to finish this lesson? Your current session will be closed and cannot be resumed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1ABC9C),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Finish'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

// Glass button component
class _GlassButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool isDark;
  final bool isActive;

  const _GlassButton({
    required this.child,
    required this.onTap,
    required this.isDark,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          gradient: isActive
              ? LinearGradient(
                  colors: isDark
                      ? [
                          Colors.white.withValues(alpha: 0.2),
                          Colors.white.withValues(alpha: 0.1),
                        ]
                      : [
                          Colors.black.withValues(alpha: 0.1),
                          Colors.black.withValues(alpha: 0.05),
                        ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isActive
              ? null
              : isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.white.withValues(alpha: 0.8),
          shape: BoxShape.circle,
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.2)
                : Colors.black.withValues(alpha: 0.1),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

class VoiceAssistantBall extends StatelessWidget {
  final bool isSpeaking;
  final bool isDarkMode;
  final AnimationController animationController;
  final double volume;

  const VoiceAssistantBall({
    super.key,
    required this.isSpeaking,
    required this.isDarkMode,
    required this.animationController,
    this.volume = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 200,
      child: AnimatedBuilder(
        animation: animationController,
        builder: (context, child) {
          return CustomPaint(
            painter: BallPainter(
              animationValue: animationController.value,
              isSpeaking: isSpeaking,
              volume: volume,
              isDarkMode: isDarkMode,
            ),
          );
        },
      ),
    );
  }
}

class BallPainter extends CustomPainter {
  final double animationValue;
  final bool isSpeaking;
  final double volume;
  final bool isDarkMode;

  BallPainter({
    required this.animationValue,
    required this.isSpeaking,
    required this.volume,
    this.isDarkMode = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Theme-aware dynamic colors
    final Color baseTopColor = isDarkMode
        ? const Color(0xFF8B5CF6)
        : const ui.Color.fromARGB(255, 20, 121, 236);
    final Color baseBottomColor = isDarkMode
        ? const Color(0xFFEC4899)
        : const Color(0xFF1ABC9C);

    final topColor = Color.lerp(
      baseTopColor,
      const Color(0xFFFF5252),
      (volume * 0.8).clamp(0.0, 1.0),
    )!;
    final bottomColor = Color.lerp(
      baseBottomColor,
      const Color(0xFFFFD740),
      (volume * 0.8).clamp(0.0, 1.0),
    )!;

    // Draw Main Sphere Background with gradient
    final paintTop = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [topColor, Color.lerp(topColor, bottomColor, 0.2)!],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height / 2));
    final paintBottom = Paint()
      ..shader =
          LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.lerp(bottomColor, topColor, 0.2)!, bottomColor],
          ).createShader(
            Rect.fromLTWH(0, size.height / 2, size.width, size.height / 2),
          );

    final circlePath = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.clipPath(circlePath);

    // Draw Top Half
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height / 2), paintTop);
    // Draw Bottom Half
    canvas.drawRect(
      Rect.fromLTWH(0, size.height / 2, size.width, size.height / 2),
      paintBottom,
    );

    // Inner Shadow for depth
    final innerShadowPaint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        radius,
        [
          Colors.transparent,
          Colors.black.withValues(alpha: isDarkMode ? 0.4 : 0.15),
        ],
        [0.75, 1.0],
      );
    canvas.drawCircle(center, radius, innerShadowPaint);

    // Highlight reflection
    final highlightPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(center.dx - radius * 0.3, center.dy - radius * 0.3),
        radius * 0.5,
        [
          Colors.white.withValues(alpha: isDarkMode ? 0.3 : 0.4),
          Colors.white.withValues(alpha: 0.0),
        ],
      );
    canvas.drawCircle(center, radius, highlightPaint);

    // Wave Visualization
    bool isActive = volume > 0.05;

    if (!isActive) {
      // Idle State: Gentle breathing wave
      final wavePaint = Paint()
        ..color =
            (isDarkMode ? const Color(0xFF22D3EE) : const Color(0xFF00FFFF))
                .withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      final path = Path();
      double waveCount = 2;
      double amplitude = 5 + (animationValue * 3);
      double phase = animationValue * 0.5 * math.pi;

      for (double x = 0; x <= size.width; x++) {
        double normalizedX = x / size.width;
        double envelope = math.sin(normalizedX * math.pi);
        double y =
            size.height / 2 +
            (math.sin(normalizedX * waveCount * math.pi - phase) *
                amplitude *
                envelope);

        if (x == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, wavePaint);
    } else {
      // Active State: Enhanced glowing waves with multiple layers

      double ampScale = volume * (size.height * 0.45);
      double freqMod = 1.0 + (volume * 2.5);
      double phase = animationValue * 6.0 * math.pi;

      // Multiple wave layers for richness
      _drawGlowingWave(
        canvas,
        size,
        color: isDarkMode ? const Color(0xFF22D3EE) : const Color(0xFF00FFFF),
        freq: 0.05 * freqMod,
        phase: phase,
        amp: ampScale * 1.0,
        isSecondary: false,
      );

      _drawGlowingWave(
        canvas,
        size,
        color: isDarkMode ? const Color(0xFFFBBF24) : const Color(0xFFFFB732),
        freq: -0.04 * freqMod,
        phase: phase + 1.5,
        amp: ampScale * 1.5,
        isSecondary: true,
      );

      _drawGlowingWave(
        canvas,
        size,
        color: isDarkMode ? const Color(0xFFA78BFA) : const Color(0xFF8B5CF6),
        freq: 0.07 * freqMod,
        phase: phase + 3.0,
        amp: ampScale * 0.8,
        isSecondary: false,
      );
    }
  }

  void _drawGlowingWave(
    Canvas canvas,
    Size size, {
    required Color color,
    required double freq,
    required double phase,
    required double amp,
    required bool isSecondary,
  }) {
    final path = Path();

    for (double x = 0; x <= size.width; x += 2) {
      double normalizedX = x / size.width;
      double envelope = math.sin(normalizedX * math.pi);

      double baseVal = math.sin(normalizedX * 15.0 * freq.abs() * 100 + phase);
      if (!isSecondary && volume > 0.1) {
        baseVal += 0.4 * math.sin(normalizedX * 25.0 + phase * 2.5);
      }

      double y = size.height / 2 + (baseVal * amp * envelope);

      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Outer glow
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0);
    canvas.drawPath(path, glowPaint);

    // Middle glow
    final midPaint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);
    canvas.drawPath(path, midPaint);

    // Core line
    final corePaint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawPath(path, corePaint);
  }

  @override
  bool shouldRepaint(covariant BallPainter oldDelegate) =>
      oldDelegate.animationValue != animationValue ||
      oldDelegate.volume != volume ||
      oldDelegate.isSpeaking != isSpeaking ||
      oldDelegate.isDarkMode != isDarkMode;
}

// Enhanced Background Painter - Animated gradient when user speaks
class SpeakingBackgroundPainter extends CustomPainter {
  final double animationValue;
  final double volume;
  final bool isDark;

  SpeakingBackgroundPainter({
    required this.animationValue,
    required this.volume,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // Draw flowing particles/orbs when user is speaking
    final int particleCount = 6; // Increased for more "dots"
    for (int i = 0; i < particleCount; i++) {
      final double phase = (i / particleCount) * 2 * math.pi;
      final double t = animationValue * 2 * math.pi + phase;

      final double x =
          size.width * 0.1 +
          (size.width * 0.8) * ((i * 1.37) % 1.0) +
          math.sin(t * 0.4 + (volume * 1.5)) * size.width * 0.1;
      final double y =
          size.height * 0.2 +
          (size.height * 0.6) * ((i * 1.61) % 1.0) +
          math.cos(t * 0.5 + (volume * 1.2)) * size.height * 0.1;

      final Color particleColor = isDark
          ? Color.lerp(
              const Color(0xFF6366F1),
              const Color(0xFFEC4899),
              (i / particleCount),
            )!
          : Color.lerp(
              const Color(0xFF8B5CF6),
              const Color(0xFFF472B6),
              (i / particleCount),
            )!;

      // Use a more dynamic but smooth alpha
      final double baseAlpha = 0.05 + (volume * 0.2);
      final double pulsingAlpha = baseAlpha * (0.8 + 0.2 * math.sin(t * 2));

      paint.color = particleColor.withValues(
        alpha: pulsingAlpha.clamp(0.0, 1.0),
      );

      // Radius reacts smoothly
      final double radius =
          10 +
          (volume * 100 * math.sin(t * 0.3 + 0.5).abs()) +
          math.sin(t * 1.2) * 5;

      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant SpeakingBackgroundPainter oldDelegate) =>
      oldDelegate.animationValue != animationValue ||
      oldDelegate.volume != volume ||
      oldDelegate.isDark != isDark;
}

// Ambient Orbs Painter - Decorative floating orbs
class AmbientOrbsPainter extends CustomPainter {
  final double animationValue;
  final bool isDark;
  final bool isUserSpeaking;
  final bool isBotSpeaking;
  final double volume;

  AmbientOrbsPainter({
    required this.animationValue,
    required this.isDark,
    required this.isUserSpeaking,
    required this.isBotSpeaking,
    this.volume = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    final Color primaryColor = isBotSpeaking
        ? (isDark ? const Color(0xFF14B8A6) : const Color(0xFF2DD4BF))
        : (isUserSpeaking
              ? (isDark ? const Color(0xFF6366F1) : const Color(0xFF8B5CF6))
              : (isDark ? const Color(0xFF4B5563) : const Color(0xFFD1D5DB)));

    final Color secondaryColor = isBotSpeaking
        ? (isDark ? const Color(0xFFF59E0B) : const Color(0xFFFBBF24))
        : (isUserSpeaking
              ? (isDark ? const Color(0xFFEC4899) : const Color(0xFFF472B6))
              : (isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB)));

    _drawOrb(
      canvas,
      size,
      paint,
      Offset(size.width * 0.15, size.height * 0.2),
      size.width * 0.15,
      primaryColor,
      0,
    );
    _drawOrb(
      canvas,
      size,
      paint,
      Offset(size.width * 0.85, size.height * 0.25),
      size.width * 0.12,
      secondaryColor,
      1,
    );
    _drawOrb(
      canvas,
      size,
      paint,
      Offset(size.width * 0.1, size.height * 0.75),
      size.width * 0.1,
      secondaryColor,
      2,
    );
    _drawOrb(
      canvas,
      size,
      paint,
      Offset(size.width * 0.9, size.height * 0.8),
      size.width * 0.08,
      primaryColor,
      3,
    );
  }

  void _drawOrb(
    Canvas canvas,
    Size size,
    Paint paint,
    Offset center,
    double baseRadius,
    Color color,
    int index,
  ) {
    final double t = animationValue * 2 * math.pi + (index * math.pi / 2);
    // Pulse radius reacts to volume
    final double volumeScale = 1.0 + (volume * 0.4);
    final double pulseRadius =
        baseRadius * volumeScale * (1 + math.sin(t) * 0.12);

    // Drifting motion based on volume
    final double driftX = math.sin(t * 0.5) * 15 * volume;
    final double driftY = math.cos(t * 0.5) * 15 * volume;
    final Offset finalCenter = center.translate(driftX, driftY);

    paint.color = color.withValues(alpha: 0.08 + (volume * 0.04));
    canvas.drawCircle(finalCenter, pulseRadius * 2, paint);

    paint.color = color.withValues(alpha: 0.15 + (volume * 0.08));
    canvas.drawCircle(finalCenter, pulseRadius * 1.5, paint);

    paint.color = color.withValues(alpha: 0.25 + (volume * 0.1));
    canvas.drawCircle(finalCenter, pulseRadius, paint);
  }

  @override
  bool shouldRepaint(covariant AmbientOrbsPainter oldDelegate) =>
      oldDelegate.animationValue != animationValue ||
      oldDelegate.isDark != isDark ||
      oldDelegate.isUserSpeaking != isUserSpeaking ||
      oldDelegate.isBotSpeaking != isBotSpeaking ||
      oldDelegate.volume != volume;
}

// Quick moving wave painter for Mic button
class MicWavePainter extends CustomPainter {
  final double animationValue;
  final double volume;
  final Color color;

  MicWavePainter({
    required this.animationValue,
    required this.volume,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width / 2;

    // Draw 3 rapid expanding ripples
    for (int i = 0; i < 3; i++) {
      double progress = (animationValue + i / 3.0) % 1.0;
      double radius = baseRadius * 0.8 + (progress * baseRadius * 0.5);
      double opacity = (1.0 - progress) * (0.3 + volume * 0.7);

      paint.color = color.withValues(alpha: opacity.clamp(0.0, 1.0));
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant MicWavePainter oldDelegate) =>
      oldDelegate.animationValue != animationValue ||
      oldDelegate.volume != volume;
}

class _VoiceAssistantBubble extends StatelessWidget {
  final String message;
  final VoidCallback onClose;

  const _VoiceAssistantBubble({required this.message, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.7,
      ),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF8B5CF6), const Color(0xFF6366F1)]
              : [const Color(0xFF1ABC9C), const Color(0xFF16A085)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lightbulb_outline, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.nunito(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 16),
            onPressed: onClose,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}
