import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:Badya/utils/logger.dart';
import 'package:Badya/services/media_service.dart';
import 'package:Badya/services/import_service.dart';
import 'package:Badya/widgets/page_skeleton.dart';
import 'package:Badya/widgets/video_player_widget.dart';
import 'package:Badya/widgets/video_controls_bar.dart';
import 'package:Badya/widgets/transcript_list_view.dart';
import 'package:Badya/widgets/transcript_skeleton.dart';
import 'package:Badya/widgets/content_bottom_bar.dart';
import 'package:Badya/utils/constants.dart';
import 'package:Badya/services/adk_service.dart';
import 'package:Badya/widgets/custom_dialog.dart';
import 'package:Badya/widgets/reader_settings_sheet.dart';

/// Encapsulates video playback, transcript loading & synchronization,
/// seek bar, and playback controls for imported video content.
class ImportedVideoView extends StatefulWidget {
  final String importId;
  final String? contentId;
  final Map<String, dynamic> lesson;
  final String userId;
  final String language;
  final String? nativeLanguage;
  final String? sourceUrl;
  final String? originalUrl;
  final ReaderSettings readerSettings;
  final void Function(BuildContext context, String action, String text) onAction;
  final VoidCallback onDefinitionTap;
  final VoidCallback onFontTap;
  final ValueChanged<double>? onProgressChanged;
  final VoidCallback? onCompleted;

  const ImportedVideoView({
    super.key,
    required this.importId,
    this.contentId,
    required this.lesson,
    required this.userId,
    required this.language,
    this.nativeLanguage,
    this.sourceUrl,
    this.originalUrl,
    required this.readerSettings,
    required this.onAction,
    required this.onDefinitionTap,
    required this.onFontTap,
    this.onProgressChanged,
    this.onCompleted,
  });

  @override
  State<ImportedVideoView> createState() => ImportedVideoViewState();
}

class ImportedVideoViewState extends State<ImportedVideoView>
    with WidgetsBindingObserver {
  late final Player _player;
  late final VideoController _controller;
  bool _playerInitialized = false;

  List<Map<String, dynamic>> _rawTranscript = [];
  List<Map<String, dynamic>> _transcript = [];
  bool _isLoading = true;
  String? _errorMessage;
  int _currentTranscriptIndex = -1;
  double _speed = 1.0;
  bool _showTranscript = true;
  bool _isPlaying = false;
  final List<GlobalKey> _itemKeys = [];
  bool _isInitialSeeking = true;
  double _lastPositionInSeconds = 0.0;
  double _maxPositionReached = 0.0;
  final double _syncOffset = 0.0;
  final double _lookahead = 0.1;
  final double _mergeThreshold = 2.5;
  String? _selectedTranscriptCode;
  bool _isTranscriptLoading = false;
  List<Map<String, dynamic>> _availableTranscriptsLocal = [];
  late final String _preferredCaptionCode;
  late final ScrollController _transcriptScrollController;
  int? _targetScrollIndex;

  DateTime _lastProgressSave = DateTime.now();
  Duration? _initialSeekPosition;
  Duration? _videoDuration;
  ImportService get _importService => ImportService();

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration>? _durationSub;

  double get _startTime {
    final st = widget.lesson['start_time'];
    if (st is num) return st.toDouble();
    if (st is String) return double.tryParse(st) ?? 0.0;
    return 0.0;
  }

  double? get _endTime {
    final et = widget.lesson['end_time'];
    if (et is num) return et.toDouble();
    if (et is String) return double.tryParse(et);
    return null;
  }

  double? get _lastPosition {
    final lp = widget.lesson['last_position'];
    if (lp is num) return lp.toDouble();
    if (lp is String) return double.tryParse(lp);
    return null;
  }

  double? get _segmentDuration {
    if (_endTime == null) return null;
    return _endTime! - _startTime;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MediaService.ensureInitialized();
    _transcriptScrollController = ScrollController();
    _preferredCaptionCode = _normalizeCaptionLanguage(widget.language);
    _player = Player();
    _playerInitialized = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAsync();
    });
  }

  Future<void> _initializeAsync() async {
    await _loadImportMetadata();
    await _initializePlayer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!_playerInitialized) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _player.pause();
      _saveProgressSafely();
    }
  }

  @override
  void deactivate() {
    if (_playerInitialized) {
      _player.stop();
    }
    _saveProgressSafely();
    super.deactivate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSub?.cancel();
    _playingSub?.cancel();
    _durationSub?.cancel();
    _transcriptScrollController.dispose();
    if (_playerInitialized) {
      _player.dispose();
    }
    super.dispose();
  }

  /// Pause playback (callable from parent before navigating away)
  void pause() {
    if (_playerInitialized) {
      _player.pause();
    }
  }

  /// Save progress before leaving
  Future<void> saveProgress() async {
    await _saveProgress();
  }

  /// Returns the current transcript as plain text.
  String get plainTextTranscript {
    if (_transcript.isNotEmpty) {
      return _transcript
          .map((item) => item['text']?.toString() ?? '')
          .where((t) => t.trim().isNotEmpty)
          .join(' ');
    }
    if (_rawTranscript.isNotEmpty) {
      return _rawTranscript
          .map((item) => item['text']?.toString() ?? '')
          .where((t) => t.trim().isNotEmpty)
          .join(' ');
    }
    return '';
  }

  void _saveProgressSafely() {
    _saveProgress().catchError((e) {
      Logger.error('Error in _saveProgressSafely', e);
    });
  }


  Future<void> _initializePlayer() async {
    try {
      _controller = VideoController(
        _player,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: true,
          androidAttachSurfaceAfterVideoParameters: true,
        ),
      );

      final String textContent = (widget.lesson['text_content'] ?? '')
          .toString();
      if (textContent.isNotEmpty) {
        try {
          final decoded = jsonDecode(textContent);
          if (decoded is List) {
            _rawTranscript = decoded.cast<Map<String, dynamic>>();
            _updateTranscript();
          }
        } catch (e) {
          Logger.warn(
            '_initializePlayer: text_content is not valid JSON for '
            '${widget.lesson['id']} — transcript will be fetched async. Error: $e',
          );
        }
      }

      String playableUrl = widget.sourceUrl ?? '';
      if (playableUrl.contains('youtube.com') ||
          playableUrl.contains('youtu.be')) {
        final ytForStream = YoutubeExplode();
        try {
          final String? videoIdParsed = VideoId.parseVideoId(playableUrl);
          if (videoIdParsed != null && videoIdParsed.isNotEmpty) {
            final manifest = await ytForStream.videos.streams.getManifest(
              VideoId(videoIdParsed),
            );
            final muxedStreams = manifest.muxed.toList();
            if (muxedStreams.isNotEmpty) {
              muxedStreams.sort((a, b) {
                final aHeight = a.videoResolution.height;
                final bHeight = b.videoResolution.height;
                return bHeight.compareTo(aHeight);
              });
              playableUrl = muxedStreams.first.url.toString();
            }
          }
        } catch (e) {
          Logger.warn('Failed to resolve stream URL client-side: $e');
        } finally {
          ytForStream.close();
        }
      }

      await _player.open(Media(playableUrl));

      final double initialSeek =
          (_lastPosition != null && _lastPosition! > _startTime)
          ? _lastPosition!
          : _startTime;
      _initialSeekPosition = Duration(
        milliseconds: (initialSeek * 1000).toInt(),
      );
      _isInitialSeeking = true;
      await _player.seek(_initialSeekPosition!);
      _isInitialSeeking = false;

      _positionSub = _player.stream.position.listen(_onVideoTick);
      _playingSub = _player.stream.playing.listen((playing) {
        if (mounted) setState(() => _isPlaying = playing);
      });
      _durationSub = _player.stream.duration.listen((d) {
        if (mounted) setState(() => _videoDuration = d);
      });
      _isInitialSeeking = false;
      _player.play();

      Future.delayed(const Duration(milliseconds: 500), () {
        if (_currentTranscriptIndex >= 0) {
          _scrollToIndex(_currentTranscriptIndex);
        }
      });

      if (!mounted) return;
      setState(() => _isLoading = false);

      _loadTranscriptAsync();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load video: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadTranscriptAsync() async {
    if (_rawTranscript.isNotEmpty) return;

    final sourceUrl = widget.originalUrl ?? widget.sourceUrl ?? '';
    final String? videoIdParsed = VideoId.parseVideoId(sourceUrl);
    if (videoIdParsed == null || videoIdParsed.isEmpty) return;

    final loadedFromFirestore = await _tryLoadTranscriptFromFirestore();
    if (loadedFromFirestore) return;

    if (mounted) {
      setState(() => _isTranscriptLoading = true);
    }

    final yt = YoutubeExplode();
    bool loadedLocalOrClient = false;
    try {
      final videoIdObj = VideoId(videoIdParsed);
      String? selectedCode;
      bool isAuto = false;

      final trackManifest = await yt.videos.closedCaptions
          .getManifest(videoIdObj)
          .timeout(const Duration(seconds: 8));
      final tracks = trackManifest.tracks;

      if (_selectedTranscriptCode != null) {
        selectedCode = _selectedTranscriptCode;
      }

      if (selectedCode == null) {
        for (final code in [
          _preferredCaptionCode,
          _preferredCaptionCode.split('-')[0],
        ]) {
          ClosedCaptionTrackInfo? match = tracks
              .where((t) => _captionCodeMatches(t.language.code, code))
              .firstOrNull;
          match ??= tracks.where((t) => t.language.code == code).firstOrNull;
          match ??= tracks
              .where((t) => t.language.name == _preferredCaptionCode)
              .firstOrNull;
          match ??= tracks
              .where(
                (t) => _captionCodeMatches(t.language.code, widget.language),
              )
              .firstOrNull;
          match ??= tracks.where((t) => !t.isAutoGenerated).firstOrNull;
          match ??= tracks.isNotEmpty ? tracks.first : null;

          if (match != null) {
            selectedCode = match.language.code;
            isAuto = match.isAutoGenerated;
            break;
          }
        }
      }

      if (selectedCode != null) {
        await _loadTranscriptByCode(selectedCode, isAuto: isAuto, force: true);
        loadedLocalOrClient = true;
      }

      if (_availableTranscriptsLocal.isEmpty && tracks.isNotEmpty) {
        if (mounted) {
          setState(() {
            _availableTranscriptsLocal = tracks
                .map(
                  (t) => {
                    'code': t.language.code,
                    'name': t.language.name,
                    'auto': t.isAutoGenerated,
                  },
                )
                .toList();
          });
        }
      }
    } catch (e) {
      Logger.warn('Failed to parse YouTube track manifest for transcript: $e');
    } finally {
      yt.close();
    }

    if (!loadedLocalOrClient) {
      final code = _selectedTranscriptCode ?? _preferredCaptionCode;
      if (code.isNotEmpty) {
        await _loadTranscriptByCode(code, force: true);
      }
    }

    if (_transcript.isEmpty && _rawTranscript.isNotEmpty) {
      if (mounted) {
        setState(() {
          _updateTranscript();
        });
      }
    }

    if (mounted) {
      setState(() => _isTranscriptLoading = false);
    }
  }

  void _onVideoTick(Duration position) {
    if (_isInitialSeeking) return;

    final double currentSeconds =
        position.inMilliseconds / 1000.0 + _syncOffset + _lookahead;

    if (_lastPositionInSeconds > 0 &&
        (currentSeconds - _lastPositionInSeconds).abs() > 1.5) {
      _updateTranscript();
    }
    _lastPositionInSeconds = currentSeconds;

    if (_startTime > 0 && currentSeconds < _startTime - 2.0) {
      _player.seek(Duration(milliseconds: (_startTime * 1000).toInt()));
      _syncTranscriptAtTime(_startTime);
      return;
    }
    if (_endTime != null && currentSeconds >= _endTime!) {
      _player.pause();
      _player.seek(Duration(milliseconds: (_endTime! * 1000).toInt()));
      _syncTranscriptAtTime(_endTime!);
      return;
    }

    _syncTranscriptAtTime(currentSeconds);

    if (currentSeconds > _maxPositionReached) {
      _maxPositionReached = currentSeconds;
    }

    final now = DateTime.now();
    if (now.difference(_lastProgressSave).inSeconds >= 5) {
      _saveProgress();
      _lastProgressSave = now;
    }
  }

  void _syncTranscriptAtTime(double absoluteSeconds) {
    final double relativeSeconds = _startTime > 0
        ? absoluteSeconds - _startTime
        : absoluteSeconds;

    final idx = _findTranscriptIndex(relativeSeconds);
    if (idx != _currentTranscriptIndex) {
      if (mounted) setState(() => _currentTranscriptIndex = idx);
      if (idx >= 0) _scrollToIndex(idx);
    }
  }

  int _findTranscriptIndex(double time) {
    if (_transcript.isEmpty) return -1;
    int low = 0;
    int high = _transcript.length - 1;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      final start = (_transcript[mid]['start'] as num).toDouble();
      final end = (_transcript[mid]['end'] as num).toDouble();
      if (time < start) {
        high = mid - 1;
      } else if (time > end) {
        low = mid + 1;
      } else {
        return mid;
      }
    }
    if (low <= 0 || low >= _transcript.length) return -1;
    final gapStart = (_transcript[low - 1]['end'] as num).toDouble();
    final gapEnd = (_transcript[low]['start'] as num).toDouble();
    final gapSize = gapEnd - gapStart;
    if (gapSize < 2.0) {
      final distToPrev = time - gapStart;
      final distToNext = gapEnd - time;
      return distToPrev <= distToNext ? low - 1 : low;
    }
    return -1;
  }

  void _scrollToIndex(int index, {Duration? duration, int retryCount = 0}) {
    if (index < 0 || index >= _itemKeys.length) return;
    _targetScrollIndex = index;

    if (!_transcriptScrollController.hasClients) {
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
        alignment: 0.3,
      );
      return;
    }

    if (retryCount >= 3) return;

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

    final pos = _transcriptScrollController.position;
    final maxScroll = pos.hasContentDimensions ? pos.maxScrollExtent : 0.0;
    double estimatedOffset = index * itemHeight;
    if (maxScroll > 0) {
      estimatedOffset = estimatedOffset.clamp(0.0, maxScroll);
    }

    _transcriptScrollController.jumpTo(estimatedOffset);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_targetScrollIndex == index) {
        _scrollToIndex(index, duration: duration, retryCount: retryCount + 1);
      }
    });
  }

  Future<void> _loadImportMetadata() async {
    try {
      final String targetId = widget.contentId ?? widget.importId;
      final doc = await FirebaseFirestore.instance
          .collection('user_content')
          .doc(targetId)
          .get();
      if (doc.exists && mounted) {
        final data = doc.data() as Map<String, dynamic>;
        final meta = data['metadata'] as Map<String, dynamic>?;
        final savedCode = meta?['transcript_language']?.toString();
        if (savedCode != null && savedCode.isNotEmpty) {
          _selectedTranscriptCode = savedCode;
          await _loadTranscriptByCode(savedCode);
        }
      }
    } catch (e) {
      Logger.warn('Failed to load import metadata for ${widget.importId}: $e');
    }
  }

  String _normalizeCaptionLanguage(String language) {
    if (languageBcp47Codes.containsKey(language)) {
      return languageBcp47Codes[language]!;
    }
    return language.toLowerCase();
  }

  bool _captionCodeMatches(String trackCode, String preferredCode) {
    if (trackCode.isEmpty || preferredCode.isEmpty) return false;
    final cleanedTrack = trackCode.toLowerCase().split('-').first;
    final cleanedPreferred = preferredCode.toLowerCase().split('-').first;
    return cleanedTrack == cleanedPreferred;
  }

  Future<void> _loadTranscriptByCode(
    String code, {
    bool isAuto = false,
    bool force = false,
  }) async {
    if (code.isEmpty) return;
    if (_isTranscriptLoading && !force) return;
    if (mounted) setState(() => _isTranscriptLoading = true);
    _selectedTranscriptCode = code;

    try {
      final sourceUrl = widget.originalUrl ?? widget.sourceUrl ?? '';
      if (!sourceUrl.contains('youtube.com') &&
          !sourceUrl.contains('youtu.be')) {
        return;
      }

      final String? videoIdParsed = VideoId.parseVideoId(sourceUrl);
      if (videoIdParsed == null || videoIdParsed.isEmpty) return;

      final loadedFromFirestore = await _tryLoadTranscriptFromFirestore();
      if (loadedFromFirestore) {
        _updateSelectedTranscript(code);
        if (mounted) setState(() => _isTranscriptLoading = false);
        return;
      }

      final videoIdObj = VideoId(videoIdParsed);

      bool clientSideSuccess = false;
      try {
        final yt = YoutubeExplode();
        try {
          final trackManifest = await yt.videos.closedCaptions.getManifest(
            videoIdObj,
          );

          if (_availableTranscriptsLocal.isEmpty &&
              trackManifest.tracks.isNotEmpty) {
            _availableTranscriptsLocal = trackManifest.tracks
                .map(
                  (t) => {
                    'code': t.language.code,
                    'name': t.language.name,
                    'auto': t.isAutoGenerated,
                  },
                )
                .toList();
          }

          final target = code.toLowerCase();
          ClosedCaptionTrackInfo? match = trackManifest.tracks.where((t) {
            final trackCode = t.language.code.toLowerCase();
            return trackCode == target || trackCode.startsWith('$target-');
          }).firstOrNull;

          match ??= trackManifest.tracks.where((t) {
            final trackCode = t.language.code.toLowerCase();
            return target.startsWith('$trackCode-');
          }).firstOrNull;

          match ??= trackManifest.tracks
              .where((t) => !t.isAutoGenerated)
              .firstOrNull;
          match ??= trackManifest.tracks.firstOrNull;

          if (match != null) {
            final track = await yt.videos.closedCaptions.get(match);
            if (track.captions.isNotEmpty) {
              final rawCaptions = track.captions
                  .map((c) {
                    final double localStart = c.offset.inMilliseconds / 1000.0;
                    final double localEnd =
                        (c.offset + c.duration).inMilliseconds / 1000.0;
                    if (localEnd <= 0) return null;
                    return {
                      'text': c.text,
                      'start': localStart < 0 ? 0.0 : localStart,
                      'end': localEnd,
                    };
                  })
                  .whereType<Map<String, dynamic>>()
                  .toList();

              _rawTranscript = rawCaptions;

              if (_rawTranscript.isNotEmpty) {
                clientSideSuccess = true;
                _updateTranscript();
              }
            }
          }
        } finally {
          yt.close();
        }
      } catch (e) {
        Logger.warn('Failed to fetch client-side YouTube transcript: $e');
      }

      if (!clientSideSuccess) {
        try {
          final result = await _importService.fetchTranscriptFromBackend(
            videoId: videoIdParsed,
            languageCode: code,
          );
          if (result != null) {
            final rawList = result['captions'] ?? result['transcript'];
            if (rawList is List) {
              _rawTranscript = rawList.map((entry) {
                final map = Map<String, dynamic>.from(entry as Map);
                if (!map.containsKey('end') && map.containsKey('duration')) {
                  final startVal = (map['start'] as num?)?.toDouble() ?? 0.0;
                  final durationVal =
                      (map['duration'] as num?)?.toDouble() ?? 0.0;
                  map['end'] = startVal + durationVal;
                }
                return map;
              }).toList();
              clientSideSuccess = true;
              _updateTranscript();
            }
          }
        } on RateLimitException catch (e) {
          if (mounted) _showTranscriptRateLimitDialog(e.message);
        } catch (e) {
          Logger.warn('Failed to fetch transcript from backend: $e');
        }
      }

      if (_rawTranscript.isNotEmpty) {
        _updateSelectedTranscript(code);
        _saveTranscriptToFirestore();
      }
    } catch (e) {
      Logger.error('Error loading transcript by code', e);
    }

    if (mounted) setState(() => _isTranscriptLoading = false);
  }

  void _updateTranscript() {
    for (var i = 0; i < _rawTranscript.length; i++) {
      final text = (_rawTranscript[i]['text'] ?? '')
          .toString()
          .replaceAll('\u200B', '')
          .replaceAll('\u200E', '')
          .replaceAll('\u200F', '')
          .trim();
      _rawTranscript[i]['text'] = text;
    }
    _rawTranscript.removeWhere((e) => (e['text'] ?? '').toString().isEmpty);

    _rawTranscript.sort(
      (a, b) => ((a['start'] as num?)?.toDouble() ?? 0).compareTo(
        (b['start'] as num?)?.toDouble() ?? 0,
      ),
    );

    for (var i = 0; i < _rawTranscript.length - 1; i++) {
      final currentEnd = (_rawTranscript[i]['end'] as num).toDouble();
      final nextStart = (_rawTranscript[i + 1]['start'] as num).toDouble();
      if (currentEnd > nextStart) {
        _rawTranscript[i]['end'] = nextStart;
      }
    }

    if (_rawTranscript.length > 1) {
      final merged = <Map<String, dynamic>>[];
      Map<String, dynamic> current = Map<String, dynamic>.from(
        _rawTranscript.first,
      );
      for (var i = 1; i < _rawTranscript.length; i++) {
        final next = _rawTranscript[i];
        final currentEnd = (current['end'] as num).toDouble();
        final nextStart = (next['start'] as num).toDouble();
        final duration = currentEnd - (current['start'] as num).toDouble();

        if (duration < _mergeThreshold &&
            (nextStart - currentEnd).abs() < 0.5) {
          current['text'] = '${current['text']} ${next['text']}'.trim();
          current['end'] = next['end'];
        } else {
          merged.add(Map<String, dynamic>.from(current));
          current = Map<String, dynamic>.from(next);
        }
      }
      merged.add(Map<String, dynamic>.from(current));
      _transcript = merged;
    } else {
      _transcript = List.from(_rawTranscript);
    }

    if (_startTime > 0) {
      for (var i = 0; i < _transcript.length; i++) {
        final start = (_transcript[i]['start'] as num).toDouble();
        final end = (_transcript[i]['end'] as num).toDouble();
        _transcript[i]['start'] = start - _startTime;
        _transcript[i]['end'] = end - _startTime;
      }
      _transcript.removeWhere((e) => (e['end'] as num).toDouble() <= 0);
      for (var i = 0; i < _transcript.length; i++) {
        final s = (_transcript[i]['start'] as num).toDouble();
        if (s < 0) _transcript[i]['start'] = 0.0;
      }
    }

    _itemKeys.clear();
    for (var i = 0; i < _transcript.length; i++) {
      _itemKeys.add(GlobalKey());
    }
  }

  Future<void> _updateSelectedTranscript(String code) async {
    try {
      final String targetId = widget.contentId ?? widget.importId;
      await FirebaseFirestore.instance
          .collection('user_content')
          .doc(targetId)
          .update({
            'metadata.transcript_language': code,
            'updated_at': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      Logger.warn('Failed to update selected transcript code: $e');
    }
  }

  Future<bool> _tryLoadTranscriptFromFirestore() async {
    if (_rawTranscript.isNotEmpty) return false;
    try {
      final String contentId = widget.contentId ?? widget.importId;

      final sourceDoc = await FirebaseFirestore.instance
          .collection('user_content')
          .doc(contentId)
          .collection('source')
          .doc('raw')
          .get();
      if (!sourceDoc.exists) return false;

      final transcriptJson = sourceDoc.data()?['transcript_json'] as String?;
      if (transcriptJson == null || transcriptJson.isEmpty) return false;

      final decoded = jsonDecode(transcriptJson);
      if (decoded is! List || decoded.isEmpty) return false;

      _rawTranscript = decoded.cast<Map<String, dynamic>>();
      _updateTranscript();
      return true;
    } catch (e) {
      Logger.error('Failed to load transcript from Firestore', e);
      return false;
    }
  }

  Future<void> _saveTranscriptToFirestore() async {
    if (_rawTranscript.isEmpty) return;
    try {
      final String contentId = widget.contentId ?? widget.importId;
      final transcriptJson = jsonEncode(_rawTranscript);
      await FirebaseFirestore.instance
          .collection('user_content')
          .doc(contentId)
          .collection('source')
          .doc('raw')
          .set({
            'transcript_json': transcriptJson,
            'updated_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      Logger.error('Failed to save transcript to Firestore', e);
    }
  }

  Future<void> _saveProgress() async {
    double? effectiveDuration = _segmentDuration;
    if (effectiveDuration == null || effectiveDuration <= 0) {
      effectiveDuration = _videoDuration?.inSeconds.toDouble();
    }
    if (effectiveDuration == null || effectiveDuration <= 0) return;
    final progress = (_maxPositionReached - _startTime) / effectiveDuration;
    final clamped = progress.clamp(0.0, 1.0);
    widget.onProgressChanged?.call(clamped);
    if (clamped >= 0.99) {
      widget.onCompleted?.call();
    }
  }

  void _showTranscriptRateLimitDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => CustomDialog(
        title: 'Transcript Limit Reached',
        showCancelButton: false,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.timer_off_rounded,
                size: 40,
                color: Colors.orangeAccent,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              style: GoogleFonts.nunito(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'You can fetch up to 20 transcripts per minute and 200 per day. '
              'Please wait and try again later.',
              style: GoogleFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white54
                    : Colors.black45,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        saveButtonText: 'OK',
        saveButtonColor: Colors.orangeAccent,
        onSave: () => Navigator.pop(ctx),
        onCancel: () => Navigator.pop(ctx),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: Colors.redAccent.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Something went wrong',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _errorMessage = null;
                  _isLoading = true;
                });
                _initializePlayer();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const PageSkeleton();
    }
    if (_errorMessage != null) {
      return _buildErrorView();
    }

    final theme = Theme.of(context);
    return Column(
      children: [
        VideoPlayerWidget(
          controller: _controller,
          player: _player,
        ),
        if (_showTranscript)
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInBack,
              transitionBuilder: (child, animation) {
                return SizeTransition(
                  sizeFactor: animation,
                  axisAlignment: -1.0,
                  child: FadeTransition(opacity: animation, child: child),
                );
              },
              child: _transcript.isNotEmpty
                  ? TranscriptListView(
                      key: const ValueKey('transcript_list'),
                      transcript: _transcript,
                      currentIndex: _currentTranscriptIndex,
                      itemKeys: _itemKeys,
                      scrollController: _transcriptScrollController,
                      fontFamily: widget.readerSettings.fontFamily,
                      fontSize: widget.readerSettings.fontSize,
                      lineHeight: widget.readerSettings.lineHeight,
                      fontWeightIndex: widget.readerSettings.fontWeightIndex,
                      textAlignIndex: widget.readerSettings.textAlignIndex,
                      startTime: _startTime,
                      onItemTap: (absoluteStart) {
                        _player.seek(
                          Duration(
                            milliseconds: (absoluteStart * 1000).toInt(),
                          ),
                        );
                        _syncTranscriptAtTime(absoluteStart);
                        _player.play();
                      },
                      onAction: widget.onAction,
                    )
                  : _isTranscriptLoading
                  ? const TranscriptSkeleton(
                      key: ValueKey('transcript_skeleton'),
                    )
                  : Center(
                      key: const ValueKey('no_transcript'),
                      child: Text(
                        'No transcript available.',
                        style: GoogleFonts.nunito(
                          fontSize: 14,
                          color:
                              theme.textTheme.bodyMedium?.color?.withValues(
                                alpha: 0.5,
                              ) ??
                              Colors.grey,
                        ),
                      ),
                    ),
            ),
          ),
        VideoControlsBar(
          key: ValueKey('video_controls_${widget.lesson['id']}'),
          positionStream: _player.stream.position,
          playingStream: _player.stream.playing,
          speed: _speed,
          segmentDuration: _segmentDuration ?? 0,
          totalDuration: _videoDuration,
          startTime: _startTime,
          showTranscript: _showTranscript,
          isPlaying: _isPlaying,
          initialPosition: _initialSeekPosition,
          onSeek: (seekTime) {
            _player.seek(Duration(milliseconds: (seekTime * 1000).toInt()));
            _syncTranscriptAtTime(seekTime);
          },
          onSpeedChanged: (v) {
            setState(() => _speed = v);
            _player.setRate(v);
          },
          onToggleTranscript: () =>
              setState(() => _showTranscript = !_showTranscript),
          onPlayPause: () {
            if (_isPlaying) {
              _player.pause();
            } else {
              _player.play();
            }
          },
        ),
        ContentBottomBar(
          onDefinitionTap: widget.onDefinitionTap,
          onFontTap: widget.onFontTap,
          showFontActive: false,
        ),
      ],
    );
  }
}
