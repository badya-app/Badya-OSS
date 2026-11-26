import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A reusable segmentation method selector widget.
///  /// Shows options: None, Fixed Duration (video only), and Word Count.
  /// When "Minutes" or "Words" is selected, a numeric input field appears.
  ///
  /// Use [onChanged] to receive the selected segmentation method and value.
class SegmentationSelector extends StatefulWidget {
  /// Source type: 'video', 'url', 'file', 'text'
  final String sourceType;

  /// Whether the content has chapter metadata available
  /// (extracted by the backend for YouTube/PDF).
  final bool hasChapters;

  /// Currently selected segmentation method ('none', 'minutes', 'words', 'chapters')
  final String initialSegmentBy;

  /// Current threshold value (only meaningful for 'minutes' and 'words')
  final int? initialSegmentValue;

  /// Called whenever the selection changes.
  final ValueChanged<SegmentationSelection>? onChanged;

  const SegmentationSelector({
    super.key,
    required this.sourceType,
    this.hasChapters = false,
    this.initialSegmentBy = 'none',
    this.initialSegmentValue,
    this.onChanged,
  });

  @override
  State<SegmentationSelector> createState() => _SegmentationSelectorState();
}

class _SegmentationSelectorState extends State<SegmentationSelector> {
  late String _segmentBy;
  late TextEditingController _segmentValueController;

  @override
  void initState() {
    super.initState();
    _segmentBy = widget.initialSegmentBy;
    final int defaultValue = _segmentBy == 'words' ? 1500 : 10;
    _segmentValueController = TextEditingController(
      text: (widget.initialSegmentValue ?? defaultValue).toString(),
    );
    _segmentValueController.addListener(_notifyChanged);
  }

  @override
  void dispose() {
    _segmentValueController.removeListener(_notifyChanged);
    _segmentValueController.dispose();
    super.dispose();
  }

  void _notifyChanged() {
    widget.onChanged?.call(SegmentationSelection(
      segmentBy: _segmentBy,
      segmentValue: _segmentBy == 'minutes' || _segmentBy == 'words'
          ? int.tryParse(_segmentValueController.text)
          : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isVideo = widget.sourceType == 'video';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Segmentation Method',
          style: GoogleFonts.nunito(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.05),
            ),
          ),
          child: Column(
            children: [
              _buildSegmentOption(
                id: 'none',
                title: 'No Segmentation',
                subtitle: 'Import as a single lesson',
                icon: Icons.unfold_less_rounded,
              ),
              if (isVideo)
                _buildSegmentOption(
                  id: 'minutes',
                  title: 'Fixed Duration',
                  subtitle: 'Segment every X minutes',
                  icon: Icons.timer_rounded,
                ),
              _buildSegmentOption(
                id: 'words',
                title: 'Word Count',
                subtitle: 'Segment every X words',
                icon: Icons.text_fields_rounded,
              ),
              if (widget.hasChapters)
                _buildSegmentOption(
                  id: 'chapters',
                  title: 'Chapters',
                  subtitle: 'Use video/document chapters',
                  icon: Icons.menu_book_rounded,
                ),
            ],
          ),
        ),
        if (_segmentBy == 'minutes' || _segmentBy == 'words') ...[
          const SizedBox(height: 16),
          _buildValueField(isDark),
        ],
      ],
    );
  }

  Widget _buildValueField(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _segmentBy == 'minutes' ? 'Minutes per Lesson' : 'Words per Lesson',
          style: GoogleFonts.nunito(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _segmentValueController,
          keyboardType: TextInputType.number,
          style: GoogleFonts.nunito(
            color: isDark ? Colors.white70 : Colors.black87,
            fontWeight: FontWeight.w700,
          ),
          decoration: InputDecoration(
            hintText: _segmentBy == 'minutes' ? 'e.g. 10' : 'e.g. 1500',
            hintStyle: GoogleFonts.nunito(
              color: isDark ? Colors.white12 : Colors.black26,
              fontWeight: FontWeight.w600,
            ),
            suffixIcon: Icon(
              _segmentBy == 'minutes'
                  ? Icons.av_timer_rounded
                  : Icons.format_list_numbered_rounded,
              color: const Color(0xFF4ECDC4),
            ),
            filled: true,
            fillColor: isDark
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.black.withValues(alpha: 0.03),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.05),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(
                color: Color(0xFF4ECDC4),
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSegmentOption({
    required String id,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _segmentBy == id;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color tealColor = const Color(0xFF4ECDC4);

    return InkWell(
      onTap: () {
        setState(() {
          // Auto-adjust value when switching between minutes and words
          if (id == 'words' &&
              _segmentBy == 'minutes' &&
              _segmentValueController.text == '10') {
            _segmentValueController.text = '1500';
          } else if (id == 'minutes' &&
              _segmentBy == 'words' &&
              _segmentValueController.text == '1500') {
            _segmentValueController.text = '10';
          }
          _segmentBy = id;
          _notifyChanged();
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? tealColor.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected
                  ? tealColor
                  : (isDark ? Colors.white24 : Colors.black26),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.nunito(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: isDark
                          ? (isSelected ? Colors.white : Colors.white70)
                          : (isSelected ? Colors.black : Colors.black87),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.nunito(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white24 : Colors.black26,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: tealColor, size: 18),
          ],
        ),
      ),
    );
  }

  /// Returns the current selection as a [SegmentationSelection].
  SegmentationSelection get currentSelection => SegmentationSelection(
    segmentBy: _segmentBy,
    segmentValue: (_segmentBy == 'minutes' || _segmentBy == 'words')
        ? int.tryParse(_segmentValueController.text)
        : null,
  );
}

/// Result model for segmentation selection.
class SegmentationSelection {
  final String segmentBy;
  final int? segmentValue;

  const SegmentationSelection({
    required this.segmentBy,
    this.segmentValue,
  });

  /// Whether the selection is valid.
  bool get isValid {
    if (segmentBy == 'chapters') return true;
    if (segmentBy == 'minutes' || segmentBy == 'words') {
      return segmentValue != null && segmentValue! > 0;
    }
    return true;
  }
}
