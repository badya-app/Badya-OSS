import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:audioplayers/audioplayers.dart';
import 'package:Badya/utils/score_service.dart';
import 'package:Badya/utils/level_service.dart';
import 'package:Badya/utils/logger.dart';
import 'package:Badya/lesson_paths_page.dart';
import 'package:Badya/widgets/coin_celebration_overlay.dart';
import 'package:Badya/services/vocab_review_service.dart';
import 'package:Badya/services/adk_service.dart';
import 'package:Badya/services/app_review_prompt_service.dart';
import 'package:Badya/config/app_constants.dart';
import 'package:Badya/config/local_mode.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LessonCompletionPage extends StatefulWidget {
  final String subjectTitle;
  final String topicId;
  final String currentLanguage;
  final int xpEarned;
  final int oldTotalXp;
  final AnalysisResult? analysisResult;
  final int topicScore;

  final bool isWordReview;

  final int? easyCount;
  final int? goodCount;
  final int? hardCount;
  final int? forgotCount;
  final int? nextReviewCount;

  final String? backToContentId;
  final String? backToContentTitle;
  final String difficulty;

  const LessonCompletionPage({
    super.key,
    required this.subjectTitle,
    required this.topicId,
    required this.currentLanguage,
    required this.xpEarned,
    required this.oldTotalXp,
    this.analysisResult,
    required this.topicScore,
    this.isWordReview = false,
    this.easyCount,
    this.goodCount,
    this.hardCount,
    this.forgotCount,
    this.nextReviewCount,
    this.backToContentId,
    this.backToContentTitle,
    this.difficulty = 'intermediate',
  });

  @override
  State<LessonCompletionPage> createState() => _LessonCompletionPageState();
}

class _LessonCompletionPageState extends State<LessonCompletionPage>
    with TickerProviderStateMixin {
  late AnimationController _xpController;
  late Animation<double> _xpAnimation;
  AnimationController? _floatController;
  bool _showLevelUp = false;
  AudioPlayer? _celebrationPlayer;

  int _calculateLevel(int xp) {
    return (math.sqrt(xp / 50.0).floor() + 1).clamp(1, 100);
  }

  int _xpForLevel(int level) {
    return 50 * (level - 1) * (level - 1);
  }

  @override
  void initState() {
    super.initState();
    final int oldLevel = _calculateLevel(widget.oldTotalXp);
    final int newLevel = _calculateLevel(widget.oldTotalXp + widget.xpEarned);

    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    _xpController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _xpAnimation =
        Tween<double>(
          begin: widget.oldTotalXp.toDouble(),
          end: (widget.oldTotalXp + widget.xpEarned).toDouble(),
        ).animate(
          CurvedAnimation(parent: _xpController, curve: Curves.easeOutCubic),
        );

    _xpController.forward().then((_) {
      if (newLevel > oldLevel) {
        setState(() {
          _showLevelUp = true;
        });
        // Show coin celebration for level-up reward
        final coinsAwarded = LevelService.coinsForLevelRange(oldLevel, newLevel);
        if (coinsAwarded > 0 && mounted) {
          CoinCelebrationOverlay.show(
            context,
            coinsAwarded: coinsAwarded,
            description: 'Level-Up Reward!',
          );
        }
      }
    });

    _celebrationPlayer = AudioPlayer();
    Future.delayed(const Duration(milliseconds: 500), () {
      _celebrationPlayer?.play(AssetSource('sounds/celebration.wav'));
    });

    final newTotalXp = widget.oldTotalXp + widget.xpEarned;
    if (AppConstants.crossedReviewPromptThreshold(
      widget.oldTotalXp,
      newTotalXp,
    )) {
      Future.delayed(AppConstants.reviewPromptDelay, () {
        if (!mounted) return;
        AppReviewPromptService.instance.maybeShow(
          context,
          thresholdCrossedOnThisScreen: true,
        );
      });
    }
  }

  @override
  void dispose() {
    _floatController?.dispose();
    _xpController.dispose();
    _celebrationPlayer?.dispose();
    super.dispose();
  }

  bool get _hasAnalysisData {
    final a = widget.analysisResult;
    if (a == null) return false;
    return a.understandingPercentage > 0 ||
        a.expressionPercentage > 0 ||
        a.communicationPercentage > 0 ||
        a.languageLevel.isNotEmpty;
  }

  bool get _hasSrsRatings =>
      (widget.easyCount ?? 0) +
          (widget.goodCount ?? 0) +
          (widget.hardCount ?? 0) +
          (widget.forgotCount ?? 0) >
      0;

  void _initFloatController() {
    _floatController ??= AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  Widget build(BuildContext context) {
    _initFloatController();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final feedbackText = widget.analysisResult != null
        ? (widget.analysisResult!.feedback.isNotEmpty
              ? widget.analysisResult!.feedback
              : widget.analysisResult!.userPerformanceSummary)
        : 'Your lesson has been recorded. Great effort!';

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 160),
            child: Column(
              children: [
                Text(
                  widget.isWordReview
                      ? 'Review Complete!'
                      : 'Lesson Completed!',
                  style: GoogleFonts.manrope(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ).animate().fade().slideY(begin: -0.2),

                const SizedBox(height: 24),

                _buildScoreSection(),
                const SizedBox(height: 16),

                _buildXpCard(),

                const SizedBox(height: 16),

                if (_showLevelUp) ...[
                  _buildLevelUpBanner(),
                  const SizedBox(height: 16),
                ],

                if (_hasAnalysisData) ...[
                  _buildPerformanceCard(),
                  const SizedBox(height: 16),
                ],

                if (_hasSrsRatings) ...[
                  _buildSrsCard(),
                  const SizedBox(height: 16),
                ],

                if (widget.analysisResult != null && feedbackText.isNotEmpty)
                  _buildFeedbackCard(feedbackText),

                if (widget.backToContentId != null) ...[
                  const SizedBox(height: 16),
                  _buildBackToContentButton(),
                ],
              ],
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    theme.scaffoldBackgroundColor.withValues(alpha: 0),
                    theme.scaffoldBackgroundColor.withValues(alpha: 0.9),
                    theme.scaffoldBackgroundColor,
                  ],
                ),
              ),
              child: Center(
                child: SizedBox(width: 452, child: _buildContinueButton()),
              ),
            ).animate().fade(delay: 800.ms).slideY(begin: 0.2, delay: 800.ms),
          ),
        ],
      ),
    );
  }

  // ── Score Section ──

  Widget _buildScoreSection() {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        SizedBox(
          height: 224,
          child: AnimatedBuilder(
            animation: _floatController!,
            builder: (context, child) {
              final floatOffset =
                  -10 * math.sin(_floatController!.value * math.pi);
              return Transform.translate(
                offset: Offset(0, floatOffset),
                child: child,
              );
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.primary.withValues(alpha: 0.05),
                    boxShadow: [
                      BoxShadow(
                        color: colors.primary.withValues(alpha: 0.05),
                        blurRadius: 64,
                        spreadRadius: 16,
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.surface,
                    border: Border.all(
                      color: colors.surfaceContainerHigh,
                      width: 4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colors.primary.withValues(alpha: 0.15),
                        blurRadius: 40,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${widget.topicScore}',
                        style: GoogleFonts.manrope(
                          fontSize: 48,
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                          color: colors.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'SCORE',
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.7,
                          color: colors.outline,
                        ),
                      ),
                    ],
                  ),
                ).animate().scale(
                  delay: 200.ms,
                  curve: Curves.elasticOut,
                  duration: 800.ms,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── XP Card ──

  Widget _buildXpCard() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.3)
                : Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              AnimatedBuilder(
                animation: _xpAnimation,
                builder: (context, child) {
                  final level = _calculateLevel(_xpAnimation.value.toInt());
                  return Text(
                    'Level $level',
                    style: GoogleFonts.manrope(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: colors.primary,
                    ),
                  );
                },
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colors.tertiaryContainer,
                  borderRadius: BorderRadius.circular(9999),
                ),
                child: Text(
                  '+${widget.xpEarned} XP',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colors.onTertiaryContainer,
                  ),
                ).animate().shake(delay: 1.seconds),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(9999),
            child: Stack(
              children: [
                Container(
                  height: 16,
                  width: double.infinity,
                  color: colors.surfaceContainerHighest,
                ),
                AnimatedBuilder(
                  animation: _xpAnimation,
                  builder: (context, child) {
                    final currentXp = _xpAnimation.value.toInt();
                    final level = _calculateLevel(currentXp);
                    final startXp = _xpForLevel(level);
                    final endXp = _xpForLevel(level + 1);
                    final progress = ((currentXp - startXp) / (endXp - startXp))
                        .clamp(0.0, 1.0);
                    return FractionallySizedBox(
                      widthFactor: progress,
                      alignment: Alignment.centerLeft,
                      child: Container(
                        height: 16,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              colors.primary.withValues(alpha: 0.6),
                              colors.primary,
                            ],
                          ),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(9999),
                            bottomLeft: Radius.circular(9999),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: AnimatedBuilder(
              animation: _xpAnimation,
              builder: (context, child) {
                final currentXp = _xpAnimation.value.toInt();
                final level = _calculateLevel(currentXp);
                final endXp = _xpForLevel(level + 1);
                return Text(
                  '$currentXp / $endXp XP',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ).animate().slideY(begin: 0.1, delay: 400.ms).fade(delay: 400.ms);
  }

  // ── Level Up Banner ──

  Widget _buildLevelUpBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.stars, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            'LEVEL UP!',
            style: GoogleFonts.manrope(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    ).animate().scale().shake().shimmer(duration: 2.seconds);
  }

  // ── Performance Breakdown Card ──

  Widget _buildPerformanceCard() {
    final colors = Theme.of(context).colorScheme;
    final a = widget.analysisResult!;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        boxShadow: _cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics_rounded, color: colors.primary, size: 22),
              const SizedBox(width: 8),
              Text(
                'Performance Breakdown',
                style: GoogleFonts.manrope(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildMetricBar(
            'Understanding',
            a.understandingPercentage,
            colors.secondary,
          ),
          const SizedBox(height: 16),
          _buildMetricBar('Expression', a.expressionPercentage, colors.primary),
          const SizedBox(height: 16),
          _buildMetricBar(
            'Communication',
            a.communicationPercentage,
            colors.tertiary,
          ),
        ],
      ),
    ).animate().fade(delay: 500.ms).slideY(begin: 0.05, delay: 500.ms);
  }

  Widget _buildMetricBar(String label, int value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              '$value%',
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(9999),
          child: Container(
            height: 12,
            width: double.infinity,
            color: color.withValues(alpha: 0.15),
            child: FractionallySizedBox(
              widthFactor: value.clamp(0, 100) / 100.0,
              alignment: Alignment.centerLeft,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(9999),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── SRS Breakdown Card ──

  Widget _buildSrsCard() {
    final colors = Theme.of(context).colorScheme;
    final total =
        (widget.easyCount ?? 0) +
        (widget.goodCount ?? 0) +
        (widget.hardCount ?? 0) +
        (widget.forgotCount ?? 0);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        boxShadow: _cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.assessment_rounded, color: colors.primary, size: 22),
              const SizedBox(width: 8),
              Text(
                'Word Ratings',
                style: GoogleFonts.manrope(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            total == 1 ? '1 word reviewed' : '$total words reviewed',
            style: GoogleFonts.manrope(
              fontSize: 14,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _SrsBadge(
                emoji: '🟢',
                label: 'Easy',
                count: widget.easyCount ?? 0,
                color: const Color(0xFF27AE60),
              ),
              const SizedBox(width: 8),
              _SrsBadge(
                emoji: '🔵',
                label: 'Good',
                count: widget.goodCount ?? 0,
                color: const Color(0xFF3498DB),
              ),
              const SizedBox(width: 8),
              _SrsBadge(
                emoji: '🟠',
                label: 'Hard',
                count: widget.hardCount ?? 0,
                color: const Color(0xFFF39C12),
              ),
              const SizedBox(width: 8),
              _SrsBadge(
                emoji: '🔴',
                label: 'Forgot',
                count: widget.forgotCount ?? 0,
                color: const Color(0xFFE74C3C),
              ),
            ],
          ),
          if (widget.nextReviewCount != null) ...[
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: colors.secondary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colors.secondary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    size: 22,
                    color: colors.secondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.nextReviewCount == 0
                          ? 'All caught up! No words due for review.'
                          : '${widget.nextReviewCount} word${widget.nextReviewCount == 1 ? '' : 's'} due for your next review.',
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ).animate().fade(delay: 550.ms).slideY(begin: 0.05, delay: 550.ms);
  }

  // ── Tutor Feedback Card ──

  Widget _buildFeedbackCard(String feedbackText) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: (isDark ? Colors.black : Colors.white).withValues(
              alpha: 0.4,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.surfaceContainerHighest),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    color: colors.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Tutor Feedback',
                    style: GoogleFonts.manrope(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                feedbackText,
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  height: 1.5,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fade(delay: 600.ms).slideX(begin: 0.05, delay: 600.ms);
  }

  // ── Navigate to Lesson Paths ──

  Future<void> _navigateToLessonPaths(BuildContext context) async {
    final uid = LocalMode.enabled
        ? LocalMode.guestUid
        : (FirebaseAuth.instance.currentUser?.uid ?? 'default_user');

    // Ensure words exist — load or generate via ADK
    final vocabService = VocabReviewService();
    final scopeId = VocabReviewService.topicScopeId(
      widget.topicId,
      widget.currentLanguage,
    );
    var words = await vocabService.getAllWords(
      scope: VocabReviewService.scopeTopic,
      scopeId: scopeId,
    );

    if (words.isEmpty) {
      try {
        await AdkService().generateAndCacheWords(
          topicId: widget.topicId,
          subject: widget.subjectTitle,
          description: '',
          language: widget.currentLanguage,
          difficulty: widget.difficulty,
          userId: uid,
        );

        words = await vocabService.getAllWords(
          scope: VocabReviewService.scopeTopic,
          scopeId: scopeId,
        );
      } catch (e) {
        Logger.warn('Failed to generate words for lesson paths: $e');
      }
    }

    final bool isImportedContent = widget.backToContentId != null;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => LessonPathsPage(
          subjectTitle: widget.subjectTitle,
          description: '',
          topicId: widget.topicId,
          currentLanguage: widget.currentLanguage,
          difficulty: widget.difficulty,
          isImportedContent: isImportedContent,
          importedContentId: widget.backToContentId,
        ),
      ),
      (route) => route.isFirst,
    );
  }

  // ── Continue Button ──

  Widget _buildContinueButton() {
    final colors = Theme.of(context).colorScheme;

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: () {
          if (widget.isWordReview) {
            Navigator.pop(context);
          } else {
            _navigateToLessonPaths(context);
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 8,
          shadowColor: colors.primary.withValues(alpha: 0.4),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              widget.isWordReview ? 'BACK TO WORDS' : 'CONTINUE',
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward, size: 20),
          ],
        ),
      ),
    );
  }

  // ── Back to Content Button ──

  Widget _buildBackToContentButton() {
    final colors = Theme.of(context).colorScheme;

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.arrow_back_rounded, size: 20),
        label: Text(
          'Back to ${widget.backToContentTitle ?? 'Content'}',
          style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        onPressed: () {
          Navigator.popUntil(context, (route) {
            return route.settings.name == 'ImportCoursePage' || route.isFirst;
          });
        },
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: BorderSide(color: colors.primary.withValues(alpha: 0.5)),
        ),
      ),
    ).animate().fade(delay: 900.ms).slideY(begin: 0.15, delay: 900.ms);
  }

  List<BoxShadow> _cardShadow(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return [
      BoxShadow(
        color: isDark
            ? Colors.black.withValues(alpha: 0.3)
            : Colors.black.withValues(alpha: 0.08),
        blurRadius: 20,
        offset: const Offset(0, 4),
      ),
    ];
  }
}

class _SrsBadge extends StatelessWidget {
  final String emoji;
  final String label;
  final int count;
  final Color color;

  const _SrsBadge({
    required this.emoji,
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 4),
            Text(
              '$count',
              style: GoogleFonts.manrope(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
