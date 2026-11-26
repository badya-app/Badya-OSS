import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:Badya/utils/profile_images.dart';

/// Shows a bottom sheet with the bundled profile avatars for the user to
/// pick from. Returns the selected asset path, or `null` if cancelled.
Future<String?> showAvatarPickerSheet(
  BuildContext context,
) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).cardTheme.color,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => const _AvatarPickerSheet(),
  );
}

class _AvatarPickerSheet extends StatelessWidget {
  const _AvatarPickerSheet();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          Text(
            'Choose Avatar',
            style: GoogleFonts.nunito(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Theme.of(context).textTheme.titleLarge?.color,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Pick an avatar that represents you',
            style: GoogleFonts.nunito(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white38 : Colors.black45,
            ),
          ),
          const SizedBox(height: 20),

          // Avatar grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1,
            ),
            itemCount: kProfileImages.length,
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () => Navigator.of(context).pop(kProfileImages[index]),
                child: ClipOval(
                  child: Image.asset(
                    kProfileImages[index],
                    fit: BoxFit.cover,
                  ),
                ),
              ).animate().fadeIn(
                duration: 300.ms,
                delay: (index * 30).ms,
              ).scale(
                begin: const Offset(0.85, 0.85),
                end: const Offset(1, 1),
                curve: Curves.easeOutBack,
              );
            },
          ),
        ],
      ),
    );
  }
}
