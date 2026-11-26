import 'dart:convert';
import 'dart:io';
import 'package:Badya/widgets/reader_settings_sheet.dart';
import 'package:Badya/services/media_service.dart';
import 'package:Badya/services/user_preferences_service.dart';
import 'package:Badya/voice_chat_page.dart';
import 'package:Badya/widgets/custom_selection_toolbar.dart';
import 'package:Badya/widgets/definition_history_panel.dart';
import 'package:Badya/utils/language_service.dart';
import 'package:Badya/utils/logger.dart';
import 'package:Badya/services/adk_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:Badya/services/lesson_session_service.dart';
import 'package:Badya/services/notification_service.dart';
import 'package:Badya/utils/ui_utils.dart';
import 'package:Badya/widgets/word_unscramble_game.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VideoPage extends StatefulWidget {
  final String subjectTitle;
  final String description;
  final String topicId;
  final String sessionId;
  final String userId;
  final String appName;
  final String language;
  final String? nativeLanguage;
  final List<String>? wordsList;

  /// Tracks the currently active topic ID if the user is currently on the VideoPage.
  static String? activeTopicId;

  const VideoPage({
    super.key,
    required this.subjectTitle,
    required this.description,
    required this.topicId,
    required this.sessionId,
    required this.userId,
    required this.appName,
    required this.language,
    this.nativeLanguage,
    this.wordsList,
  });

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> with WidgetsBindingObserver {
  late final Player _player = Player();
  VideoController? _controller;
  List<Map<String, dynamic>> _transcript = [];
  bool _isGenerating = true;
  String? _errorMessage;
  int _currentTranscriptIndex = -1;
  double _speed = 1.0;
  bool _showTranscript = true;
  String? _analysisResult;

  // Keys for accurate scrolling
  List<GlobalKey> _itemKeys = [];
  final Map<int, int> _selectionKeys = {};

  // Definition state
  String? _definitionSessionId;
  final List<Map<String, String>> _definitionHistory = [];
  Stream<String>? _definitionStream;
  String? _currentWord;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final String _userId;
  bool _showDefinitionPanel = false;

  // Reader settings
  ReaderSettings _readerSettings = const ReaderSettings();

  // Scroll controller for transcript
  final ScrollController _scrollController = ScrollController();
  int? _targetScrollIndex;

  @override
  void initState() {
    super.initState();
    VideoPage.activeTopicId = widget.topicId;
    WidgetsBinding.instance.addObserver(this);
    MediaService.ensureInitialized();
    _userId = widget.userId;
    _loadReaderSettings();
    _initializeSessions();
    _startVideoGeneration();
  }

  @override
  void deactivate() {
    _player.stop();
    super.deactivate();
  }

  @override
  void dispose() {
    if (VideoPage.activeTopicId == widget.topicId) {
      VideoPage.activeTopicId = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    _player.stop();
    _player.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _player.pause();
    }
  }

  Future<void> _initializeSessions() async {
    final sessionService = LessonSessionService();
    // Deterministic discovery
    final snapshot = sessionService.getSession(
      topicId: widget.topicId,
      lessonType: LessonTypes.echoChamber,
    );

    if (snapshot.definitionSessionId != null) {
      await _createDefinitionSession(snapshot.definitionSessionId!);
    }
  }

  Future<void> _createDefinitionSession(String sessionId) async {
    final languageService = LanguageService();
    final userPrefs = UserPreferencesService();
    final dialects = await userPrefs.getLearningDialects();
    String language = widget.language;
    final dialect = dialects[widget.language] ?? '';
    if (dialect.isNotEmpty) {
      language = '${widget.language} ($dialect)';
    }

    final result = await languageService.createSession(
      appName: 'definition_agent',
      userId: _userId,
      sessionId: sessionId,
      state: {'language': language},
    );

    if (result != null && mounted) {
      setState(() {
        _definitionSessionId = result.sessionId;
      });

      if (result.isResumed) {
        // Fetch history to populate _definitionHistory
        final sessionData = await AdkService().fetchSession(
          appName: 'definition_agent',
          userId: _userId,
          sessionId: result.sessionId,
        );
        if (sessionData != null) {
          for (var i = 0; i < sessionData.history.length; i++) {
            final turn = sessionData.history[i];
            if (turn.author == 'user') {
              final parts = turn.content?['parts'] as List?;
              if (parts != null && parts.isNotEmpty) {
                final word = parts[0]['text'] as String?;
                if (word != null) {
                  // Find the corresponding agent response
                  if (i + 1 < sessionData.history.length) {
                    final nextTurn = sessionData.history[i + 1];
                    if (nextTurn.author == 'definition_agent') {
                      final resParts = nextTurn.content?['parts'] as List?;
                      if (resParts != null && resParts.isNotEmpty) {
                        final definition = resParts[0]['text'] as String?;
                        if (definition != null && mounted) {
                          setState(() {
                            _definitionHistory.add({
                              'word': word,
                              'definition': definition,
                            });
                          });
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  Future<void> _startVideoGeneration() async {
    final adkService = AdkService();

    try {
      // 1. Check for existing session and video
      final sessionData = await adkService.fetchSession(
        appName: widget.appName,
        userId: widget.userId,
        sessionId: widget.sessionId,
      );

      if (sessionData != null && sessionData.history.isNotEmpty) {
        // Look for the last successful video generation turn
        for (var turn in sessionData.history.reversed) {
          final author = turn.author;
          final parts = turn.content?['parts'] as List?;
          if (author == 'VideoStoryAgent' && parts != null) {
            for (var part in parts) {
              if (part['functionResponse'] != null &&
                  part['functionResponse']['name'] == 'video_tool') {
                final response = part['functionResponse']['response'];
                if (response != null && response['status'] == 'success') {
                  // Found existing video — reconstruct the event map for _processVideoEvent
                  _processVideoEvent({
                    'author': turn.author,
                    'content': turn.content,
                  });
                  return;
                }
              }
            }
          }
        }
      }

      // 2. If not found, trigger generation
      await for (var event in adkService.runAgentSseStream(
        appName: widget.appName,
        userId: widget.userId,
        sessionId: widget.sessionId,
        message: 'Generate the video.',
      )) {
        if (!mounted) break;

        _processVideoEvent(event);
      }
    } catch (e) {
      Logger.error('Error generating video', e);
      _handleVideoFailure('We had some trouble preparing your video. Please check your connection and try again.', errorDetails: e.toString());
    }
  }

  Future<void> _handleVideoFailure(String message, {String? errorDetails}) async {
    if (!mounted) return;

    setState(() {
      _isGenerating = false;
      _errorMessage = message;
    });

    UiUtils.showErrorDialog(
      context,
      message: message,
      error: errorDetails,
      onDismiss: () => Navigator.pop(context),
      onStay: () {},
    );
  }

  void _processVideoEvent(Map<String, dynamic> event) async {
    final adkService = AdkService();
    final author = event['author'];
    final isPartial = event['partial'] == true;

    if (author == 'VideoStoryAgent' && !isPartial) {
      final parts = event['content']?['parts'] as List<dynamic>?;
      if (parts != null) {
        for (var part in parts) {
          // 1. Handle Function Response (Artifact URL)
          if (part['functionResponse'] != null) {
            final funcResp = part['functionResponse'];
            if (funcResp['name'] == 'video_tool') {
              final response = funcResp['response'];
              if (response != null) {
                if (response['status'] == 'failed') {
                  final errorMsg = response['error'] as String? ?? 'Video generation failed.';
                  Logger.error('Video generation tool failed: $errorMsg');
                  await _handleVideoFailure('Failed to generate video. Please try again.', errorDetails: errorMsg);
                  return;
                } else if (response['status'] == 'success') {
                  final videoUrlDirect = response['video_url'] as String?;
                  final videoPath = response['video_path'];
                  final transcriptRaw = response['transcript'] as List<dynamic>?;

                  List<Map<String, dynamic>> processedTranscript = [];
                  if (transcriptRaw != null) {
                    for (var item in transcriptRaw) {
                      processedTranscript.add({
                        'text': item['text'],
                        'start': (item['start'] as num).toDouble(),
                        'end': (item['end'] as num).toDouble(),
                      });
                    }
                  }

                  if (videoUrlDirect != null && videoUrlDirect.isNotEmpty) {
                    // Direct GCS streaming (Option 3) — bypasses Cloud Run 32MB limit & base64
                    // Replace fallback /unknown/ placeholders with the actual userId and sessionId if needed
                    String effectiveUrl = videoUrlDirect;
                    if (effectiveUrl.contains('/unknown/')) {
                      effectiveUrl = effectiveUrl.replaceFirst(
                        '/unknown/unknown/',
                        '/${widget.userId}/${widget.sessionId}/',
                      );
                    }
                    await _initializeVideo(effectiveUrl, processedTranscript);
                    await _maybeShowVideoReadyNotification();
                  } else if (videoPath != null) {
                    // Fallback for local development
                    final videoUrl = adkService.getArtifactUrl(
                      appName: widget.appName,
                      userId: widget.userId,
                      sessionId: widget.sessionId,
                      artifactName: videoPath,
                      version: 0,
                    );

                    final videoDataPath = await _fetchAndDecodeVideo(videoUrl);
                    if (videoDataPath != null) {
                      await _initializeVideo(videoDataPath, processedTranscript);
                      await _maybeShowVideoReadyNotification();
                    } else {
                      await _handleVideoFailure('Could not download video. Please try again.');
                    }
                  }
                }
              }
            }
          }

          // 2. Handle Inline Data (Base64 Video)
          if (part['inlineData'] != null) {
            final inlineData = part['inlineData'];
            final mimeType = inlineData['mimeType'] as String?;
            final base64Data = inlineData['data'] as String?;

            if (base64Data != null &&
                mimeType != null &&
                mimeType.startsWith('video/')) {
              final tempPath = await _saveVideoBytes(base64Data, mimeType);
              await _initializeVideo(tempPath, []);
              await _maybeShowVideoReadyNotification();
            }
          }
        }
      }
    }

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

  Future<String?> _fetchAndDecodeVideo(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        final base64Data = jsonData['inlineData']?['data'];
        final mimeType = jsonData['inlineData']?['mimeType'] ?? 'video/mp4';
        if (base64Data != null) {
          return await _saveVideoBytes(base64Data, mimeType);
        }
      }
    } catch (e) {
      Logger.error("Error fetching video artifact", e);
    }
    return null;
  }

  Future<String> _saveVideoBytes(String base64Data, String mimeType) async {
    // Clean Base64 (Standardize URL-safe Base64)
    String normalized = base64Data.replaceAll('-', '+').replaceAll('_', '/');
    while (normalized.length % 4 != 0) {
      normalized += '=';
    }
    final bytes = base64Decode(normalized);

    final extension = mimeType.split('/').last;
    final tempDir = await getTemporaryDirectory();
    final file = File(
      '${tempDir.path}/video_${DateTime.now().millisecondsSinceEpoch}.$extension',
    );
    await file.writeAsBytes(bytes);
    return file.path;
  }

  Future<void> _initializeVideo(
    String url,
    List<Map<String, dynamic>> transcript,
  ) async {
    _controller = VideoController(_player);
    _player.open(Media(url));
    _player.stream.position.listen(_onVideoTick);
    _player.stream.error.listen((event) {
      Logger.error('MediaKit Error', event as Object?);
      if (mounted) {
        setState(() {
          _errorMessage = 'Error loading video: $event\nURL: $url';
        });
      }
    });
    Logger.info('Initializing video with URL: $url');

    if (mounted) {
      setState(() {
        _transcript = transcript;
        _itemKeys = List.generate(transcript.length, (index) => GlobalKey());
        _isGenerating = false;
      });
      _clearUnscrambleLoadingState();
    }
  }

  Future<void> _clearUnscrambleLoadingState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('unscramble_loading_state_${widget.sessionId}');
      await prefs.remove('unscramble_loading_state_${widget.topicId}');
    } catch (_) {}
  }

  Future<void> _maybeShowVideoReadyNotification() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final toggle = prefs.getBool('notification_toggle_video_ready') ?? true;
      if (toggle) {
        final notificationService = NotificationService();
        await notificationService.showVideoReadyNotification(
          topicTitle: widget.subjectTitle,
          topicId: widget.topicId,
          description: widget.description,
          language: widget.language,
          nativeLanguage: widget.nativeLanguage,
          wordsList: widget.wordsList,
          sessionId: widget.sessionId,
        );
      }
    } catch (e) {
      Logger.error('Failed to show video-ready notification', e);
    }
  }

  void _onVideoTick(Duration position) {
    final positionInSeconds = position.inMilliseconds / 1000.0;

    int newIndex = -1;
    for (int i = 0; i < _transcript.length; i++) {
      if (positionInSeconds >= _transcript[i]['start'] &&
          positionInSeconds <= _transcript[i]['end']) {
        newIndex = i;
        break;
      }
    }

    if (newIndex != _currentTranscriptIndex && newIndex != -1) {
      setState(() {
        _currentTranscriptIndex = newIndex;
      });
      _scrollToIndex(newIndex);
    }
  }

  void _scrollToIndex(int index, {Duration? duration, int retryCount = 0}) {
    if (index < 0 || index >= _itemKeys.length) return;
    _targetScrollIndex = index;

    if (!_scrollController.hasClients) {
      if (retryCount < 3) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _targetScrollIndex == index) {
            _scrollToIndex(index, duration: duration, retryCount: retryCount + 1);
          }
        });
      }
      return;
    }

    final key = _itemKeys[index];
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: duration ?? const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.5,
      );
      return;
    }

    if (retryCount >= 3) return;

    // Item is off-screen (not yet mounted by ListView.builder).
    // Measure rendered item height if possible, fallback to 68.0.
    double itemHeight = 68.0;
    for (final k in _itemKeys) {
      final c = k.currentContext;
      if (c != null) {
        final ro = c.findRenderObject();
        if (ro is RenderBox && ro.hasSize && ro.size.height > 0) {
          itemHeight = ro.size.height;
          break;
        }
      }
    }

    final pos = _scrollController.position;
    final maxScroll = pos.hasContentDimensions ? pos.maxScrollExtent : 0.0;
    double estimatedOffset = index * itemHeight;
    if (maxScroll > 0) {
      estimatedOffset = estimatedOffset.clamp(0.0, maxScroll);
    }

    _scrollController.jumpTo(estimatedOffset);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_targetScrollIndex == index) {
        _scrollToIndex(index, duration: duration, retryCount: retryCount + 1);
      }
    });
  }

  void _finishAndGoToVoice() {
    _player.stop();
    final storyText = _transcript.map((item) => item['text']).join(' ');

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VoiceChatPage(
          subjectTitle: widget.subjectTitle,
          description: widget.description,
          agentName: 'Discussion Bot',
          appName: 'voice_chat',
          topicId: widget.topicId,
          storySubject: widget.subjectTitle,
          story: storyText,
          analysisResult: _analysisResult,
          learningLanguage: widget.language,
          nativeLanguage: widget.nativeLanguage,
          userId: widget.userId,
          wordsList: widget.wordsList,
          sessionIdsToDelete: [
            widget.sessionId,
            if (_definitionSessionId != null) _definitionSessionId!,
          ],
          currentLanguage: widget.language,
          lessonType: LessonTypes.echoChamber,
        ),
      ),
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

  // ─── Video player ───────────────────────────────────────────────────
  Widget _buildVideoPlayerWidget() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          width: double.infinity,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: Colors.black,
              child: _controller != null
                  ? Video(controller: _controller!)
                  : const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Transcript list ──────────────────────────────────────────────────
  Widget _buildTranscriptList() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
        ),
      ),
      child: ListView.builder(
        controller: _scrollController,
        cacheExtent: 1000.0,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: _transcript.length,
        itemBuilder: (context, index) {
          final item = _transcript[index];
          final isActive = index == _currentTranscriptIndex;
          final text = item['text']?.toString() ?? '';
          final rawStart = (item['start'] as num?)?.toDouble() ?? 0;

          return GestureDetector(
            onTap: () {
              _player.seek(Duration(milliseconds: (rawStart * 1000).toInt()));
              _player.play();
            },
            child: Container(
              key: _itemKeys.isNotEmpty && index < _itemKeys.length
                  ? _itemKeys[index]
                  : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.symmetric(vertical: 2),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isActive
                      ? theme.colorScheme.primary.withValues(alpha: 0.08)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: isActive
                      ? Border(
                          left: BorderSide(
                            color: theme.colorScheme.primary,
                            width: 3,
                          ),
                        )
                      : null,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Timestamp badge
                    Container(
                      margin: const EdgeInsets.only(right: 10, top: 2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: isActive
                            ? theme.colorScheme.primary
                            : (isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.06)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _formatDuration(
                          Duration(milliseconds: (rawStart * 1000).toInt()),
                        ),
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isActive
                              ? (isDark ? Colors.black : Colors.white)
                              : (isDark ? Colors.white54 : Colors.black45),
                        ),
                      ),
                    ),
                    // Transcript text
                    Expanded(
                      child: SelectableText(
                        text,
                        key: ValueKey(
                          'st_${index}_${_selectionKeys[index] ?? 0}',
                        ),
                        textAlign: resolveTextAlign(
                          _readerSettings.textAlignIndex,
                        ),
                        style: resolveFontStyle(
                          _readerSettings.fontFamily,
                          fontSize: _readerSettings.fontSize,
                          fontWeight: isActive
                              ? FontWeight.w700
                              : resolveFontWeight(
                                  _readerSettings.fontWeightIndex,
                                ),
                          color: isActive
                              ? theme.colorScheme.primary
                              : (isDark ? Colors.white70 : Colors.black87),
                          height: _readerSettings.lineHeight,
                        ),
                        contextMenuBuilder: (ctx, editableTextState) {
                          final selection =
                              editableTextState.textEditingValue.selection;
                          final textBody =
                              editableTextState.textEditingValue.text;
                          final selText = selection.textInside(textBody);
                          return CustomSelectionToolbar(
                            anchors: editableTextState.contextMenuAnchors,
                            buttonItems:
                                editableTextState.contextMenuButtonItems,
                            onHide: () => editableTextState.hideToolbar(),
                            onCustomAction: (action) {
                              CustomSelectionToolbar.handleAction(
                                context,
                                action,
                                selText,
                                learningLanguage: widget.language,
                                nativeLanguage: widget.nativeLanguage,
                                onDefinition: () {
                                  setState(() {
                                    _currentWord = selText;
                                    _definitionStream = LanguageService()
                                        .define(
                                          selText,
                                          sessionId: _definitionSessionId,
                                          userId: _userId,
                                          targetLanguage: widget.nativeLanguage,
                                          sourceLanguage: widget.language,
                                        );
                                    _showDefinitionPanel = true;
                                  });
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    _scaffoldKey.currentState?.openEndDrawer();
                                  });
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Generating view ──────────────────────────────────────────────────
  Widget _buildGeneratingView() {
    return WordUnscrambleGame(
      words: widget.wordsList ?? [],
      language: widget.language,
      sessionId: widget.sessionId,
      topicId: widget.topicId,
      videoReady: !_isGenerating && _errorMessage == null,
      onVideoReady: () {
        // The video is ready — just rebuild to show the video player
        setState(() {});
      },
      onBack: () => Navigator.pop(context),
    );
  }

  // ─── Error view ───────────────────────────────────────────────────────
  Widget _buildErrorView() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: theme.colorScheme.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.videocam_off_rounded,
                size: 40,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Video Generation Incomplete',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: theme.textTheme.titleLarge?.color,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'We could not finish generating your video. Please try again.',
              style: GoogleFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white70 : Colors.black87,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _errorMessage = null;
                  _isGenerating = true;
                });
                _startVideoGeneration();
              },
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.secondary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: Icon(
                Icons.arrow_back_rounded,
                size: 18,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              label: Text(
                'Back to Lessons',
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Video controls ───────────────────────────────────────────────────
  Widget _buildVideoControls() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreamBuilder<Duration>(
            stream: _player.stream.position,
            builder: (context, snapshot) {
              final position = snapshot.data ?? const Duration();
              final duration = _player.state.duration;
              return Column(
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      activeTrackColor: theme.colorScheme.secondary,
                      inactiveTrackColor: theme.colorScheme.secondary
                          .withValues(alpha: 0.2),
                      thumbColor: theme.colorScheme.secondary,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 14,
                      ),
                      overlayColor: theme.colorScheme.secondary.withValues(
                        alpha: 0.2,
                      ),
                    ),
                    child: Slider(
                      value: position.inMilliseconds.toDouble().clamp(
                        0.0,
                        duration.inMilliseconds.toDouble(),
                      ),
                      min: 0,
                      max: duration.inMilliseconds == 0
                          ? 1.0
                          : duration.inMilliseconds.toDouble(),
                      onChanged: (value) {
                        final pos = Duration(milliseconds: value.toInt());
                        _player.seek(pos);
                        _onVideoTick(pos);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(position),
                          style: GoogleFonts.nunito(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                        Text(
                          _formatDuration(duration),
                          style: GoogleFonts.nunito(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PopupMenuButton<double>(
                initialValue: _speed,
                onSelected: (v) {
                  setState(() => _speed = v);
                  _player.setRate(v);
                },
                itemBuilder: (context) => [2.0, 1.5, 1.25, 1.0, 0.75, 0.5]
                    .map((v) => PopupMenuItem(value: v, child: Text('${v}x')))
                    .toList(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black).withValues(
                      alpha: 0.08,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.speed_rounded,
                        size: 16,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${_speed}x',
                        style: GoogleFonts.nunito(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              StreamBuilder<bool>(
                stream: _player.stream.playing,
                builder: (context, snapshot) {
                  final isPlaying = snapshot.data ?? false;
                  return GestureDetector(
                    onTap: () => isPlaying ? _player.pause() : _player.play(),
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.secondary.withValues(
                              alpha: 0.3,
                            ),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  );
                },
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                  _showTranscript
                      ? Icons.subtitles_rounded
                      : Icons.subtitles_off_rounded,
                  color: _showTranscript
                      ? theme.colorScheme.secondary
                      : (isDark ? Colors.white38 : Colors.black26),
                ),
                onPressed: () =>
                    setState(() => _showTranscript = !_showTranscript),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Bottom bar (definition + font) ───────────────────────────────────
  Widget _buildBottomBar() {
    final theme = Theme.of(context);
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
            _ControlCircleButton(
              onTap: () {
                setState(() => _showDefinitionPanel = true);
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _scaffoldKey.currentState?.openEndDrawer(),
                );
              },
              icon: Icons.menu_book_rounded,
            ),
            const SizedBox(width: 16),
            // Font size & family
            _ControlCircleButton(
              onTap: _showReaderSettings,
              icon: Icons.text_fields_outlined,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _player.stop();
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        onEndDrawerChanged: (isOpen) {
          if (!isOpen) {
            setState(() => _definitionStream = null);
          }
        },
        endDrawer: _showDefinitionPanel
            ? DefinitionHistoryPanel(
                definitionStream: _definitionStream,
                history: _definitionHistory,
                initialWord: _currentWord,
                onClose: () => _scaffoldKey.currentState?.closeEndDrawer(),
              )
            : null,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            if (!_isGenerating)
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
                    onTap: _finishAndGoToVoice,
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
        body: SafeArea(
          child: _isGenerating
              ? _buildGeneratingView()
              : _errorMessage != null
              ? _buildErrorView()
              : Column(
                  children: [
                    if (_controller != null) _buildVideoPlayerWidget(),
                    const SizedBox(height: 16),
                    if (_showTranscript)
                      Expanded(child: _buildTranscriptList()),
                    if (!_showTranscript) const Spacer(),
                    _buildVideoControls(),
                    _buildBottomBar(),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ControlCircleButton extends StatelessWidget {
  final VoidCallback onTap;
  final IconData? icon;

  const _ControlCircleButton({
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        width: 52,
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.05),
            width: 2,
          ),
        ),
        child: Center(
          child: Icon(
            icon,
            color: Theme.of(context).iconTheme.color,
            size: 26,
          ),
        ),
      ),
    );
  }
}
