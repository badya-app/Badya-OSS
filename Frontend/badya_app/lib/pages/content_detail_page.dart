import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Badya/config/content_types.dart';
import 'package:Badya/models/user_content.dart';
import 'package:Badya/lesson_paths_page.dart';
import 'package:Badya/import_course_page.dart';
import 'package:Badya/services/language_manager.dart';
import 'package:Badya/services/vocab_review_service.dart';
import 'package:Badya/services/adk_service.dart';
import 'package:Badya/config/local_mode.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Navigate to the appropriate detail page for this content.
/// For AI-generated content, pre-loads vocabulary before navigating
/// so that LessonPathsPage appears ready with words list.
class ContentDetailPage extends StatelessWidget {
  final UserContent content;

  const ContentDetailPage({
    super.key,
    required this.content,
  });

  /// Navigate to the appropriate detail page for this content.
  /// For AI-generated content, pre-loads or generates vocabulary
  /// BEFORE navigating, so LessonPathsPage appears ready.
  ///
  /// If [showLoading] is true, shows a loading dialog while preparing content.
  static Future<void> navigate({
    required BuildContext context,
    required UserContent content,
    bool showLoading = false,
  }) async {
    // For AI-generated content, preload/generate words BEFORE navigation
    if (content.type == ContentType.aiGenerated) {
      if (showLoading) {
        await _showLoadingWhilePreparing(context, content);
      } else {
        await _ensureWordsExist(context, content);
      }
    }
    // Now navigate - LessonPathsPage will have words ready
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContentDetailPage(content: content),
      ),
    );
  }

  /// Show a loading dialog while preparing AI-generated content.
  /// This gives visual feedback on the current page before navigation.
  static Future<void> _showLoadingWhilePreparing(
    BuildContext context,
    UserContent content,
  ) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF222220) : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: Container(
          width: double.maxFinite,
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 1.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 400),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 320),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: surfaceColor,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: borderColor, width: 1.0),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Topic thumbnail if available
                    if (content.metadata?['thumbnail_url'] != null &&
                        (content.metadata!['thumbnail_url'] as String).isNotEmpty)
                      Container(
                        width: double.infinity,
                        height: 140,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: (content.metadata!['thumbnail_url'] as String).startsWith('http')
                            ? Image.network(
                                content.metadata!['thumbnail_url'] as String,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _loadingFallback(theme),
                              )
                            : Image.asset(
                                content.metadata!['thumbnail_url'] as String,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _loadingFallback(theme),
                              ),
                      ),

                    // Loading indicator with shimmer animation
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: const Color(0xFF9B59B6).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF9B59B6).withValues(alpha: 0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Color(0xFF9B59B6),
                        ),
                      ),
                    ).animate().shimmer(
                      duration: 1500.ms,
                      color: const Color(0xFF9B59B6).withValues(alpha: 0.3),
                    ),

                    const SizedBox(height: 28),

                    // Title
                    Text(
                      'Preparing your lesson…',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                        color: isDark ? Colors.white : const Color(0xFF2D3436),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Description
                    Text(
                      'Generating vocabulary cards for "${content.title}"',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Progress hint
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _decorativeDot(
                          color: const Color(0xFF9B59B6).withValues(alpha: 0.3),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'This may take a moment',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    try {
      await _ensureWordsExist(context, content);
    } finally {
      // Close the dialog
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  /// Loading fallback widget when image fails to load.
  static Widget _loadingFallback(ThemeData theme) {
    return Container(
      color: theme.cardTheme.color,
      child: Icon(
        Icons.image_not_supported_rounded,
        size: 40,
        color: theme.iconTheme.color,
      ),
    );
  }

  /// A small decorative dot for visual interest.
  static Widget _decorativeDot({required Color color}) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.5),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }

  /// Ensure words exist for AI-generated content - load from cache or generate via ADK.
  /// This runs BEFORE navigation so the user sees LessonPathsPage ready.
  static Future<void> _ensureWordsExist(
    BuildContext context,
    UserContent content,
  ) async {
    final uid = LocalMode.enabled
        ? LocalMode.guestUid
        : FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final language = context.read<LanguageManager>().currentLanguage;

    try {
      // Try to load existing words first
      final vocabService = VocabReviewService();
      final scopeId = VocabReviewService.topicScopeId(
        content.id,
        language,
      );
      var words = await vocabService.getAllWords(
        scope: VocabReviewService.scopeTopic,
        scopeId: scopeId,
      );

      if (words.isEmpty) {
        // No cached words — generate them via ADK
        final adkService = AdkService();
        await adkService.generateAndCacheWords(
          topicId: content.id,
          subject: content.title,
          description: content.description,
          language: language,
          difficulty: content.metadata?['difficulty'] as String? ?? 'intermediate',
          userId: uid,
        );

        words = await vocabService.getAllWords(
          scope: VocabReviewService.scopeTopic,
          scopeId: scopeId,
        );
      }
    } catch (_) {
      // Word generation failed — LessonPathsPage will handle regeneration on demand
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (content.type) {
      case ContentType.aiGenerated:
        return LessonPathsPage(
          subjectTitle: content.title,
          description: content.description,
          topicId: content.id,
          currentLanguage: context.read<LanguageManager>().currentLanguage,
          difficulty: content.metadata?['difficulty'] as String? ?? 'intermediate',
        );
      case ContentType.youtube:
        // Build importItem map from content for ImportCoursePage.
        // The actual Firestore import ID lives in metadata['legacy_import_id'],
        // NOT in content.id (which is the user_content doc ID).
        // Using the wrong ID means ImportCoursePage can't find lessons
        // and shows "Processing segments...\" forever.
        final importId = content.metadata?['legacy_import_id'] as String? ?? content.id;
        final importItem = <String, dynamic>{
          'id': importId,
          'title': content.title,
          'metadata': Map<String, dynamic>.from(content.metadata ?? {}),
        };
        return ImportCoursePage(
          importItem: importItem,
          contentId: content.id,
        );
      default:
        // Document / PDF / Text / Article — use ImportCoursePage with
        // virtual segmentation from ContentService.getContentSegments().
        // This provides lesson structure, progress tracking, and avoids
        // showing raw text dumps without segmentation.
        final importId = content.metadata?['legacy_import_id'] as String? ?? content.id;
        final importItem = <String, dynamic>{
          'id': importId,
          'title': content.title,
          'metadata': Map<String, dynamic>.from(content.metadata ?? {}),
        };
        return ImportCoursePage(
          importItem: importItem,
          contentId: content.id,
        );
    }
  }
}
