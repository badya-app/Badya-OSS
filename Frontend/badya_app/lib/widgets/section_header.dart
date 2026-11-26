import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A reusable section header widget.
///
/// Default style (profile_page):
///   SectionHeader(title: 'Languages')
///
/// With subtitle (notification_settings_sheet):
///   SectionHeader(title: 'Active Hours', subtitle: 'Choose when...')
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final double fontSize;
  final FontWeight fontWeight;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.fontSize = 22,
    this.fontWeight = FontWeight.w900,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (subtitle != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.nunito(
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: theme.textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: GoogleFonts.nunito(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.grey[500],
            ),
          ),
        ],
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: GoogleFonts.nunito(
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: theme.textTheme.titleLarge?.color,
        ),
      ),
    );
  }
}
