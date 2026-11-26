import 'package:Badya/utils/legal_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

/// Displays a legal document (Terms of Service / Privacy Policy) as a
/// scrollable, styled page.
///
/// Pushed from the signup form's acceptance row and from the profile's
/// Privacy & Security sheet. Content lives in [LegalContent] so it can be
/// updated in one place.
class LegalDocumentPage extends StatelessWidget {
  final LegalDocument document;
  final IconData icon;

  const LegalDocumentPage({
    super.key,
    required this.document,
    this.icon = Icons.menu_book_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF2D3436);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          document.title,
          style: GoogleFonts.merriweather(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: textColor,
          ),
        ),
      ),
      // SelectionArea lets users copy text (e.g. the contact email) from
      // the legal documents.
      body: SelectionArea(
        child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context, isDark),
            const SizedBox(height: 24),
            for (var i = 0; i < document.sections.length; i++)
              _buildSection(context, document.sections[i])
                  .animate()
                  .fadeIn(delay: (i * 40).ms, duration: 300.ms)
                  .slideY(begin: 0.05),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFF78B1E).withValues(alpha: 0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF78B1E).withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF78B1E), Color(0xFFFFB75E)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFF78B1E).withValues(alpha: 0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 34),
          ),
          const SizedBox(height: 16),
          Text(
            document.title,
            textAlign: TextAlign.center,
            style: GoogleFonts.merriweather(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: isDark ? Colors.white : const Color(0xFF2D3436),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFF78B1E).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Last updated: ${document.lastUpdated}',
              style: GoogleFonts.nunito(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFF78B1E),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.96, 0.96));
  }

  Widget _buildSection(BuildContext context, LegalSection section) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bodyColor = isDark ? Colors.white70 : Colors.black87;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.15),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: GoogleFonts.nunito(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: const Color(0xFFF78B1E),
            ),
          ),
          const SizedBox(height: 12),
          for (final paragraph in section.paragraphs)
            _buildParagraph(context, paragraph, bodyColor),
        ],
      ),
    );
  }

  Widget _buildParagraph(BuildContext context, String text, Color bodyColor) {
    final isBullet = text.startsWith('• ');
    if (!isBullet) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: GoogleFonts.nunito(
            fontSize: 13.5,
            height: 1.55,
            color: bodyColor,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Color(0xFF4ECDC4),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text.substring(2),
              style: GoogleFonts.nunito(
                fontSize: 13.5,
                height: 1.55,
                color: bodyColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
