import 'package:Badya/widgets/reader_settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_kit/media_kit.dart';

/// Video player with a font-settings overlay for caption styling.
class VideoPlayerWidget extends StatelessWidget {
  final VideoController? controller;
  final Player player;
  final double fontSize;
  final String selectedFontFamily;
  final Map<String, String> availableFonts;
  final bool showFontOverlay;
  final VoidCallback? onToggleFontOverlay;
  final ValueChanged<ReaderSettings>? onFontChanged;

  const VideoPlayerWidget({
    super.key,
    required this.controller,
    required this.player,
    this.fontSize = 18.0,
    this.selectedFontFamily = 'Nunito',
    this.availableFonts = const {},
    this.showFontOverlay = false,
    this.onToggleFontOverlay,
    this.onFontChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        color: Colors.black,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            children: [
              if (controller != null) Video(controller: controller!),
              if (showFontOverlay)
                Positioned.fill(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.8),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 40,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: availableFonts.keys
                                .map(
                                  (name) => Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: GestureDetector(
                                      onTap: () => onFontChanged?.call(
                                        ReaderSettings(
                                          fontSize: fontSize,
                                          fontFamily: name,
                                        ),
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: selectedFontFamily == name
                                              ? Colors.tealAccent
                                              : Colors.white.withValues(
                                                  alpha: 0.15,
                                                ),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Text(
                                          name,
                                          style: TextStyle(
                                            color: selectedFontFamily == name
                                                ? Colors.black
                                                : Colors.white,
                                            fontFamily: availableFonts[name],
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                        const Spacer(),
                        Slider(
                          value: fontSize,
                          min: 12,
                          max: 42,
                          divisions: 15,
                          activeColor: Colors.tealAccent,
                          inactiveColor: Colors.white.withValues(alpha: 0.2),
                          label: '${fontSize.round()}px',
                          onChanged: (v) => onFontChanged?.call(
                            ReaderSettings(
                              fontSize: v,
                              fontFamily: selectedFontFamily,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
