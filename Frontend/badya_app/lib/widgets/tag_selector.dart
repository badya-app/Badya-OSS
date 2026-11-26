import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:Badya/services/tag_service.dart';

/// A tag selector widget with auto-suggest from user's tag history.
///
/// Features:
/// - Text field with tag input
/// - Auto-suggest dropdown from user's most frequent tags
/// - Selected tags shown as removable chips below the field
/// - Known tags displayed as suggestion chips above
class TagSelector extends StatefulWidget {
  final List<String> initialTags;
  final ValueChanged<List<String>> onTagsChanged;
  final String hintText;
  final bool showSuggestions;

  const TagSelector({
    super.key,
    this.initialTags = const [],
    required this.onTagsChanged,
    this.hintText = 'Add tags...',
    this.showSuggestions = true,
  });

  @override
  State<TagSelector> createState() => _TagSelectorState();
}

class _TagSelectorState extends State<TagSelector> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final TagService _tagService = TagService();

  List<String> _selectedTags = [];
  List<String> _suggestions = [];
  List<String> _filteredSuggestions = [];
  bool _showSuggestionsOverlay = false;
  bool _isLoadingSuggestions = false;

  @override
  void initState() {
    super.initState();
    _selectedTags = List.from(widget.initialTags);
    _controller.addListener(_onTextChanged);
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _controller.text.isEmpty) {
        _loadSuggestions();
      } else if (!_focusNode.hasFocus) {
        setState(() => _showSuggestionsOverlay = false);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    setState(() => _isLoadingSuggestions = true);
    final tags = await _tagService.getTagSuggestions(limit: 15);
    if (mounted) {
      setState(() {
        // Exclude already selected tags from suggestions
        _suggestions = tags
            .where((t) => !_selectedTags.contains(t))
            .toList();
        _filteredSuggestions = List.from(_suggestions);
        _showSuggestionsOverlay = true;
        _isLoadingSuggestions = false;
      });
    }
  }

  void _onTextChanged() {
    final query = _controller.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredSuggestions = List.from(_suggestions);
      } else {
        _filteredSuggestions = _suggestions
            .where((t) => t.toLowerCase().contains(query))
            .toList();
      }
      _showSuggestionsOverlay = _focusNode.hasFocus;
    });
  }

  void _addTag(String tag) {
    final normalized = tag.trim().toLowerCase();
    if (normalized.isEmpty || _selectedTags.contains(normalized)) return;

    setState(() {
      _selectedTags.add(normalized);
      _suggestions.remove(normalized);
      _filteredSuggestions.remove(normalized);
      _controller.clear();
    });
    widget.onTagsChanged(List.from(_selectedTags));
  }

  void _removeTag(String tag) {
    setState(() {
      _selectedTags.remove(tag);
      if (!_suggestions.contains(tag)) {
        _suggestions.add(tag);
      }
      _filteredSuggestions = List.from(_suggestions);
    });
    widget.onTagsChanged(List.from(_selectedTags));
  }

  void _onSubmitText() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) {
      _addTag(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tealColor = const Color(0xFF4ECDC4);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected tags chips
        if (_selectedTags.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _selectedTags.map((tag) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: tealColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: tealColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tag,
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: tealColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => _removeTag(tag),
                      child: Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: tealColor.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
        ],

        // Text field
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          onSubmitted: (_) => _onSubmitText(),
          style: GoogleFonts.nunito(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
          decoration: InputDecoration(
            hintText: _selectedTags.isEmpty ? widget.hintText : 'Add more tags...',
            hintStyle: GoogleFonts.nunito(
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white30 : Colors.black26,
            ),
            filled: true,
            fillColor: isDark
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.black.withValues(alpha: 0.03),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: tealColor, width: 1.5),
            ),
            suffixIcon: IconButton(
              onPressed: _onSubmitText,
              icon: Icon(
                Icons.add_rounded,
                color: tealColor,
                size: 20,
              ),
            ),
          ),
        ),

        // Suggestions
        if (_showSuggestionsOverlay && _filteredSuggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 140),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2D2D2D) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _filteredSuggestions.length.clamp(0, 8),
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.05),
                ),
                itemBuilder: (context, index) {
                  final tag = _filteredSuggestions[index];
                  return InkWell(
                    onTap: () => _addTag(tag),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          Icon(
                            Icons.tag_rounded,
                            size: 16,
                            color: tealColor.withValues(alpha: 0.6),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            tag,
                            style: GoogleFonts.nunito(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// A single tag pill used inside TagSelector and elsewhere.
class TagPill extends StatelessWidget {
  final String label;
  final bool isCompact;
  final VoidCallback? onTap;

  const TagPill({
    super.key,
    required this.label,
    this.isCompact = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 8 : 12,
          vertical: isCompact ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.nunito(
            fontSize: isCompact ? 11 : 13,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ),
      ),
    );
  }
}
