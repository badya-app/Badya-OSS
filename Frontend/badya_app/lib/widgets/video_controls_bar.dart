import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Playback controls bar: position slider, speed, play/pause, transcript toggle.
class VideoControlsBar extends StatelessWidget {
  final Stream<Duration> positionStream;
  final Stream<bool> playingStream;
  final double speed;
  final double segmentDuration;
  final double startTime;
  final bool showTranscript;
  final ValueChanged<double> onSeek;
  final ValueChanged<double> onSpeedChanged;
  final VoidCallback onToggleTranscript;
  final VoidCallback onPlayPause;
  final bool isPlaying;
  final Duration? initialPosition;
  /// The actual full video duration, used as a fallback for the
  /// timeline slider and end-time label when [segmentDuration] is 0
  /// (i.e. the content has no user-defined segment end).
  final Duration? totalDuration;

  const VideoControlsBar({
    super.key,
    required this.positionStream,
    required this.playingStream,
    required this.speed,
    required this.segmentDuration,
    required this.startTime,
    required this.showTranscript,
    required this.onSeek,
    required this.onSpeedChanged,
    required this.onToggleTranscript,
    required this.onPlayPause,
    required this.isPlaying,
    this.initialPosition,
    this.totalDuration,
  });

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreamBuilder<Duration>(
            stream: positionStream,
            initialData: initialPosition ?? const Duration(),
            builder: (context, snapshot) {
              final position = snapshot.data ?? const Duration();
              final double posSeconds = position.inMilliseconds / 1000.0;
              final double relativePos = startTime > 0
                  ? (posSeconds - startTime).clamp(0.0, double.infinity)
                  : posSeconds.clamp(0.0, double.infinity);
              // Use segment duration when available; fall back to actual
              // video duration for unsegmented content.
              final double effectiveDuration = segmentDuration > 0
                  ? segmentDuration
                  : (totalDuration?.inMilliseconds ?? 0) / 1000.0;
              final double maxVal = effectiveDuration > 0 ? effectiveDuration : 1.0;

              return Column(
                children: [
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                      activeTrackColor:
                          isDark ? Colors.tealAccent : Colors.teal,
                      inactiveTrackColor:
                          (isDark ? Colors.white : Colors.black)
                              .withValues(alpha: 0.1),
                    ),
                    child: Slider(
                      value: relativePos.clamp(0.0, maxVal),
                      min: 0,
                      max: maxVal,
                      onChanged: (v) {
                        final seekTime = startTime + v;
                        onSeek(seekTime);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(
                            Duration(seconds: relativePos.toInt()),
                          ),
                          style: GoogleFonts.nunito(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                        Text(
                          segmentDuration > 0
                              ? _formatDuration(
                                  Duration(seconds: segmentDuration.toInt()),
                                )
                              : totalDuration != null
                                  ? _formatDuration(totalDuration!)
                                  : '--:--',
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
                initialValue: speed,
                onSelected: onSpeedChanged,
                itemBuilder: (context) =>
                    [2.0, 1.5, 1.25, 1.0, 0.75, 0.5]
                        .map(
                          (v) => PopupMenuItem(
                            value: v,
                            child: Text('${v}x'),
                          ),
                        )
                        .toList(),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.08),
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
                        '${speed}x',
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
                stream: playingStream,
                initialData: isPlaying,
                builder: (context, snapshot) {
                  final activePlaying = snapshot.data ?? isPlaying;
                  return GestureDetector(
                    onTap: onPlayPause,
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.tealAccent : Colors.teal,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (isDark ? Colors.tealAccent : Colors.teal)
                                .withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        activePlaying
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
                  showTranscript
                      ? Icons.subtitles_rounded
                      : Icons.subtitles_off_rounded,
                  color: showTranscript
                      ? (isDark ? Colors.tealAccent : Colors.teal)
                      : (isDark ? Colors.white38 : Colors.black26),
                ),
                onPressed: onToggleTranscript,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
