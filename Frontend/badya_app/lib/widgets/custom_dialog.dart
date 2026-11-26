import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class CustomDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final VoidCallback? onDelete;
  final VoidCallback onCancel;
  final VoidCallback? onSave;
  final String saveButtonText;
  final String cancelButtonText;
  final Color saveButtonColor;
  final bool showSaveButton;
  final bool showActions;
  final bool showCancelButton;
  final bool isLoading;

  const CustomDialog({
    super.key,
    required this.title,
    required this.content,
    this.onDelete,
    required this.onCancel,
    this.onSave,
    this.saveButtonText = 'Save',
    this.cancelButtonText = 'Cancel',
    this.saveButtonColor = const Color(0xFF4ECDC4),
    this.showSaveButton = true,
    this.showActions = true,
    this.showCancelButton = true,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Theme-aware colors
    final backgroundColor = isDark
        ? const Color(0xFF1A1C1E) // Sleeker dark
        : const Color(0xFFFDF4DD); // Warm Cream to match theme
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.05);
    final titleColor = isDark ? Colors.white : const Color(0xFF1A1C1E);
    final cancelTextColor = isDark ? Colors.white70 : const Color(0xFF636E72);
    final saveTextColor = Colors.white;

    return Dialog(
      backgroundColor: backgroundColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: borderColor, width: 1),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: GoogleFonts.nunito(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: titleColor,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    if (onDelete != null)
                      IconButton(
                        onPressed: onDelete,
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.redAccent,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                content,
                const SizedBox(height: 32),
                if (showActions)
                  Row(
                    children: [
                      // Cancel Button
                      if (showCancelButton)
                        Expanded(
                          child: TextButton(
                            onPressed: isLoading ? null : onCancel,
                            style: TextButton.styleFrom(
                              backgroundColor: isDark
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : Colors.black.withValues(alpha: 0.05),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            child: Text(
                              cancelButtonText,
                              style: GoogleFonts.nunito(
                                fontWeight: FontWeight.w800,
                                color: cancelTextColor,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                      if (showSaveButton && onSave != null) ...[
                        const SizedBox(width: 12),
                        // Save/Action Button
                        Expanded(
                          child: ElevatedButton(
                            onPressed: isLoading ? null : onSave,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: saveButtonColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            child: isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    saveButtonText,
                                    style: GoogleFonts.nunito(
                                      fontWeight: FontWeight.w900,
                                      color: saveTextColor,
                                      fontSize: 15,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
