import 'package:flutter/material.dart';

/// A circular icon button used in the content bottom bar.
class ContentCircleButton extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  final bool isAccent;

  const ContentCircleButton({
    super.key,
    required this.onTap,
    required this.icon,
    this.isAccent = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        width: 52,
        decoration: BoxDecoration(
          color: isAccent
              ? theme.colorScheme.secondary.withValues(alpha: 0.1)
              : theme.cardTheme.color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isAccent
                ? theme.colorScheme.secondary.withValues(alpha: 0.3)
                : theme.dividerColor.withValues(alpha: 0.05),
            width: 2,
          ),
        ),
        child: Center(
          child: Icon(
            icon,
            color: isAccent
                ? theme.colorScheme.secondary
                : theme.iconTheme.color,
            size: 26,
          ),
        ),
      ),
    );
  }
}
