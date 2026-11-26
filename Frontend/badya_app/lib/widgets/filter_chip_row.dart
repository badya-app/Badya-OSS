import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A filter option in the library page's horizontal chip row.
class FilterOption {
  final String label;
  final String? type; // 'all', 'mine', 'public', 'ai_generated', 'youtube', 'document', 'pdf', etc.
  final IconData? icon;

  const FilterOption({
    required this.label,
    this.type,
    this.icon,
  });
}

/// Horizontal scrollable row of filter chips for the library page.
/// Filters: All | Mine | Public | AI | Videos | Docs | PDF
class FilterChipRow extends StatelessWidget {
  final List<FilterOption> filters;
  final String? activeFilter;
  final ValueChanged<String> onFilterChanged;

  const FilterChipRow({
    super.key,
    required this.filters,
    required this.activeFilter,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        clipBehavior: Clip.none,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = activeFilter == filter.type;
          return _FilterChipButton(
            label: filter.label,
            icon: filter.icon,
            isSelected: isSelected,
            onTap: () => onFilterChanged(filter.type ?? 'all'),
          );
        },
      ),
    );
  }
}

class _FilterChipButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChipButton({
    required this.label,
    this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_FilterChipButton> createState() => _FilterChipButtonState();
}

class _FilterChipButtonState extends State<_FilterChipButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color bgColor = widget.isSelected
        ? const Color(0xFF4ECDC4) // Teal accent when selected
        : (isDark
            ? const Color(0xFF2D2D2D)
            : Colors.white);
    final Color fgColor = widget.isSelected
        ? Colors.black
        : (isDark ? Colors.white70 : Colors.black54);

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _isPressed && !widget.isSelected
                ? (isDark
                    ? const Color(0xFF3D3D3D)
                    : Colors.grey.shade200)
                : bgColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.isSelected
                  ? const Color(0xFF4ECDC4)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.10)
                      : Colors.black.withValues(alpha: 0.10)),
            ),
            boxShadow: widget.isSelected
                ? [
                    BoxShadow(
                      color: Color(0xFF4ECDC4).withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  size: 16,
                  color: fgColor,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                widget.label,
                style: GoogleFonts.nunito(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: fgColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
