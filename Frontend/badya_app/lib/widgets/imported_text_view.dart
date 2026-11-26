import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:Badya/services/adk_service.dart';
import 'package:Badya/widgets/content_bottom_bar.dart';
import 'package:Badya/widgets/custom_selection_toolbar.dart';
import 'package:Badya/widgets/reader_settings_sheet.dart';

/// Renders imported text content (articles, book chapters, stories)
/// with markdown parsing, reader formatting settings, scroll progress,
/// and word selection actions.
class ImportedTextView extends StatefulWidget {
  final String textContent;
  final ReaderSettings readerSettings;
  final void Function(BuildContext context, String action, String text) onAction;
  final VoidCallback onDefinitionTap;
  final VoidCallback onFontTap;
  final ValueChanged<double>? onProgressChanged;
  final VoidCallback? onCompleted;

  const ImportedTextView({
    super.key,
    required this.textContent,
    required this.readerSettings,
    required this.onAction,
    required this.onDefinitionTap,
    required this.onFontTap,
    this.onProgressChanged,
    this.onCompleted,
  });

  @override
  State<ImportedTextView> createState() => _ImportedTextViewState();
}

class _ImportedTextViewState extends State<ImportedTextView> {
  final ScrollController _scrollController = ScrollController();
  double _scrollProgress = 0.0;
  bool _isCompleted = false;
  String? _selectedText;
  Timer? _scrollDebounceTimer;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollDebounceTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final progress = maxScroll > 0 ? currentScroll / maxScroll : 1.0;
    final clamped = progress.clamp(0.0, 1.0);

    if ((clamped - _scrollProgress).abs() > 0.005) {
      setState(() => _scrollProgress = clamped);
    }

    if (progress >= 0.99 ||
        (maxScroll > 50 && currentScroll >= maxScroll - 50)) {
      if (!_isCompleted) {
        _isCompleted = true;
        _scrollDebounceTimer?.cancel();
        widget.onCompleted?.call();
      }
    } else {
      _scrollDebounceTimer?.cancel();
      _scrollDebounceTimer = Timer(const Duration(seconds: 1), () {
        widget.onProgressChanged?.call(clamped);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayContent = widget.textContent.replaceAll(
      '[[BASE_URL]]',
      AdkService().baseUrl,
    );

    final bodyTextStyle = resolveFontStyle(
      widget.readerSettings.fontFamily,
      fontSize: widget.readerSettings.fontSize,
      height: widget.readerSettings.lineHeight,
      fontWeight: resolveFontWeight(widget.readerSettings.fontWeightIndex),
    );

    final wrapAlign = resolveWrapAlignment(widget.readerSettings.textAlignIndex);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // Scroll progress bar
        Container(
          height: 3,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: (isDark ? Colors.white : Colors.black).withValues(
              alpha: 0.06,
            ),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: _scrollProgress,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: const LinearGradient(
                  colors: [Colors.teal, Colors.blue],
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: TweenAnimationBuilder<double>(
            tween: Tween(
              begin: widget.readerSettings.fontSize,
              end: widget.readerSettings.fontSize,
            ),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            builder: (context, size, child) {
              return TweenAnimationBuilder<double>(
                tween: Tween(
                  begin: widget.readerSettings.lineHeight,
                  end: widget.readerSettings.lineHeight,
                ),
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                builder: (context, height, child) {
                  return SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(20),
                    child: SelectionArea(
                      onSelectionChanged: (selection) {
                        if (selection != null) {
                          setState(() => _selectedText = selection.plainText);
                        }
                      },
                      contextMenuBuilder: (ctx, selectableRegionState) {
                        return CustomSelectionToolbar(
                          anchors: selectableRegionState.contextMenuAnchors,
                          buttonItems: selectableRegionState.contextMenuButtonItems,
                          onHide: () => selectableRegionState.hideToolbar(),
                          onCustomAction: (action) {
                            widget.onAction(context, action, _selectedText ?? '');
                          },
                        );
                      },
                      child: MarkdownBody(
                        data: displayContent,
                        selectable: false,
                        sizedImageBuilder: (config) {
                          return Image(
                            image: CachedNetworkImageProvider(
                              config.uri.toString(),
                            ),
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                                  Icons.broken_image_rounded,
                                  size: 48,
                                ),
                          );
                        },
                        styleSheet: MarkdownStyleSheet(
                          p: bodyTextStyle,
                          textAlign: wrapAlign,
                          blockSpacing: 24,
                          h1: GoogleFonts.merriweather(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                          h2: GoogleFonts.merriweather(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                          h3: GoogleFonts.merriweather(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
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
