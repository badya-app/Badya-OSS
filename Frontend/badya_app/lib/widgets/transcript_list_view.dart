import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:Badya/widgets/custom_selection_toolbar.dart';
import 'package:Badya/widgets/reader_settings_sheet.dart';

/// A scrollable list of transcript entries with active-highlight,
/// timestamp badges, and selection-based action support.
class TranscriptListView extends StatelessWidget {
  final List<Map<String, dynamic>> transcript;
  final int currentIndex;
  final List<GlobalKey> itemKeys;
  final ScrollController scrollController;
  final String fontFamily;
  final double fontSize;
  final double lineHeight;
  final int fontWeightIndex;
  final int textAlignIndex;
  final double startTime;
  final void Function(double absoluteStart) onItemTap;
  final void Function(BuildContext context, String action, String text)
      onAction;

  const TranscriptListView({
    super.key,
    required this.transcript,
    required this.currentIndex,
    required this.itemKeys,
    required this.scrollController,
    required this.fontFamily,
    required this.fontSize,
    this.lineHeight = 1.4,
    this.fontWeightIndex = 0,
    this.textAlignIndex = 0,
    required this.startTime,
    required this.onItemTap,
    required this.onAction,
  });

  String _formatDuration(double rawStart) {
    final clampedStart = rawStart < 0 ? 0.0 : rawStart;
    final duration = Duration(milliseconds: (clampedStart * 1000).toInt());
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
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
        controller: scrollController,
        cacheExtent: 1000.0,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: transcript.length,
        itemBuilder: (context, index) {
          final item = transcript[index];
          final isActive = index == currentIndex;
          final text = item['text']?.toString() ?? '';
          final rawStart = (item['start'] as num?)?.toDouble() ?? 0;

          // Convert segment-relative timestamps to absolute for seeking
          final absoluteStart =
              startTime > 0 ? rawStart + startTime : rawStart;

          return GestureDetector(
            onTap: () => onItemTap(absoluteStart),
            child: Container(
              key: itemKeys.isNotEmpty && index < itemKeys.length
                  ? itemKeys[index]
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
                      ? (isDark
                            ? Colors.tealAccent.withValues(alpha: 0.12)
                            : Colors.teal.withValues(alpha: 0.08))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: isActive
                      ? Border(
                          left: BorderSide(
                            color: isDark ? Colors.tealAccent : Colors.teal,
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
                            ? (isDark ? Colors.tealAccent : Colors.teal)
                            : (isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.06)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _formatDuration(rawStart),
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
                        textAlign: resolveTextAlign(textAlignIndex),
                        style: resolveFontStyle(
                          fontFamily,
                          fontSize: fontSize,
                          fontWeight: isActive
                              ? FontWeight.w700
                              : resolveFontWeight(fontWeightIndex),
                          color: isActive
                              ? (isDark
                                    ? Colors.tealAccent
                                    : Colors.teal.shade700)
                              : (isDark ? Colors.white70 : Colors.black87),
                          height: lineHeight,
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
                              onAction(ctx, action, selText);
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
}
