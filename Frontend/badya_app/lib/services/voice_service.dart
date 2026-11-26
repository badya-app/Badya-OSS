import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:Badya/services/adk_service.dart';
import 'package:Badya/utils/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';

class VoiceService {
  final _record = AudioRecorder();
  WebSocketChannel? _channel;
  StreamSubscription? _recorderSubscription;

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  bool _isConnecting = false;
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  Future<void> connect({
    required String appName,
    required String userId,
    required String sessionId,
  }) async {
    if (_isConnecting || _isConnected) return;
    _isConnecting = true;

    final baseUrl = AdkService().baseUrl;
    final wsUrl =
        '${baseUrl.replaceFirst('http', 'ws')}/ws/apps/$appName/users/$userId/sessions/$sessionId';

    Logger.info('Connecting to Voice WebSocket: $wsUrl');

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _isConnected = true;
      _isConnecting = false;

      // Initialize PCM Sound for playback (24000Hz as per voiceclient.py)
      await FlutterPcmSound.setup(sampleRate: 24000, channelCount: 1);
      FlutterPcmSound.start();

      _channel!.stream.listen(
        (message) => _handleIncomingMessage(message),
        onDone: () {
          Logger.info('Voice WebSocket closed');
          _isConnected = false;
        },
        onError: (error) {
          Logger.error('Voice WebSocket error', error);
          _isConnected = false;
        },
      );
    } catch (e) {
      Logger.error('Error connecting to Voice WebSocket', e);
      _isConnecting = false;
      _isConnected = false;
    }
  }

  void _handleIncomingMessage(dynamic message) {
    if (message is String) {
      try {
        final Map<String, dynamic> event = jsonDecode(message);
        if (!_messageController.isClosed) {
          _messageController.add(event);
        }
      } catch (e) {
        Logger.error('Error handling incoming voice message', e);
      }
    } else if (message is Uint8List) {
      // Direct binary PCM audio from agent
      _handleBinaryAudio(message);
    }
  }

  void _handleBinaryAudio(Uint8List bytes) {
    // Add to buffer and start playback loop if not running
    _playbackBuffer.add(bytes);
    if (!_isBufferPlaying) {
      _processPlaybackBuffer();
    }

    // Update bot volume visualization
    final int segmentSize = 4800; // ~100ms at 24000Hz
    for (int i = 0; i < bytes.length; i += segmentSize) {
      int end = (i + segmentSize < bytes.length) ? i + segmentSize : bytes.length;
      final segment = bytes.sublist(i, end);
      _visualVolumeQueue.add(_calculateRMS(segment));
    }

    if (!_isVisualizing) {
      _processVisualQueue();
    }
  }

  // Volume Streams (Normalized 0.0 - 1.0)
  final _userVolumeController = StreamController<double>.broadcast();
  final _botVolumeController = StreamController<double>.broadcast();

  // Voice Activity Detection Stream (true when voice is detected)
  final _voiceActivityController = StreamController<bool>.broadcast();
  Stream<bool> get voiceActivity => _voiceActivityController.stream;

  Stream<double> get userVolume => _userVolumeController.stream;
  Stream<double> get botVolume => _botVolumeController.stream;

  double _calculateRMS(List<int> bytes) {
    if (bytes.isEmpty) return 0.0;

    // Int16 view of the byte data
    final int16List = Uint8List.fromList(bytes).buffer.asInt16List();

    double sum = 0;
    for (var sample in int16List) {
      sum += sample * sample;
    }

    final mean = sum / int16List.length;
    final rms = math.sqrt(mean);

    // Normalize to 0.0 - 1.0 (Max amplitude for 16-bit is 32768)
    return (rms / 32768.0).clamp(0.0, 1.0);
  }

  DateTime? _muteMicUntil;

  // Audio Playback Buffer
  final List<Uint8List> _playbackBuffer = [];
  bool _isBufferPlaying = false;

  final List<double> _visualVolumeQueue = [];
  bool _isVisualizing = false;

  /// Deprecated: Audio is now handled via binary frames in _handleIncomingMessage
  Future<void> playAgentAudio(String base64Data) async {
    Logger.warn('playAgentAudio called with base64 data. This is deprecated.');
  }

  Future<void> _processPlaybackBuffer() async {
    _isBufferPlaying = true;

    while (_playbackBuffer.isNotEmpty) {
      final bytes = _playbackBuffer.removeAt(0);
      final int16list = bytes.buffer.asInt16List();

      // Calculate duration for muting logic
      final double durationSeconds = int16list.length / 24000.0;
      final duration = Duration(milliseconds: (durationSeconds * 1000).ceil());

      final now = DateTime.now();
      if (_muteMicUntil == null || _muteMicUntil!.isBefore(now)) {
        _muteMicUntil = now.add(duration);
      } else {
        _muteMicUntil = _muteMicUntil!.add(duration);
      }

      // Play the audio - let FlutterPcmSound handle timing internally
      try {
        await FlutterPcmSound.feed(PcmArrayInt16.fromList(int16list));
      } catch (e) {
        Logger.error('Error feeding audio chunk', e);
      }

      // Reduced delay - let the buffer queue handle flow control
      // instead of forcing exact timing which can cause drift
      await Future.delayed(const Duration(milliseconds: 20));
    }

    _isBufferPlaying = false;
  }

  Future<void> _processVisualQueue() async {
    _isVisualizing = true;
    while (_visualVolumeQueue.isNotEmpty) {
      final vol = _visualVolumeQueue.removeAt(0);
      if (!_botVolumeController.isClosed) {
        _botVolumeController.add(vol);
      }
      // Wait for approx 100ms to match the chunk duration
      await Future.delayed(const Duration(milliseconds: 100));
    }
    // Return to silence when done
    if (!_botVolumeController.isClosed) {
      _botVolumeController.add(0.0);
    }
    _isVisualizing = false;
  }

  // Voice Activity Detection threshold (0.0 - 1.0)
  // Lower = more sensitive to quiet sounds
  static const double voiceActivityThreshold = 0.02;

  // Check if the current audio level indicates voice activity
  bool isVoiceActive(double rms) => rms >= voiceActivityThreshold;

  Future<void> startRecording() async {
    if (await _record.hasPermission()) {
      // Record as PCM 16-bit, 16000Hz, Mono
      // Reduced echoCancel, noiseSuppress aggressiveness to avoid filtering speech
      // Keep autoGain for consistent levels
      final config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        echoCancel: false,
        noiseSuppress: false,
        autoGain: true,
      );

      final stream = await _record.startStream(config);

      _recorderSubscription = stream.listen((data) {
        if (_isConnected && _channel != null) {
          // --- Software AEC Logic ---
          // if we are currently "muting" mic input because bot is speaking
          // then we should also MUTE the visual feedback for the user
          // this prevents the background clouds from moving when the bot speaks
          if (_muteMicUntil != null &&
              DateTime.now().isBefore(_muteMicUntil!)) {
            // Force visuals to silent
            _userVolumeController.add(0.0);
            _voiceActivityController.add(false);
            return;
          }

          // Calculate RMS for user volume visualization
          // We only take a subset to calculate RMS to be fast
          final rms = _calculateRMS(data);
          if (!_userVolumeController.isClosed) {
            _userVolumeController.add(rms);
          }

          // Emit voice activity state
          final isVoice = isVoiceActive(rms);
          if (!_voiceActivityController.isClosed) {
            _voiceActivityController.add(isVoice);
          }

          try {
            // Send binary PCM data directly (Production Ready)
            _channel!.sink.add(data);
          } catch (e) {
            Logger.error('Error sending audio blob', e);
          }
        } else {
          // If not connected, still emit user volume for local feedback
          if (!_userVolumeController.isClosed) {
            final rms = _calculateRMS(data);
            _userVolumeController.add(rms);
            if (!_voiceActivityController.isClosed) {
              _voiceActivityController.add(isVoiceActive(rms));
            }
          }
        }
      });
    }
  }

  Future<void> stopRecording() async {
    // 1. Send silence explicitly to trigger VAD (Silence Flush)
    if (_isConnected && _channel != null) {
      try {
        // Generate 500ms of silence (16000 samples/sec * 0.5 sec = 8000 samples * 2 bytes/sample = 16000 bytes)
        final silence = Uint8List(16000);
        _channel!.sink.add(silence);
      } catch (e) {
        Logger.error('Error sending silence flush', e);
      }
    }

    // 2. Stop the recorder
    await _record.stop();
    if (!_userVolumeController.isClosed) {
      _userVolumeController.add(0.0); // Reset volume
    }

    // 3. Wait a brief moment
    await Future.delayed(const Duration(milliseconds: 100));

    // 4. Cleanup
    await _recorderSubscription?.cancel();
    _recorderSubscription = null;
  }

  Future<void> disconnect() async {
    await stopRecording();
    await _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _isConnecting = false;
    if (!_userVolumeController.isClosed) {
      _userVolumeController.add(0.0);
    }
    if (!_botVolumeController.isClosed) {
      _botVolumeController.add(0.0);
    }
    if (!_voiceActivityController.isClosed) {
      _voiceActivityController.add(false);
    }
    await FlutterPcmSound.release();
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _userVolumeController.close();
    _botVolumeController.close();
    _voiceActivityController.close();
    _record.dispose();
  }
}
