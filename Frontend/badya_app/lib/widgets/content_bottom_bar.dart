import 'package:flutter/material.dart';
import 'package:Badya/widgets/content_circle_button.dart';

/// Bottom bar with definition and font controls for content pages.
class ContentBottomBar extends StatelessWidget {
  final VoidCallback onDefinitionTap;
  final VoidCallback onFontTap;
  final bool showFontActive;

  const ContentBottomBar({
    super.key,
    required this.onDefinitionTap,
    required this.onFontTap,
    this.showFontActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            /// Definition toggle
            ContentCircleButton(
              onTap: onDefinitionTap,
              icon: Icons.menu_book_rounded,
            ),
            const SizedBox(width: 16),
            /// Font size
            ContentCircleButton(
              onTap: onFontTap,
              icon: showFontActive
                  ? Icons.text_fields
                  : Icons.text_fields_outlined,
              isAccent: showFontActive,
            ),
          ],
        ),
      ),
    );
  }
}
