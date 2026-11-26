import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A neutral tag chip/pill used across the library page.
/// Tags have no semantic color — they are neutral pills.
class TagChip extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback? onTap;
  final bool isCompact;

  const TagChip({
    super.key,
    required this.label,
    this.isSelected = false,
    this.onTap,
    this.isCompact = false,
  });

  @override
  State<TagChip> createState() => _TagChipState();
}

class _TagChipState extends State<TagChip> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color bgColor = widget.isSelected
        ? (isDark ? const Color(0xFF4ECDC4) : const Color(0xFF4ECDC4))
        : (isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.06));

    final Color fgColor = widget.isSelected
        ? (isDark ? Colors.black : Colors.white)
        : (isDark ? Colors.white70 : Colors.black54);

    final Color pressedBg = widget.isSelected
        ? bgColor
        : (isDark
            ? Colors.white.withValues(alpha: 0.14)
            : Colors.black.withValues(alpha: 0.10));

    return GestureDetector(
      onTapDown: widget.onTap != null
          ? (_) => setState(() => _isPressed = true)
          : null,
      onTapUp: widget.onTap != null
          ? (_) {
              setState(() => _isPressed = false);
              widget.onTap!();
            }
          : null,
      onTapCancel: widget.onTap != null
          ? () => setState(() => _isPressed = false)
          : null,
      // onTap intentionally omitted — onTapUp handles the callback + state reset
      child: AnimatedScale(
        scale: _isPressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(
            horizontal: widget.isCompact ? 8 : 12,
            vertical: widget.isCompact ? 4 : 6,
          ),
          decoration: BoxDecoration(
            color: _isPressed && !widget.isSelected ? pressedBg : bgColor,
            borderRadius: BorderRadius.circular(16),
            border: widget.isSelected
                ? Border.all(color: const Color(0xFF4ECDC4), width: 1)
                : null,
          ),
          child: Text(
            widget.label,
            style: GoogleFonts.nunito(
              fontSize: widget.isCompact ? 10 : 12,
              fontWeight: FontWeight.w700,
              color: fgColor,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// A static tag pill (non-interactive, displayed on cards).
class TagPill extends StatelessWidget {
  final String label;
  final bool isCompact;

  const TagPill({
    super.key,
    required this.label,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 8 : 10,
        vertical: isCompact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: GoogleFonts.nunito(
          fontSize: isCompact ? 10 : 11,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white70 : Colors.black54,
        ),
      ),
    );
  }
}
