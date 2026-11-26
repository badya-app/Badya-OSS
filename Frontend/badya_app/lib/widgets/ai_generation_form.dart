import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:Badya/config/api_config.dart';
import 'package:Badya/models/transaction_model.dart' as billing;
import 'package:Badya/services/adk_service.dart';
import 'package:Badya/services/coin_service.dart';
import 'package:Badya/services/content_service.dart';
import 'package:Badya/utils/ui_utils.dart';
import 'package:Badya/config/content_types.dart';
import 'package:Badya/widgets/custom_dialog.dart';
import 'package:Badya/widgets/tag_selector.dart';
import 'package:Badya/lesson_paths_page.dart';
import 'package:Badya/utils/logger.dart';
import 'package:Badya/services/cache_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Form for generating AI content.
///
/// Features:
/// - Topic field
/// - Description field
/// - Difficulty selector (Beginner, Intermediate, Advanced)
/// - Tags selector (suggestions on focus)
/// - Visibility toggle
/// - Generation progress with animated state
/// - Connects to AdkService for generation
class AIGenerationForm extends StatefulWidget {
  final String language;
  final List<String> tags;
  final VoidCallback? onCancel;

  const AIGenerationForm({
    super.key,
    this.language = 'English',
    this.tags = const [],
    this.onCancel,
  });

  @override
  State<AIGenerationForm> createState() => _AIGenerationFormState();
}

class _AIGenerationFormState extends State<AIGenerationForm>
    with SingleTickerProviderStateMixin {
  final _topicController = TextEditingController();
  final _descriptionController = TextEditingController();
  final AdkService _adkService = AdkService();
  final ContentService _contentService = ContentService();

  // Visibility
  bool _isPublic = true;

  // Image generation toggle
  bool _generateImage = true;

  // Difficulty
  String _difficulty = 'intermediate'; // 'beginner', 'intermediate', 'advanced'

  // Tags
  List<String> _tags = [];

  // Generation state
  bool _isGenerating = false;
  String _generationStatus = '';
  int _currentStatusIndex = 0;
  late AnimationController _pulseController;

  // Progress messages shown during generation
  static const List<String> _progressMessages = [
    'Crafting lesson structure...',
    'Generating vocabulary...',
    'Creating exercises...',
    'Building conversation practice...',
    'Generating thumbnail image...',
    'Reviewing and polishing...',
    'Finalizing content...',
  ];

  bool get _isFormValid =>
      _topicController.text.trim().isNotEmpty &&
      _descriptionController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _tags = List.from(widget.tags);

    _topicController.addListener(() => setState(() {}));
    _descriptionController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _topicController.dispose();
    _descriptionController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _handleGenerate() async {
    if (!_isFormValid) return;

    setState(() {
      _isGenerating = true;
      _currentStatusIndex = 0;
      _generationStatus = _progressMessages[0];
    });

    // Animate through progress messages
    _startStatusAnimation();

    String? contentId;

    try {
      final user = FirebaseAuth.instance.currentUser;
      final uid = user?.uid ?? 'anonymous';

      // Step 1: Create the content entry in Firestore (processing state)
      contentId = await _contentService.addContent(
        userId: uid,
        authorName: user?.displayName ?? '',
        authorPhotoUrl: user?.photoURL,
        type: ContentType.aiGenerated,
        title: _topicController.text.trim(),
        description: _descriptionController.text.trim(),
        tags: _tags,
        language: widget.language,
        isPublic: _isPublic,
        source: ContentSource.aiGenerated,
        originType: OriginType.userCreated,
        status: ContentStatus.processing,
        aiPrompt:
            'Topic: ${_topicController.text.trim()}\nDifficulty: $_difficulty\nDescription: ${_descriptionController.text.trim()}',
      );

      setState(() => _generationStatus = _progressMessages[1]);

      // Step 2: Connect to ADK word_generator_agent for generation
      await _adkService.generateAndCacheWords(
        topicId: contentId!,
        subject: _topicController.text.trim(),
        description: _descriptionController.text.trim(),
        language: widget.language,
        difficulty: _difficulty,
        userId: uid,
      );

      // Step 3: Optionally generate thumbnail image via Python server
      String? thumbnailUrl;
      if (_generateImage) {
        // Charge 3 coins for image generation
        final coinService = CoinService();
        final accessResult = await coinService.canAccessContent(
          billing.ContentType.thumbnail,
        );
        if (accessResult.canAccess) {
          await coinService.spendForContent(
            billing.ContentType.thumbnail,
            contentId!,
          );
          setState(() => _generationStatus = _progressMessages[4]);
          try {
            final prompt = await _adkService.generateThumbnailPrompt(
              title: _topicController.text.trim(),
              description: _descriptionController.text.trim(),
            );
            if (prompt != null) {
              thumbnailUrl = await _adkService.generateImage(
                prompt: prompt,
                userId: uid,
              );
            }
          } on RateLimitException catch (e) {
            if (mounted) _showRateLimitDialog(e.message);
          } catch (_) {
            // Other errors — image generation is optional, ignore silently
          }
        } else {
          // Not enough coins — skip image generation
          Logger.warn('Insufficient coins for image generation — skipping');
        }
      }

      setState(() => _generationStatus = _progressMessages[5]);

      // Step 4: Generate embedding for recommendation system
      final embedding = await _embedContent(
        title: _topicController.text.trim(),
        description: _descriptionController.text.trim(),
        tags: _tags,
      );

      // Step 5: Mark as ready with optional thumbnail and embedding
      final metadata = <String, dynamic>{
        'difficulty': _difficulty,
        'generated_at': DateTime.now().toIso8601String(),
      };
      if (thumbnailUrl != null) {
        metadata['thumbnail_url'] = thumbnailUrl;
      }
      if (embedding != null) {
        metadata['embedding'] = embedding;
      }
      await _contentService.updateImportStatus(
        contentId!,
        ContentStatus.ready,
        metadata: metadata,
      );
      if (thumbnailUrl != null) {
        await _contentService.updateContent(
          contentId!,
          thumbnailUrl: thumbnailUrl,
        );
      }

      // Step 5: Cache the content
      final cacheService = await _getCacheService();
      if (cacheService != null) {
        await cacheService.setCache(
          contentId: contentId!,
          data: {
            'content_id': contentId!,
            'title': _topicController.text.trim(),
            'type': 'ai_generated',
            'language': widget.language,
          },
        );
      }

      if (mounted) {
        setState(() => _isGenerating = false);
        Navigator.of(context).pop();
        await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(
            builder: (_) => LessonPathsPage(
              topicId: contentId!,
              subjectTitle: _topicController.text.trim(),
              description: _descriptionController.text.trim(),
              currentLanguage: widget.language,
              difficulty: _difficulty,
            ),
          ),
        );
      }
    } catch (e) {
      // Mark content as failed so it doesn't get stuck in 'processing' state
      if (contentId != null) {
        try {
          await _contentService.updateImportStatus(
            contentId!,
            ContentStatus.failed,
          );
        } catch (e) {
          Logger.warn('Failed to mark content as failed: $e');
        }
      }

      if (mounted) {
        setState(() {
          _isGenerating = false;
          _generationStatus = 'Generation failed: $e';
        });
        UiUtils.showErrorSnackbar(context, 'AI generation failed: $e');
      }
    }
  }

  void _showRateLimitDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => CustomDialog(
        title: 'Daily Limit Reached',
        showCancelButton: false,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.timer_off_rounded,
                size: 40,
                color: Colors.orangeAccent,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              style: GoogleFonts.nunito(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'You can generate up to 5 images per day. Please try again tomorrow.',
              style: GoogleFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white54
                    : Colors.black45,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        saveButtonText: 'OK',
        saveButtonColor: Colors.orangeAccent,
        onSave: () => Navigator.pop(ctx),
        onCancel: () => Navigator.pop(ctx),
      ),
    );
  }

  Future<CacheService?> _getCacheService() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return CacheService(prefs);
    } catch (_) {
      return null;
    }
  }

  /// Generate embedding for the content via the AI server's /recommendations/embed endpoint.
  /// Returns null if the backend is unreachable or returns an empty/zero vector.
  Future<List<double>?> _embedContent({
    required String title,
    required String description,
    required List<String> tags,
  }) async {
    try {
      final url = Uri.parse('${ApiConfig.getBaseUrl()}/recommendations/embed');
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'title': title,
              'description': description,
              'tags': tags,
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        final embedding = List<double>.from(result['embedding']);
        // Check for zero vector — don't store if empty
        if (embedding.any((v) => v != 0.0)) {
          return embedding;
        }
      }
    } catch (e) {
      // Backend unreachable or timeout — embedding is optional
      Logger.warn('Embedding generation failed (non-blocking): $e');
    }
    return null;
  }

  void _startStatusAnimation() {
    Future.doWhile(() async {
      if (!mounted || !_isGenerating) return false;
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted || !_isGenerating) return false;
      setState(() {
        _currentStatusIndex =
            (_currentStatusIndex + 1) % _progressMessages.length;
        _generationStatus = _progressMessages[_currentStatusIndex];
      });
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tealColor = const Color(0xFF4ECDC4);

    if (_isGenerating) {
      return _buildGeneratingState(context, isDark, tealColor);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Topic
        _buildField(
          context: context,
          label: 'Topic',
          controller: _topicController,
          hint: 'e.g. Spanish Restaurant Conversation',
          icon: Icons.topic_rounded,
        ),
        const SizedBox(height: 16),

        // Description
        _buildField(
          context: context,
          label: 'Description / Focus Areas',
          controller: _descriptionController,
          hint: 'Describe what you want to learn...',
          icon: Icons.description_rounded,
          maxLines: 3,
        ),
        const SizedBox(height: 16),

        // Difficulty selector
        _buildDifficultySelector(context, tealColor),
        const SizedBox(height: 16),

        // Tags
        Text(
          'Tags',
          style: GoogleFonts.nunito(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
        const SizedBox(height: 8),
        TagSelector(
          initialTags: _tags,
          onTagsChanged: (tags) {
            setState(() => _tags = tags);
          },
          hintText: 'Add tags to organize your content...',
        ),
        const SizedBox(height: 16),

        // ─── Visibility toggle ────────────────────────────────────
        _buildVisibilityToggle(),

        const SizedBox(height: 12),

        // ─── Image generation toggle ─────────────────────────────
        _buildImageToggle(),

        const SizedBox(height: 32),

        // ─── Back + Generate buttons (import-dialog style) ─────────
        LayoutBuilder(
          builder: (context, constraints) {
            final useStack = constraints.maxWidth < 300;
            final List<Widget> buttons = [
              // Generate first
              Expanded(
                flex: useStack ? 0 : 1,
                child: ElevatedButton(
                  onPressed: _isFormValid ? _handleGenerate : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: tealColor,
                    disabledBackgroundColor: tealColor.withValues(alpha: 0.25),
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(56),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Generate',
                          style: GoogleFonts.nunito(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(width: useStack ? 0 : 16, height: useStack ? 12 : 0),
              // Back after
              Expanded(
                flex: useStack ? 0 : 1,
                child: OutlinedButton(
                  onPressed: widget.onCancel,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    side: BorderSide(
                      color: isDark ? Colors.white10 : Colors.black12,
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'Back',
                      style: GoogleFonts.nunito(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ),
              ),
            ];

            return useStack
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: buttons
                        .map((e) => e is Expanded ? e.child : e)
                        .toList(),
                  )
                : Row(children: buttons);
          },
        ),
      ],
    );
  }

  Widget _buildGeneratingState(
    BuildContext context,
    bool isDark,
    Color tealColor,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 16),

        // Animated icon
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Color(0xFF9B59B6).withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Transform.scale(
                scale: 0.8 + (_pulseController.value * 0.2),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 40,
                  color: Color(0xFF9B59B6),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 24),

        // Status message
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: Text(
            _generationStatus,
            key: ValueKey(_generationStatus),
            style: GoogleFonts.nunito(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 16),

        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(seconds: 3),
            builder: (context, value, child) {
              return LinearProgressIndicator(
                value: value,
                minHeight: 4,
                backgroundColor: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.05),
                valueColor: const AlwaysStoppedAnimation(Color(0xFF9B59B6)),
              );
            },
          ),
        ),
        const SizedBox(height: 12),

        const SizedBox(height: 24),

        // Animated dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            return AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final jump = math.sin(
                  (_pulseController.value * 2 * math.pi) - (index * 1.2),
                );
                final offset = jump < 0 ? jump * 6 : 0.0;
                return Transform.translate(
                  offset: Offset(0, offset),
                  child: Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: const BoxDecoration(
                      color: Color(0xFF9B59B6),
                      shape: BoxShape.circle,
                    ),
                  ),
                );
              },
            );
          }),
        ),
      ],
    );
  }

  Widget _buildField({
    required BuildContext context,
    required String label,
    required TextEditingController controller,
    String? hint,
    IconData? icon,
    int maxLines = 1,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.nunito(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: GoogleFonts.nunito(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.nunito(
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
            prefixIcon: icon != null
                ? Icon(icon, color: const Color(0xFF4ECDC4), size: 20)
                : null,
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
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.06),
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

  Widget _buildVisibilityToggle() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tealColor = const Color(0xFF4ECDC4);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          'Public',
          style: GoogleFonts.nunito(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        activeTrackColor: tealColor,
        value: _isPublic,
        onChanged: (v) => setState(() => _isPublic = v),
      ),
    );
  }

  Widget _buildImageToggle() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tealColor = const Color(0xFF4ECDC4);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          'AI Thumbnail',
          style: GoogleFonts.nunito(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        subtitle: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  stops: const [0.0, 0.5, 1.0],
                  colors: [
                    isDark ? const Color(0xFF2A2A28) : const Color(0xFFF8F6F3),
                    isDark ? const Color(0xFF222220) : const Color(0xFFF3EFE9),
                    isDark ? const Color(0xFF2A2A28) : const Color(0xFFF8F6F3),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFFFFD93D).withValues(alpha: 0.25)
                      : const Color(0x1A2D3436),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    const IconData(0xe800, fontFamily: 'MyFlutterApp'),
                    size: 20,
                    color: isDark
                        ? const Color(0xFFFFD93D)
                        : const Color(0xFFF5A623),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '3 coins',
                    style: GoogleFonts.nunito(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: isDark
                          ? const Color(0xFFFFD93D)
                          : const Color(0xFF2A2A28),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        activeTrackColor: tealColor,
        value: _generateImage,
        onChanged: (v) => setState(() => _generateImage = v),
      ),
    );
  }

  Widget _buildDifficultySelector(BuildContext context, Color tealColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Difficulty',
          style: GoogleFonts.nunito(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
        const SizedBox(height: 8),
        _buildDifficultyChip(
          value: 'beginner',
          label: 'Beginner',
          icon: Icons.eco_rounded,
          subtitle: 'Just starting out',
        ),
        const SizedBox(height: 6),
        _buildDifficultyChip(
          value: 'intermediate',
          label: 'Intermediate',
          icon: Icons.trending_up_rounded,
          subtitle: 'Building proficiency',
        ),
        const SizedBox(height: 6),
        _buildDifficultyChip(
          value: 'advanced',
          label: 'Advanced',
          icon: Icons.rocket_launch_rounded,
          subtitle: 'Deep mastery',
        ),
      ],
    );
  }

  Widget _buildDifficultyChip({
    required String value,
    required String label,
    required IconData icon,
    String subtitle = '',
  }) {
    final isSelected = _difficulty == value;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tealColor = const Color(0xFF4ECDC4);

    Color chipColor;
    switch (value) {
      case 'beginner':
        chipColor = const Color(0xFF2ECC71);
      case 'intermediate':
        chipColor = const Color(0xFFFFD93D);
      case 'advanced':
        chipColor = const Color(0xFFFF6B6B);
      default:
        chipColor = tealColor;
    }

    return GestureDetector(
      onTap: () => setState(() => _difficulty = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? chipColor.withValues(alpha: 0.12)
              : (isDark
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.black.withValues(alpha: 0.03)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? chipColor
                : (isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.06)),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isSelected
                    ? chipColor.withValues(alpha: 0.2)
                    : (isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.black.withValues(alpha: 0.04)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 20,
                color: isSelected
                    ? chipColor
                    : (isDark ? Colors.white38 : Colors.black38),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.nunito(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? (isDark ? Colors.white : Colors.black87)
                          : (isDark ? Colors.white54 : Colors.black45),
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: GoogleFonts.nunito(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isSelected
                            ? chipColor.withValues(alpha: 0.8)
                            : (isDark ? Colors.white24 : Colors.black26),
                      ),
                    ),
                ],
              ),
            ),
            if (isSelected)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: chipColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 12,
                  color: Colors.white,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
