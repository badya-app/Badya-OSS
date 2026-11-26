import 'package:Badya/services/definition_controller.dart';
import 'package:Badya/services/user_preferences_service.dart';
import 'package:Badya/utils/logger.dart';
import 'package:Badya/widgets/custom_selection_toolbar.dart';
import 'package:Badya/widgets/content_bottom_bar.dart';
import 'package:Badya/widgets/reader_settings_sheet.dart';
import 'package:Badya/services/adk_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:Badya/utils/ui_utils.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'services/lesson_session_service.dart';
import 'chat_page.dart';
import 'dart:async';

class StoryPage extends StatefulWidget {
  final String story;
  final String subjectTitle;
  final String sessionId;
  final String description;
  final String topicId;
  final String userId;
  final String appName;
  final String language; // Added
  final String? nativeLanguage;
  final List<String>? wordsList;

  const StoryPage({
    super.key,
    required this.story,
    required this.subjectTitle,
    required this.sessionId,
    required this.description,
    required this.topicId,
    required this.userId,
    required this.appName,
    required this.language, // Added
    this.nativeLanguage,
    this.wordsList,
  });

  @override
  State<StoryPage> createState() => _StoryPageState();
}

class _StoryPageState extends State<StoryPage> {
  // Custom Toolbar state
  bool _isChatSessionReady = false;
  String? _selectedText;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // ─── Definition system ──────────────────────────────────────────────────
  final DefinitionController _definitionController = DefinitionController();

  // Scroll progress
  final ScrollController _scrollController = ScrollController();
  double _scrollProgress = 0.0;
  Timer? _scrollDebounceTimer;

  // Reader settings
  ReaderSettings _readerSettings = const ReaderSettings();

  // Streaming story state
  String _streamedStory = '';
  bool _isStreaming = true;
  final List<String> _imageUrls = [];
  String? _analysisResult;

  @override
  void initState() {
    super.initState();
    _loadReaderSettings();
    _streamedStory = widget.story;
    _definitionController.initialize(
      userId: widget.userId,
      language: widget.language,
      topicId: widget.topicId,
      lessonType: LessonTypes.storyWeaver,
    );
    _definitionController.addListener(() {
      if (mounted) setState(() {});
    });
    _startStoryStreaming();
    _scrollController.addListener(_updateScrollProgress);
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
    _scrollDebounceTimer?.cancel();
    _scrollController.dispose();
    _definitionController.dispose();
    super.dispose();
  }

  void _updateScrollProgress() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) {
      if (_scrollProgress != 0.0) {
        setState(() => _scrollProgress = 0.0);
      }
      return;
    }
    final progress = _scrollController.offset / maxScroll;
    final clamped = progress.clamp(0.0, 1.0);
    if ((clamped - _scrollProgress).abs() > 0.005) {
      setState(() => _scrollProgress = clamped);
      _scrollDebounceTimer?.cancel();
      _scrollDebounceTimer = Timer(const Duration(seconds: 1), () {
        // placeholder for any debounced side-effects (e.g., analytics)
      });
    }
  }

  Future<void> _startStoryStreaming() async {
    final adkService = AdkService();

    try {
      // 1. Check for existing session and story
      final sessionData = await adkService.fetchSession(
        appName: widget.appName,
        userId: widget.userId,
        sessionId: widget.sessionId,
      );

      if (sessionData != null && sessionData.history.isNotEmpty) {
        String existingStory = '';
        String? existingAnalysis;
        List<String> existingImages = [];

        for (var turn in sessionData.history) {
          if (turn.author == 'StoryWriter') {
            final content = turn.content;
            if (content is Map && content['parts'] is List) {
              for (var part in content['parts']) {
                if (part is Map) {
                  if (part['text'] != null) {
                    existingStory += part['text'];
                  } else if (part['functionResponse'] != null) {
                    final funcResp = part['functionResponse'];
                    if (funcResp['name'] == 'generate_image_tool') {
                      final imagePath = funcResp['response']?['image_path'];
                      if (imagePath != null) {
                        final imageUrl = adkService.getArtifactUrl(
                          appName: widget.appName,
                          userId: widget.userId,
                          sessionId: widget.sessionId,
                          artifactName: imagePath,
                          version: 0,
                        );
                        existingImages.add(imageUrl);
                        existingStory += '\n\n![Image]($imageUrl)\n\n';
                      }
                    }
                  }
                }
              }
            }
          } else if (turn.author == 'StoryAnalyzer') {
            final content = turn.content;
            if (content is Map && content['parts'] is List) {
              for (var part in content['parts']) {
                if (part is Map && part['text'] != null) {
                  existingAnalysis = part['text'];
                }
              }
            }
          }
        }

        if (existingStory.isNotEmpty) {
          if (mounted) {
            setState(() {
              _streamedStory = existingStory;
              _analysisResult = existingAnalysis;
              _imageUrls.addAll(existingImages);
              _isStreaming = false;
            });
          }
          return;
        }
      }

      await for (var event in adkService.runAgentSseStream(
        appName: widget.appName,
        userId: widget.userId,
        sessionId: widget.sessionId,
        message: 'Generate the story.',
      )) {
        Logger.info('SSE event: $event');
        if (!mounted) break;

        // Check if this is from StoryWriter - author is at the top level
        final author = event['author'];
        // Only process partial events to avoid duplication
        final isPartial = event['partial'] == true;

        if (author == 'StoryWriter' && isPartial) {
          final parts = event['content']?['parts'] as List<dynamic>?;
          if (parts != null) {
            for (var part in parts) {
              // Handle text content
              if (part['text'] != null) {
                setState(() {
                  _streamedStory += part['text'];
                });
              }
            }
          }
        }

        // Handle image artifacts from non-partial events (when tool completes)
        if (author == 'StoryWriter' && !isPartial) {
          final parts = event['content']?['parts'] as List<dynamic>?;
          if (parts != null) {
            for (var part in parts) {
              if (part['functionResponse'] != null) {
                final funcResp = part['functionResponse'];
                if (funcResp['name'] == 'generate_image_tool') {
                  final imagePath = funcResp['response']?['image_path'];
                  if (imagePath != null) {
                    // Fetch the artifact and get base64 data
                    final imageUrl = adkService.getArtifactUrl(
                      appName: widget.appName,
                      userId: widget.userId,
                      sessionId: widget.sessionId,
                      artifactName: imagePath,
                      version: 0,
                    );

                    // Store the URL for later fetching
                    setState(() {
                      _imageUrls.add(imageUrl);
                      // Use a placeholder that will be replaced by the custom image builder
                      _streamedStory += '\n\n![Image]($imageUrl)\n\n';
                    });
                  }
                }
              }
            }
          }
        }

        // Capture analysis result from StoryAnalyzer
        if (author == 'StoryAnalyzer' && !isPartial) {
          final parts = event['content']?['parts'] as List<dynamic>?;
          if (parts != null) {
            for (var part in parts) {
              if (part is Map && part['text'] != null) {
                setState(() {
                  _analysisResult = part['text'];
                });
              }
            }
          }
        }
      }
    } catch (e) {
      Logger.error('Error streaming story', e);
      if (mounted) {
        UiUtils.showErrorDialog(
          context,
          message:
              'It seems we hit a snag while weaving your story. Please check your connection and try again.',
          error: e.toString(),
          onDismiss: () => Navigator.pop(context),
          onStay: () {
            setState(() {
              _isStreaming = false;
            });
          },
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isStreaming = false;
        });
      }
    }
  }

  Future<Widget> _loadArtifactImage(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        // Extract base64 data from the artifact response
        final base64Data = jsonData['inlineData']?['data'];
        if (base64Data != null) {
          final imageBytes = base64Decode(base64Data);
          return Image.memory(imageBytes, fit: BoxFit.cover);
        }
      }
      throw Exception('Failed to load image: ${response.statusCode}');
    } catch (e) {
      Logger.error('Error loading artifact image', e);
      rethrow;
    }
  }

  Future<void> _startChat(BuildContext context) async {
    if (!context.mounted) return;

    if (_isChatSessionReady) {
      final chatPage = ChatPage(
        appName: 'text_chat',
        sessionId: widget.sessionId,
        userId: widget.userId,
        initialAgent: 'QuizPresenter',
        initialStory: _streamedStory,
        storySubject: widget.subjectTitle,
        topicId: widget.topicId,
        analysisResult: _analysisResult,
        language: widget.language,
        nativeLanguage: widget.nativeLanguage,
        description: widget.description,
        wordsList: widget.wordsList,
        sessionIdsToDelete: [
          widget.sessionId,
          if (_definitionController.sessionId != null)
            _definitionController.sessionId!,
        ],
        currentLanguage: widget.language,
        lessonType: LessonTypes.storyWeaver,
      );
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => chatPage),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) =>
          const Center(child: CircularProgressIndicator()),
    );

    await Future.delayed(const Duration(seconds: 2));

    if (!context.mounted) return;
    Navigator.pop(context);

    if (!context.mounted) return;
    setState(() {
      _isChatSessionReady = true;
    });

    final chatPage = ChatPage(
      appName: 'text_chat',
      sessionId: widget.sessionId,
      userId: widget.userId,
      initialAgent: 'QuizPresenter',
      initialStory: _streamedStory,
      storySubject: widget.subjectTitle,
      topicId: widget.topicId,
      analysisResult: _analysisResult,
      language: widget.language,
      nativeLanguage: widget.nativeLanguage,
      description: widget.description,
      wordsList: widget.wordsList,
      sessionIdsToDelete: [
        widget.sessionId,
        if (_definitionController.sessionId != null)
          _definitionController.sessionId!,
      ],
      currentLanguage: widget.language,
      lessonType: LessonTypes.storyWeaver,
    );

    Navigator.push(context, MaterialPageRoute(builder: (context) => chatPage));
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

  void _showReaderSettings() {
    showReaderSettingsSheet(
      context,
      current: _readerSettings,
      language: widget.language,
      onChanged: _updateReaderSettings,
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextStyle bodyTextStyle = resolveFontStyle(
      _readerSettings.fontFamily,
      fontSize: _readerSettings.fontSize,
      height: _readerSettings.lineHeight,
      fontWeight: resolveFontWeight(_readerSettings.fontWeightIndex),
      color: Theme.of(context).textTheme.bodyLarge?.color,
    );

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
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
      appBar: AppBar(
        title: Text(
          widget.subjectTitle,
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          if (!_isStreaming)
            Container(
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00897B), Color(0xFF26A69A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF26A69A).withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _startChat(context),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_stories_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Practice',
                          style: TextStyle(
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
          const SizedBox(width: 8),
        ],
      ),
      endDrawer: _definitionController.buildEndDrawer(
        onClose: () => _scaffoldKey.currentState?.closeEndDrawer(),
      ),
      body: Column(
        children: [
          // Thin progress bar at the top of the story area
          Container(
            height: 3,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: _scrollProgress,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1ABC9C), Color(0xFF3498DB)],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(
                left: 16.0,
                right: 16.0,
                bottom: 8.0,
              ),
              child: SingleChildScrollView(
                child: SelectionArea(
                  onSelectionChanged: (content) {
                    _selectedText = content?.plainText;
                  },
                  contextMenuBuilder: (ctx, selectableRegionState) {
                    return CustomSelectionToolbar(
                      anchors: selectableRegionState.contextMenuAnchors,
                      buttonItems: selectableRegionState.contextMenuButtonItems,
                      onHide: () => selectableRegionState.hideToolbar(),
                      onCustomAction: (action) {
                        _handleAction(context, action, _selectedText ?? '');
                      },
                    );
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MarkdownBody(
                        data: _streamedStory,
                        selectable: false,
                        styleSheet: MarkdownStyleSheet(
                          p: bodyTextStyle,
                          textAlign: resolveWrapAlignment(
                            _readerSettings.textAlignIndex,
                          ),
                          h1: GoogleFonts.merriweather(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Theme.of(
                              context,
                            ).textTheme.titleLarge?.color,
                          ),
                          h2: GoogleFonts.merriweather(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Theme.of(
                              context,
                            ).textTheme.titleLarge?.color,
                          ),
                          h3: GoogleFonts.merriweather(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(
                              context,
                            ).textTheme.titleLarge?.color,
                          ),
                        ),
                        sizedImageBuilder: (config) {
                          // Fetch and decode base64 image from artifact endpoint
                          return FutureBuilder<Widget>(
                            future: _loadArtifactImage(config.uri.toString()),
                            builder: (context, snapshot) {
                              if (snapshot.hasData) {
                                return snapshot.data!;
                              } else if (snapshot.hasError) {
                                return Container(
                                  width: config.width ?? 300,
                                  height: config.height ?? 200,
                                  color: Colors.grey[300],
                                  child: Center(
                                    child: Text(
                                      'Error loading image',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                );
                              }
                              return _AnimatedImagePlaceholder(
                                width: config.width ?? 300,
                                height: config.height ?? 200,
                              );
                            },
                          );
                        },
                      ),
                      if (_isStreaming)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16.0),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Theme.of(context).primaryColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Generating story...',
                                style: GoogleFonts.notoSerif(
                                  fontSize: 14,
                                  fontStyle: FontStyle.italic,
                                  color: Theme.of(
                                    context,
                                  ).textTheme.bodyMedium?.color,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ContentBottomBar(
            onDefinitionTap: () => _definitionController.openPanel(
              () => _scaffoldKey.currentState?.openEndDrawer(),
            ),
            onFontTap: _showReaderSettings,
            showFontActive: false,
          ),
        ],
      ),
    ),
    );
  }
}

class _AnimatedImagePlaceholder extends StatefulWidget {
  final double width;
  final double height;

  const _AnimatedImagePlaceholder({required this.width, required this.height});

  @override
  State<_AnimatedImagePlaceholder> createState() =>
      _AnimatedImagePlaceholderState();
}

class _AnimatedImagePlaceholderState extends State<_AnimatedImagePlaceholder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(
                  const Color(0xFF1ABC9C),
                  const Color(0xFF3498DB),
                  _controller.value,
                )!,
                Color.lerp(
                  const Color(0xFF3498DB),
                  const Color(0xFF9B59B6),
                  _controller.value,
                )!,
                Color.lerp(
                  const Color(0xFF9B59B6),
                  const Color(0xFF1ABC9C),
                  _controller.value,
                )!,
              ],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 8),
                Text(
                  'Loading image...',
                  style: GoogleFonts.notoSerif(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
