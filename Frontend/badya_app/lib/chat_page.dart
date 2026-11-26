import 'package:Badya/services/user_preferences_service.dart';
import 'package:Badya/services/adk_service.dart';
import 'package:Badya/services/content_service.dart';
import 'package:Badya/services/lesson_session_service.dart';
import 'package:Badya/utils/ui_utils.dart';
import 'package:Badya/utils/score_service.dart' as score;
import 'package:Badya/utils/language_service.dart';
import 'package:Badya/utils/logger.dart';
import 'package:Badya/widgets/custom_selection_toolbar.dart';
import 'package:Badya/widgets/definition_history_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'widgets/assistant_chat_panel.dart';
import 'lesson_completion_page.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;

enum ChatDrawerContent { assistant, definition }

class ChatPage extends StatefulWidget {
  final String appName;
  final String sessionId;
  final String userId;
  final String initialAgent;
  final String? initialStory;
  final String? storySubject;
  final String topicId;
  final String? analysisResult;
  final String? language;
  final String? nativeLanguage;
  final String? description;
  final List<String>? wordsList;
  final List<String>? sessionIdsToDelete;
  final String currentLanguage;
  final String lessonType;

  const ChatPage({
    super.key,
    required this.appName,
    required this.sessionId,
    required this.userId,
    required this.initialAgent,
    required this.topicId,
    this.initialStory,
    this.storySubject,
    this.analysisResult,
    this.language,
    this.nativeLanguage,
    this.description,
    this.wordsList,
    this.sessionIdsToDelete,
    required this.currentLanguage,
    required this.lessonType,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [];
  final List<Map<String, String>> _assistantMessages = [];
  String? _latestAssistantMessage;
  bool _showAssistantBubble = false;
  bool _isLoading = false;

  late AnimationController _jumpingDotsController;
  bool _isConversationStarted = false;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  Map<String, String> _learningDialects = {};

  String? _textChatSessionId;
  String? _correctorSessionId;
  String? _definitionSessionId;
  final List<Map<String, String>> _definitionHistory = [];
  Stream<String>? _definitionStream;
  String? _currentWord;
  ChatDrawerContent _drawerContent = ChatDrawerContent.assistant;
  String? _selectedText;

  @override
  void initState() {
    super.initState();
    _jumpingDotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
    _loadDialects();
  }

  final AdkService _adkService = AdkService();
  final LessonSessionService _sessionService = LessonSessionService();

  Future<void> _loadDialects() async {
    final userPrefs = UserPreferencesService();
    final dialects = await userPrefs.getLearningDialects();
    setState(() {
      _learningDialects = dialects;
    });
  }

  bool _isResuming = false;

  Future<void> _initTextChat() async {
    final userPrefs = UserPreferencesService();
    final nativeLanguage =
        widget.nativeLanguage ?? await userPrefs.getNativeLanguage();
    final learningLanguageBase =
        widget.language ?? await userPrefs.getCurrentLanguage();
    final dialect = _learningDialects[learningLanguageBase] ?? '';
    final learningLanguage = dialect.isEmpty
        ? learningLanguageBase
        : '$learningLanguageBase ($dialect)';

    // 1. Deterministic session discovery
    final snapshot = _sessionService.getSession(
      topicId: widget.topicId,
      lessonType: widget.lessonType,
    );

    _textChatSessionId = snapshot.sessionId;
    _correctorSessionId = snapshot.correctorSessionId;
    _definitionSessionId = snapshot.definitionSessionId;

    // 2. Check for existing session and history
    final existingData = await _adkService.fetchSession(
      appName: widget.appName,
      userId: widget.userId,
      sessionId: _textChatSessionId!,
    );

    if (existingData != null) {
      _isResuming = true;
      _messages.clear(); // Ensure we don't double history if called twice
      for (var turn in existingData.history) {
        final author = turn.author;
        final text = turn.contentText;
        final isTriggerPrompt = text != null &&
            (text.toLowerCase() == 'start' ||
             text.toLowerCase() == 'generate the story.' ||
             text.toLowerCase() == 'generate the story');
        if (text != null && !isTriggerPrompt) {
          _messages.add({
            'role': author == 'user' ? 'user' : widget.initialAgent,
            'content': text,
          });
        }
      }
      Logger.info(
        'ChatPage: Resumed session with ${_messages.length} messages',
      );
    } else {
      _isResuming = false;
      // 3. Create a fresh session if none exists
      final performanceSummary =
          await score.ScoreService.getLatestPerformanceSummary(
            widget.userId,
            widget.currentLanguage,
          );
      final languageLevel = await score.ScoreService.getLatestLanguageLevel(
        widget.userId,
        widget.currentLanguage,
      );

      try {
        final result = await _adkService.createSession(
          appName: widget.appName,
          userId: widget.userId,
          sessionId: _textChatSessionId,
          state: {
			'topic_id': widget.topicId,
            'story': widget.initialStory,
            'story_subject': widget.storySubject,
            'analysis_result': widget.analysisResult,
            'language_level': languageLevel ?? '',
            'description': widget.description,
            'words_list': widget.wordsList,
          },
        );
        if (result == null) throw Exception('Failed to create session');
        _textChatSessionId = result.sessionId;
        _isResuming = result.isResumed;

        if (_isResuming) {
          // Re-fetch history if createSession reported resumption (double check)
          await _initTextChat();
          return;
        }
      } catch (e) {
        Logger.error('Error initializing chat', e);
        if (mounted) {
          UiUtils.showErrorDialog(
            context,
            message:
                'We could not start the chat. Please check your connection and try again.',
            error: e.toString(),
            onDismiss: () => Navigator.pop(context),
          );
        }
      }
    }
  }

  Future<void> _initCorrector() async {
    // _correctorSessionId is always set from snapshot; createSession handles
    // 409 Conflict (already exists) gracefully and returns the existing session.
    final userPrefs = UserPreferencesService();
    final learningLanguageBase =
        widget.language ?? await userPrefs.getCurrentLanguage();
    final dialect = _learningDialects[learningLanguageBase] ?? '';
    final learningLanguage = dialect.isEmpty
        ? learningLanguageBase
        : '$learningLanguageBase ($dialect)';

    final result = await _adkService.createSession(
      appName: 'corrector_agent',
      userId: widget.userId,
      sessionId: _correctorSessionId,
      state: {'language': learningLanguage},
    );
    if (result != null) {
      setState(() {
        _correctorSessionId = result.sessionId;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isConversationStarted) {
      _isConversationStarted = true;
      _initialize();
    }
  }

  Future<void> _initialize() async {
    await _initTextChat();
    await _initCorrector();
    await _createDefinitionSession();

    // Only send the "start" trigger if this is a brand-new session
    if (!_isResuming) {
      await _startConversation();
    } else {
      // Just refresh the scroll to show history
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  Future<void> _createDefinitionSession() async {
    final languageService = LanguageService();
    final userPrefs = UserPreferencesService();
    final learningLanguageBase =
        widget.language ?? await userPrefs.getCurrentLanguage();
    final dialect = _learningDialects[learningLanguageBase] ?? '';
    final learningLanguage = dialect.isEmpty
        ? learningLanguageBase
        : '$learningLanguageBase ($dialect)';

    final result = await languageService.createSession(
      appName: 'definition_agent',
      userId: widget.userId,
      sessionId: _definitionSessionId,
      state: {'language': learningLanguage},
    );

    if (result != null) {
      if (mounted) {
        setState(() {
          _definitionSessionId = result.sessionId;
        });
      }

      // Restore definition history if resumed
      if (result.isResumed) {
        final sessionData = await _adkService.fetchSession(
          appName: 'definition_agent',
          userId: widget.userId,
          sessionId: result.sessionId,
        );
        if (sessionData != null) {
          _definitionHistory.clear();
          for (var i = 0; i < sessionData.history.length; i++) {
            final turn = sessionData.history[i];
            if (turn.author == 'user') {
              final word = turn.contentText;
              if (i + 1 < sessionData.history.length) {
                final nextTurn = sessionData.history[i + 1];
                if (nextTurn.author != 'user') {
                  final definition = nextTurn.contentText;
                  if (word != null && definition != null) {
                    _definitionHistory.add({
                      'word': word,
                      'definition': definition,
                    });
                  }
                }
              }
            }
          }
          if (mounted) setState(() {});
        }
      }
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
        widget.language ?? await userPrefs.getCurrentLanguage();
    final nativeLanguage =
        widget.nativeLanguage ?? await userPrefs.getNativeLanguage();

    await CustomSelectionToolbar.handleAction(
      context,
      action,
      text,
      learningLanguage: learningLanguage,
      nativeLanguage: nativeLanguage,
      onDefinition: () {
        if (_definitionSessionId != null) {
          setState(() {
            _currentWord = text;
            _definitionStream = LanguageService().define(
              text,
              sessionId: _definitionSessionId!,
              userId: widget.userId,
              sourceLanguage: widget.language,
              targetLanguage: widget.nativeLanguage,
            );
            _drawerContent = ChatDrawerContent.definition;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scaffoldKey.currentState?.openEndDrawer();
          });
        } else {
          UiUtils.showErrorSnackbar(context, 'Definition service not ready. Please try again.');
        }
      },
    );
  }

  void _openDefinitionPanel() {
    setState(() {
      _drawerContent = ChatDrawerContent.definition;
    });
    _scaffoldKey.currentState?.openEndDrawer();
  }

  void _onDefinitionRequested(String text) {
    if (_definitionSessionId != null) {
      setState(() {
        _currentWord = text;
        _definitionStream = LanguageService().define(
          text,
          sessionId: _definitionSessionId!,
          userId: widget.userId,
          sourceLanguage: widget.language,
          targetLanguage: widget.nativeLanguage,
        );
        _drawerContent = ChatDrawerContent.definition;
      });
    } else {
      UiUtils.showErrorSnackbar(context, 'Definition service not ready. Please try again.');
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

  @override
  void dispose() {
    _jumpingDotsController.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _startConversation() async {
    await _sendMessage("start", showUserMessage: false);
  }

  Future<void> _sendMessage(String text, {bool showUserMessage = true}) async {
    if (text.isEmpty) return;

    if (showUserMessage) {
      setState(() {
        _messages.add({'role': 'user', 'content': text});
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }

    setState(() {
      _isLoading = true;
    });

    _controller.clear();

    if (_textChatSessionId == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final response = await _adkService.runAgent(
        appName: widget.appName,
        userId: widget.userId,
        sessionId: _textChatSessionId!,
        message: text,
      );

      if (!context.mounted) return;

      if (response != null) {
        final content = response['content']?['parts']?[0];
        String? agentText;
        if (content != null) {
          if (content['text'] != null) {
            agentText = content['text'];
          } else if (content['functionResponse'] != null &&
              content['functionResponse']['name'] == 'corrector_agent') {
            final correctorResult =
                content['functionResponse']['response']?['result'];
            if (correctorResult != null) {
              _addAssistantMessage(correctorResult);
            }
          }
        }

        setState(() {
          if (agentText != null) {
            _messages.add({'role': widget.initialAgent, 'content': agentText});
          }
          _isLoading = false;
        });
      } else {
        throw Exception('Empty response from agent');
      }
    } catch (e) {
      Logger.error('Error sending message', e);
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        UiUtils.showErrorDialog(
          context,
          message:
              'I am having trouble replying right now. Please check your internet connection.',
          error: e.toString(),
        );
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _addAssistantMessage(String text) {
    setState(() {
      _assistantMessages.add({'role': 'corrector_agent', 'content': text});
      _latestAssistantMessage = text;
      _showAssistantBubble = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _sendAssistantMessage(String text) async {
    if (text.isEmpty || _correctorSessionId == null) return;

    setState(() {
      _assistantMessages.add({'role': 'user', 'content': text});
    });

    final response = await _adkService.runAgent(
      appName: 'corrector_agent',
      userId: widget.userId,
      sessionId: _correctorSessionId!,
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
        setState(() {
          _assistantMessages.add({
            'role': 'corrector_agent',
            'content': resultText!,
          });
          _latestAssistantMessage = resultText;
          _showAssistantBubble = true;
        });
      }
    }
  }

  Future<void> _finishChatAndGenerateReport() async {
    final transcript = _messages
        .map((m) => {'role': m['role']!, 'content': m['content']!})
        .toList();

    final userPrefs = UserPreferencesService();
    final learningLanguage =
        widget.language ?? await userPrefs.getCurrentLanguage();

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
        widget.userId,
        learningLanguage,
      );

      final analysisJson = await _adkService.runAnalyzeAgent(
        topicId: widget.topicId,
        transcript: transcript,
        language: learningLanguage,
        userId: widget.userId,
        wordsList: widget.wordsList,
        previousAnalysis: previousAnalysis,
        lessonType: 'full', // chat_page is always story_weaver → full analysis
      );

      score.AnalysisResult? result;
      if (analysisJson != null) {
        result = score.AnalysisResult.fromJson(analysisJson);

        final lessonScore = score.ScoreService.calculateLessonScore(
          result!,
          score.LessonType.storyWeaver,
        );

        // Determine if this is imported content by parsing topicId
        final partPrefix = widget.topicId.lastIndexOf('_part_');
        final backToContentId = partPrefix >= 0
            ? widget.topicId.substring(0, partPrefix)
            : null;
        final bool isImportedContent = partPrefix >= 0;

        await score.ScoreService.saveLessonScore(
          widget.userId,
          widget.topicId,
          learningLanguage,
          'story_weaver',
          lessonScore,
          wordScores: result!.wordScores,
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
          widget.userId,
          widget.topicId,
          learningLanguage,
          result!,
        );
        // Word scores are saved via saveLessonScore(wordScores: ...) above
        // to the progress/{topicId}_{language} document. SRS state is managed
        // by VocabReviewService. The deprecated updateWordPriority() call that
        // wrote Format B (flat dotted keys) has been removed.
      }

      // Cleanup: delete the sessions from ADK backend as they are completed.
      if (_textChatSessionId != null) {
        await _sessionService.clearSession(
          appName: widget.appName,
          userId: widget.userId,
          sessionId: _textChatSessionId!,
        );
      }
      if (_correctorSessionId != null) {
        await _sessionService.clearSession(
          appName: 'corrector_agent',
          userId: widget.userId,
          sessionId: _correctorSessionId!,
        );
      }
      if (_definitionSessionId != null) {
        await _sessionService.clearSession(
          appName: 'definition_agent',
          userId: widget.userId,
          sessionId: _definitionSessionId!,
        );
      }

      if (widget.sessionIdsToDelete != null) {
        await _adkService.deleteSession(
          appName: 'story_agent',
          userId: widget.userId,
          sessionId: widget.sessionId,
        );
      }

      if (!mounted) return;
      Navigator.pop(context);

      // Fetch XP data for completion page
      final newTotalXp = await score.ScoreService.getTotalXP();
      final xpEarned = newTotalXp - oldTotalXp;
      final topicScore = await score.ScoreService.getTopicScore(
        widget.userId,
        widget.topicId,
        learningLanguage,
      );

      // Derive backToContentId from topicId for imported content
      final partPrefix = widget.topicId.lastIndexOf('_part_');
      final backToContentId = partPrefix >= 0
          ? widget.topicId.substring(0, partPrefix)
          : null;

      // Fetch course-level title from Firestore when available
      String? backToContentTitle;
      if (backToContentId != null) {
        final content = await ContentService().getContent(backToContentId);
        backToContentTitle = content?.title;
      }
      backToContentTitle ??= widget.storySubject;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => LessonCompletionPage(
            subjectTitle: widget.storySubject ?? 'Unknown Subject',
            topicId: widget.topicId,
            currentLanguage: widget.currentLanguage,
            xpEarned: xpEarned,
            oldTotalXp: oldTotalXp,
            analysisResult: result,
            topicScore: topicScore,
            backToContentId: backToContentId,
            backToContentTitle: backToContentTitle,
            difficulty: 'intermediate',
          ),
        ),
        (Route<dynamic> route) {
          if (backToContentId != null) {
            return route.settings.name == 'ImportCoursePage' || route.isFirst;
          }
          return route.isFirst;
        },
      );
    } catch (e) {
      Logger.error('Error in finishing chat', e);
      if (mounted) {
        Navigator.pop(context);
        UiUtils.showErrorDialog(
          context,
          message: 'Failed to analyze chat',
          error: e.toString(),
        );
      }
    }
  }

  void _openAssistantPanel() {
    setState(() {
      _drawerContent = ChatDrawerContent.assistant;
    });
    _scaffoldKey.currentState?.openEndDrawer();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new,
            color: Theme.of(context).iconTheme.color,
          ),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(
              Icons.check_circle_outline_rounded,
              color: Color(0xFF1ABC9C),
              size: 28,
            ),
            onPressed: () async {
              final finish = await _showFinishWarning();
              if (finish && mounted) {
                _finishChatAndGenerateReport();
              }
            },
            tooltip: 'Finish Chat',
          ),
          const SizedBox(width: 8),
        ],
      ),
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
                widget.language ?? snapshot.data?['learning'] ?? 'English';
            final nativeLanguage =
                widget.nativeLanguage ?? snapshot.data?['native'] ?? 'Arabic';

            return Scaffold(
              backgroundColor: Colors.transparent,
              resizeToAvoidBottomInset: true,
              body: _drawerContent == ChatDrawerContent.assistant
                  ? AssistantChatPanel(
                      messages: _assistantMessages,
                      onSendMessage: _sendAssistantMessage,
                      onDefinitionRequested: _onDefinitionRequested,
                      learningLanguage: learningLanguage,
                      nativeLanguage: nativeLanguage,
                    )
                  : DefinitionHistoryPanel(
                      definitionStream: _definitionStream,
                      history: _definitionHistory,
                      initialWord: _currentWord,
                      onClose: () =>
                          _scaffoldKey.currentState?.closeEndDrawer(),
                    ),
            );
          },
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SelectionArea(
              onSelectionChanged: (content) {
                _selectedText = content?.plainText;
              },
              contextMenuBuilder: (context, selectableRegionState) {
                return CustomSelectionToolbar(
                  anchors: selectableRegionState.contextMenuAnchors,
                  buttonItems: selectableRegionState.contextMenuButtonItems,
                  onHide: () => selectableRegionState.hideToolbar(),
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
                  vertical: 10,
                ),
                itemCount: _messages.length + (_isLoading ? 1 : 0),
                itemBuilder: (context, index) {
                  if (_isLoading && index == _messages.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 20),
                      child: Row(
                        children: [
                          const SizedBox(width: 8),
                          JumpingDotsIndicator(
                            controller: _jumpingDotsController,
                          ),
                        ],
                      ),
                    );
                  }

                  final message = _messages[index];
                  final isUser = message['role'] == 'user';

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Row(
                      mainAxisAlignment: isUser
                          ? MainAxisAlignment.end
                          : MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              gradient: isUser
                                  ? const LinearGradient(
                                      colors: [
                                        Color(0xFF1ABC9C),
                                        Color(0xFF16A085),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : null,
                              color: isUser
                                  ? null
                                  : Theme.of(context).cardTheme.color,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(24),
                                topRight: const Radius.circular(24),
                                bottomLeft: isUser
                                    ? const Radius.circular(24)
                                    : const Radius.circular(4),
                                bottomRight: isUser
                                    ? const Radius.circular(4)
                                    : const Radius.circular(24),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 10,
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
                                      : Theme.of(
                                          context,
                                        ).textTheme.bodyLarge?.color,
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
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_showAssistantBubble && _latestAssistantMessage != null)
                Padding(
                  padding: const EdgeInsets.only(left: 24, bottom: 8),
                  child: _AssistantBubble(
                    message: _latestAssistantMessage!,
                    onClose: () => setState(() => _showAssistantBubble = false),
                  ),
                ).animate().fade().slideY(begin: 0.2, end: 0),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SafeArea(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark
                              ? Color(0xFF2D2D2D).withValues(alpha: 0.6)
                              : Colors.white.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : Colors.white.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 20,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                maxLength: 1000,
                                maxLines: null,
                                keyboardType: TextInputType.multiline,
                                textInputAction: TextInputAction.newline,
                                style: GoogleFonts.nunito(
                                  fontSize: 15,
                                  color: Theme.of(
                                    context,
                                  ).textTheme.bodyLarge?.color,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Type a message...',
                                  counterText: "",
                                  hintStyle: GoogleFonts.nunito(
                                    color: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium?.color,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 12,
                                  ),
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  fillColor: Colors.transparent,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(right: 6, left: 6),
                              child: Container(
                                width: 35,
                                height: 35,
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Color(0xFF1ABC9C),
                                      Color(0xFF16A085),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.send_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  padding: EdgeInsets.zero,
                                  onPressed: () =>
                                      _sendMessage(_controller.text),
                                ),
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
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1)),
        ),
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Definition toggle
            _ChatBottomButton(
              onTap: _openDefinitionPanel,
              icon: Icons.menu_book_rounded,
            ),
            const SizedBox(width: 16),
            // Assistant toggle with the actual assistant avatar
            GestureDetector(
              onTap: _openAssistantPanel,
              child: Container(
                height: 52,
                width: 52,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.04),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.15)
                        : Colors.black.withValues(alpha: 0.08),
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
          ],
        ),
      ),
    );
  }

  /// Show a dialog warning the user that if they finish the lesson,
  /// the session and progress will be lost.
  Future<bool> _showFinishWarning() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
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

class JumpingDotsIndicator extends StatelessWidget {
  final AnimationController controller;
  const JumpingDotsIndicator({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: controller,
          builder: (context, child) {
            final double offset =
                math.sin(
                  (controller.value * 2 * math.pi) + (index * math.pi / 2),
                ) *
                4;
            return Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              transform: Matrix4.translationValues(0, offset, 0),
              decoration: const BoxDecoration(
                color: Color(0xFF1ABC9C),
                shape: BoxShape.circle,
              ),
            );
          },
        );
      }),
    );
  }
}

class _ChatBottomButton extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;

  const _ChatBottomButton({required this.onTap, required this.icon});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        width: 52,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.04),
          shape: BoxShape.circle,
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.15)
                : Colors.black.withValues(alpha: 0.08),
            width: 2,
          ),
        ),
        child: Center(child: Icon(icon, size: 26)),
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  final String message;
  final VoidCallback onClose;
  const _AssistantBubble({required this.message, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.7,
      ),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1ABC9C),
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
