import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';

class DefinitionHistoryPanel extends StatefulWidget {
  final Stream<String>? definitionStream;
  final List<Map<String, String>> history;
  final String? initialWord;
  final VoidCallback? onClose;
  final Function(int)? onDelete;

  const DefinitionHistoryPanel({
    super.key,
    this.definitionStream,
    required this.history,
    this.initialWord,
    this.onClose,
    this.onDelete,
  });

  @override
  State<DefinitionHistoryPanel> createState() => _DefinitionHistoryPanelState();
}

class _DefinitionHistoryPanelState extends State<DefinitionHistoryPanel> {
  final StringBuffer _buffer = StringBuffer();
  StreamSubscription<String>? _subscription;
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _panelHistory = [];
  bool _isStreaming = false;

  @override
  void initState() {
    super.initState();
    _panelHistory.addAll(widget.history);
    _subscribeToStream();
  }

  @override
  void didUpdateWidget(covariant DefinitionHistoryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.definitionStream != oldWidget.definitionStream) {
      _subscribeToStream();
    }
  }

  void _deleteHistoryItem(int index) {
    if (mounted) {
      setState(() {
        _panelHistory.removeAt(index);
      });
      widget.onDelete?.call(index);
    }
  }

  void _subscribeToStream() {
    _subscription?.cancel();
    _buffer.clear();
    if (widget.definitionStream != null) {
      setState(() {
        _isStreaming = true;
      });
      _subscription = widget.definitionStream!.listen(
        (data) {
          if (mounted) {
            setState(() {
              _buffer.write(data);
            });
          }
        },
        onDone: () {
          if (_buffer.isNotEmpty) {
            final definition = _buffer.toString();
            if (widget.initialWord != null &&
                !_panelHistory.any(
                  (e) =>
                      e['word'] == widget.initialWord &&
                      e['definition'] == definition,
                )) {
              if (mounted) {
                setState(() {
                  _panelHistory.insert(0, {
                    'word': widget.initialWord!,
                    'definition': definition,
                  });
                });
              }
              widget.history.clear();
              widget.history.addAll(_panelHistory);
            }
          }
          if (mounted) {
            setState(() {
              _isStreaming = false;
            });
          }
        },
        onError: (error) {
          if (mounted) {
            setState(() {
              _buffer.write("Error: $error");
              _isStreaming = false;
            });
          }
        },
      );
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final markdownStyle = MarkdownStyleSheet.fromTheme(theme).copyWith(        p: GoogleFonts.nunito(
        fontSize: 15,
        color: theme.textTheme.bodyLarge?.color?.withValues(alpha: 0.9),
        height: 1.5,
      ),
      strong: GoogleFonts.nunito(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: theme.colorScheme.primary,
      ),
      h2: GoogleFonts.merriweather(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: theme.colorScheme.primary,
      ),
      pPadding: const EdgeInsets.only(bottom: 8),
    );

    return Drawer(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
            decoration: const BoxDecoration(
              color: Color(0xFF1ABC9C),
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.menu_book_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Definitions',
                      style: GoogleFonts.merriweather(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: widget.onClose ?? () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Expanded(
            child: _panelHistory.isEmpty && !_isStreaming
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.menu_book_outlined,
                          size: 64,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0),
                          child: Text(
                            'Select a word and tap "Define" to see its definition here.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.nunito(
                              fontSize: 18,
                              color: Colors.grey[400],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(20),
                    itemCount: _isStreaming
                        ? _panelHistory.length + 1
                        : _panelHistory.length,
                    itemBuilder: (context, index) {
                      if (_isStreaming) {
                        if (index == 0) {
                          return _buildDefinitionCard(
                            word: widget.initialWord ?? 'Loading...',
                            definition: _buffer.toString(),
                            isLoading: _buffer.isEmpty,
                            styleSheet: markdownStyle,
                          );
                        }
                        final item = _panelHistory[index - 1];
                        return _buildDefinitionCard(
                          word: item['word']!,
                          definition: item['definition']!,
                          isLoading: false,
                          styleSheet: markdownStyle,
                          onDelete: () => _deleteHistoryItem(index - 1),
                        );
                      }
                      final item = _panelHistory[index];
                      return _buildDefinitionCard(
                        word: item['word']!,
                        definition: item['definition']!,
                        isLoading: false,
                        styleSheet: markdownStyle,
                        onDelete: () => _deleteHistoryItem(index),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefinitionCard({
    required String word,
    required String definition,
    required bool isLoading,
    required MarkdownStyleSheet styleSheet,
    VoidCallback? onDelete,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  word,
                  style: GoogleFonts.nunito(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!isLoading && onDelete != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded,
                        size: 20, color: Colors.redAccent),
                    onPressed: onDelete,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (isLoading)
            const Center(child: LinearProgressIndicator())
          else
            SelectionArea(
              child: MarkdownBody(data: definition, styleSheet: styleSheet),
            ),
        ],
      ),
    );
  }
}
