import 'package:Badya/widgets/balance_widget.dart';
import 'package:Badya/widgets/section_header.dart';
import 'package:Badya/widgets/custom_app_bar.dart';
import 'package:Badya/models/review_stats.dart';
import 'package:Badya/services/vocab_review_service.dart';
import 'package:Badya/services/user_preferences_service.dart';
import 'package:Badya/services/language_manager.dart';
import 'package:Badya/strange_words_page.dart';
import 'package:Badya/config/app_constants.dart';
import 'package:Badya/utils/cefr_progress.dart';
import 'package:Badya/utils/constants.dart';
import 'package:Badya/utils/level_service.dart';
import 'package:Badya/utils/score_service.dart';
import 'package:Badya/config/local_mode.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:country_flags/country_flags.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

const String _wordSmithIcon = 'assets/lessonsIcons/bookmount.png';
const String _storyWeaverIcon = 'assets/lessonsIcons/chatIcon.png';
const String _echoChamberIcon = 'assets/lessonsIcons/micmount.png';
const String _roleMasterIcon = 'assets/lessonsIcons/rolemount.png';

class LanguageProfilePage extends StatefulWidget {
  final String language;

  const LanguageProfilePage({super.key, required this.language});

  @override
  State<LanguageProfilePage> createState() => _LanguageProfilePageState();

  static Future<_LanguageProfileData> _loadLanguageProfileData(
    String language,
  ) async {
    if (LocalMode.enabled) {
      return _LanguageProfileData.empty(language);
    }
    final firestore = FirebaseFirestore.instance;
    final userId = FirebaseAuth.instance.currentUser?.uid;

    if (userId == null) {
      return _LanguageProfileData.empty(language);
    }

    final progressQuery = await firestore
        .collection('users')
        .doc(userId)
        .collection('progress')
        .where('language', isEqualTo: language)
        .get();

    // Aggregate per-lesson-type XP for this language (used in radar chart).
    final lessonTypeXp = <String, double>{};

    // Track sum and count of actual grades for the radar chart averages.
    final lessonTypeScoreSum = <String, double>{};
    final lessonTypeCount = <String, int>{};

    for (final doc in progressQuery.docs) {
      final data = doc.data();
      final lessons = Map<String, dynamic>.from(
        data['lessons'] as Map<String, dynamic>? ?? {},
      );

      // Update lesson-type XP aggregates and grade averages.
      for (final entry in lessons.entries) {
        final type = entry.key;
        final score = (entry.value as num?)?.toDouble() ?? 0;
        if (score <= 0) continue;

        lessonTypeScoreSum[type] = (lessonTypeScoreSum[type] ?? 0) + score;
        lessonTypeCount[type] = (lessonTypeCount[type] ?? 0) + 1;

        final xp = _xpForLesson(score, type);
        if (xp <= 0) continue;

        lessonTypeXp[type] = (lessonTypeXp[type] ?? 0) + xp;
      }
    }

    // Fetch the per-language XP accumulated via ScoreService.
    final totalXp = await ScoreService.getScore(language);

    double calculateAvg(String key) {
      final sum = lessonTypeScoreSum[key] ?? 0.0;
      final count = lessonTypeCount[key] ?? 0;
      if (count == 0 || sum == 0) return 0.0;
      return (sum / count).clamp(0.0, 100.0);
    }

    final averages = {
      'story_weaver': calculateAvg('story_weaver'),
      'word_smith': calculateAvg('word_smith'),
      'echo_chamber': calculateAvg('echo_chamber'),
      'role_master': calculateAvg('role_master'),
    };

    // Per-language streak from daily_activity.by_language[language].
    // Look back 60 days (UTC, matching the global streak's day bucketing) so
    // streaks survive month boundaries, and apply the same grace period as
    // ScoreService.refreshStreak(): the streak may end at today OR yesterday.
    final nowUtc = DateTime.now().toUtc();
    final todayUtc = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
    final queryStart = todayUtc.subtract(const Duration(days: 60));
    final queryEnd = todayUtc.add(const Duration(days: 1));

    final dailySnapshot = await firestore
        .collection('users')
        .doc(userId)
        .collection('daily_activity')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(queryStart))
        .where('date', isLessThan: Timestamp.fromDate(queryEnd))
        .get();

    final dailyMap = <String, int>{};
    for (final doc in dailySnapshot.docs) {
      final data = doc.data();
      final ts = data['date'] as Timestamp?;
      if (ts == null) continue;
      final date = ts.toDate().toUtc();
      final dateKey =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

      final byLang = Map<String, dynamic>.from(
        data['by_language'] as Map<String, dynamic>? ?? {},
      );
      final langData = Map<String, dynamic>.from(
        byLang[language] as Map<String, dynamic>? ?? {},
      );
      final xp = (langData['xp_earned'] as num?)?.toInt() ?? 0;

      dailyMap[dateKey] = (dailyMap[dateKey] ?? 0) + xp;
    }

    String keyFor(DateTime dateUtc) =>
        '${dateUtc.year}-${dateUtc.month.toString().padLeft(2, '0')}-${dateUtc.day.toString().padLeft(2, '0')}';

    // Grace period: streak may end at today OR yesterday.
    DateTime? start;
    for (final candidate in [
      todayUtc,
      todayUtc.subtract(const Duration(days: 1)),
    ]) {
      if ((dailyMap[keyFor(candidate)] ?? 0) >=
          AppConstants.dailyStreakXpGoal) {
        start = candidate;
        break;
      }
    }

    int streak = 0;
    var checkDate = start;
    while (checkDate != null) {
      final key = keyFor(checkDate);
      if ((dailyMap[key] ?? 0) >= AppConstants.dailyStreakXpGoal) {
        streak++;
        checkDate = checkDate.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }

    // SRS review stats for this language (Phase 6)
    final reviewStats = await VocabReviewService().getStats(language);

    // Per-language AI analysis from Firestore (profile map + progress fallback).
    final analysis = await ScoreService.getLatestFullAnalysis(userId, language);

    return _LanguageProfileData(
      language: language,
      totalXp: totalXp,
      lessonTypeAverages: averages,
      streak: streak,
      reviewStats: reviewStats,
      languageLevel: (analysis?['language_level'] as String?)?.trim(),
      performanceSummary: (analysis?['user_performance_summary'] as String?)
          ?.trim(),
    );
  }

  /// Mirror of the XP calculation used in `ScoreService._calculateXpDelta`,
  /// but without the idempotency/delta logic. This estimates how much XP a
  /// single lesson score contributes so we can compute per-lesson-type shares.
  static double _xpForLesson(double rawScore, String lessonType) {
    final score = rawScore.round();
    if (score <= 0) return 0;

    final base = score;

    double multiplier;
    switch (lessonType) {
      case 'word_smith':
        multiplier = 0.4;
        break;
      case 'story_weaver':
        multiplier = 0.75;
        break;
      case 'echo_chamber':
        multiplier = 0.7;
        break;
      case 'role_master':
        multiplier = 0.7;
        break;
      default:
        multiplier = 1.0;
    }

    return base * multiplier;
  }
}

class _LanguageProfilePageState extends State<LanguageProfilePage> {
  late Future<_LanguageProfileData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = LanguageProfilePage._loadLanguageProfileData(widget.language);
  }

  @override
  void didUpdateWidget(covariant LanguageProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.language != widget.language) {
      _dataFuture = LanguageProfilePage._loadLanguageProfileData(
        widget.language,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: FutureBuilder<_LanguageProfileData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data =
              snapshot.data ?? _LanguageProfileData.empty(widget.language);

          return CustomScrollView(
            slivers: [
              CustomAppBar(
                showMenuButton: false,
                onLanguagePressed: () => _showLanguagePicker(context),
                languageCode: languageCodes[widget.language],
                actions: const [BalanceWidget()],
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildHeader(context, data.totalXp, data.streak),
                    const SizedBox(height: 32),
                    const SectionHeader(title: 'Skill Snapshot'),
                    const SizedBox(height: 20),
                    Center(
                      child: _LessonRadarChart(
                        scores: data.lessonTypeAverages,
                        animate: true,
                      ),
                    ),
                    const SizedBox(height: 32),
                    _buildPerformanceSection(context, data),
                    const SizedBox(height: 16),
                    _buildStrangeWordsSection(context, data),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showLanguagePicker(BuildContext context) async {
    final prefs = UserPreferencesService();
    final myLangs = await prefs.getMyLanguages();
    if (myLangs.isEmpty) return;
    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalContext) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(modalContext).dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Choose language',
                style: GoogleFonts.nunito(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(modalContext).textTheme.titleLarge?.color,
                ),
              ),
              const SizedBox(height: 12),
              ...myLangs.map(
                (lang) => ListTile(
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: lang == widget.language
                          ? Theme.of(
                              context,
                            ).colorScheme.secondary.withValues(alpha: 0.1)
                          : Theme.of(
                              modalContext,
                            ).dividerColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: lang == widget.language
                            ? Theme.of(context).colorScheme.secondary
                            : Theme.of(modalContext).dividerColor,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: ClipOval(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CountryFlag.fromCountryCode(
                            languageCodes[lang] ?? 'US',
                          ),
                        ),
                      ),
                    ),
                  ),
                  title: Text(
                    lang,
                    style: GoogleFonts.nunito(fontWeight: FontWeight.w700),
                  ),
                  trailing: lang == widget.language
                      ? Icon(
                          Icons.check_rounded,
                          color: Theme.of(context).colorScheme.secondary,
                        )
                      : null,
                  onTap: () async {
                    Navigator.pop(modalContext);
                    if (lang == widget.language) return;

                    // Update global language through LanguageManager
                    final languageManager = context.read<LanguageManager>();
                    try {
                      await languageManager.updateCurrentLanguage(lang);
                    } catch (_) {
                      // Offline / network error — local state in LanguageManager
                      // is already applied, so the UI stays consistent.
                    }

                    if (context.mounted) {
                      final nav = Navigator.of(context);
                      if (nav.canPop()) {
                        // Standalone route (pushed from ProfilePage, etc.) —
                        // replace it with a new LanguageProfilePage
                        nav.pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => LanguageProfilePage(
                              language: lang,
                            ),
                          ),
                        );
                      }
                      // Inside MainShellPage's IndexedStack —
                      // LanguageManager update already triggered a rebuild.
                      // Navigating would kill the bottom nav, so we do nothing.
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, int totalXp, int streak) {
    final level = LevelService.levelForXp(totalXp);
    final xpProgress = LevelService.xpProgress(totalXp);
    final int xpForCurrent = xpProgress.xpForCurrentLevel;
    final int xpForNext = xpProgress.xpForNextLevel;
    final double progressFraction = xpForNext == xpForCurrent
        ? 1
        : ((totalXp - xpForCurrent) / (xpForNext - xpForCurrent)).clamp(0, 1);

    final secondaryColor = Theme.of(context).colorScheme.secondary;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: secondaryColor.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: secondaryColor.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: secondaryColor, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: secondaryColor.withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: CountryFlag.fromCountryCode(
                    languageCodes[widget.language] ?? 'US',
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.language,
                      style: GoogleFonts.nunito(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Theme.of(context).textTheme.titleLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Level $level',
                      style: GoogleFonts.nunito(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: secondaryColor,
                      ),
                    ),
                    if (streak > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text('🔥 ', style: GoogleFonts.nunito(fontSize: 16)),
                          Text(
                            '$streak-day streak',
                            style: GoogleFonts.nunito(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: secondaryColor.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'XP Progress',
                    style: GoogleFonts.nunito(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  Text(
                    '${totalXp - xpForCurrent} / ${xpForNext - xpForCurrent} XP',
                    style: GoogleFonts.nunito(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.color?.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: LinearProgressIndicator(
                  value: progressFraction,
                  minHeight: 10,
                  backgroundColor: Theme.of(
                    context,
                  ).dividerColor.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation(secondaryColor),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${xpProgress.xpToNextLevel} XP to Level ${level + 1}',
                style: GoogleFonts.nunito(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: 0.1);
  }

  Widget _buildPerformanceSection(
    BuildContext context,
    _LanguageProfileData profile,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = theme.colorScheme;

    final level = profile.languageLevel;
    final summary = profile.performanceSummary;
    final hasLevel = level != null && level.isNotEmpty;
    final hasSummary = summary != null && summary.isNotEmpty;
    final hasContent = hasLevel || hasSummary;

    final accent = _colorForLevel(level, colors.secondary);
    final preview = hasSummary ? _plainPreview(summary) : '';
    final cefrCode = parseCefrCode(level);
    final cefrStudyEstimate = estimateHoursToNextLevel(level);

    final insetColor = isDark
        ? colors.surfaceContainerHigh.withValues(alpha: 0.55)
        : colors.surfaceContainerLow;

    final sectionBodyColor = _performanceReportBodyColor(theme);

    return GestureDetector(
      onTap: hasContent
          ? () => _showFullPerformance(context, profile)
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: hasContent
                ? accent.withValues(alpha: isDark ? 0.35 : 0.28)
                : theme.dividerColor.withValues(alpha: 0.12),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.22 : 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Icon(
                    Icons.insights_rounded,
                    color: accent,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Performance',
                        style: GoogleFonts.nunito(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: theme.textTheme.titleLarge?.color,
                        ),
                      ),
                      if (hasContent)
                        Text(
                          'Tap for the full report',
                          style: GoogleFonts.nunito(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: theme.textTheme.bodySmall?.color
                                ?.withValues(alpha: 0.55),
                          ),
                        ),
                    ],
                  ),
                ),
                if (hasContent)
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 18,
                    color: theme.dividerColor,
                  ),
              ],
            ),

            if (!hasContent)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_outlined,
                      size: 16,
                      color: theme.textTheme.bodySmall?.color?.withValues(
                        alpha: 0.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Finish a lesson to get your level and a personal summary.',
                        style: GoogleFonts.nunito(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.textTheme.bodySmall?.color?.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            if (hasLevel) ...[
              const SizedBox(height: 16),
              if (cefrStudyEstimate != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.22 : 0.14),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: accent.withValues(alpha: isDark ? 0.45 : 0.35),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.timelapse_rounded,
                        size: 22,
                        color: accent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: GoogleFonts.nunito(
                              fontSize: 14,
                              height: 1.3,
                              fontWeight: FontWeight.w800,
                              color: sectionBodyColor,
                            ),
                            children: [
                              TextSpan(
                                text:
                                    '~${cefrStudyEstimate.estimatedStudyDays} days to ',
                              ),
                              TextSpan(
                                text: cefrStudyEstimate.next,
                                style: GoogleFonts.nunito(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  color: accent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: insetColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: theme.dividerColor.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Language level',
                      style: GoogleFonts.nunito(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                        color: theme.textTheme.bodySmall?.color
                            ?.withValues(alpha: 0.65),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (cefrCode != null)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(
                                alpha: isDark ? 0.28 : 0.14,
                              ),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: accent.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Text(
                              cefrCode,
                              style: GoogleFonts.nunito(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: accent,
                                height: 1,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              level,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.nunito(
                                fontSize: 13,
                                height: 1.4,
                                fontWeight: FontWeight.w700,
                                color: sectionBodyColor,
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        level,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.nunito(
                          fontSize: 13,
                          height: 1.4,
                          fontWeight: FontWeight.w700,
                          color: sectionBodyColor,
                        ),
                      ),
                  ],
                ),
              ),
            ],

            if (hasSummary) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: insetColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: theme.dividerColor.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Summary',
                      style: GoogleFonts.nunito(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                        color: theme.textTheme.bodySmall?.color
                            ?.withValues(alpha: 0.65),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      preview,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        height: 1.45,
                        fontWeight: FontWeight.w700,
                        color: sectionBodyColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ).animate().fadeIn().slideX(begin: 0.05),
    );
  }

  void _showFullPerformance(
    BuildContext context,
    _LanguageProfileData profile,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PerformanceSummarySheet(
        language: profile.language,
        languageLevel: profile.languageLevel,
        summary: profile.performanceSummary,
      ),
    );
  }

  Widget _buildStrangeWordsSection(
    BuildContext context,
    _LanguageProfileData profile,
  ) {
    final stats = profile.reviewStats;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryColor = Theme.of(context).colorScheme.secondary;

    return GestureDetector(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => StrangeWordsPage(language: widget.language),
          ),
        );
        // Refresh data when returning from StrangeWordsPage
        if (mounted) {
          setState(() {
            _dataFuture = LanguageProfilePage._loadLanguageProfileData(
              widget.language,
            );
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top row: icon + title + arrow ──
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: secondaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: SvgPicture.asset(
                      'assets/images/addcard.svg',
                      width: 32,
                      height: 32,
                      colorFilter: ColorFilter.mode(
                        secondaryColor,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'My Cards',
                    style: GoogleFonts.nunito(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).textTheme.titleLarge?.color,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 18,
                  color: Theme.of(context).dividerColor,
                ),
              ],
            ),

            // ── Stats row (words / due / mastered) — shown when cards exist ──
            if (stats.totalWords > 0) ...[
              const SizedBox(height: 14),
              _ReviewStatRow(
                totalWords: stats.totalWords,
                dueCount: stats.dueCount,
                recallRate: stats.recallRate,
                masteredCount: stats.masteredCount,
                isDark: isDark,
              ),
              // ── Recall Accuracy — only shown after actual reviews ──
              if (stats.totalReviews > 0) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Recall Accuracy',
                      style: GoogleFonts.nunito(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                      ),
                    ),
                    Text(
                      '${(stats.recallRate * 100).toInt()}%',
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: stats.recallRate.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: Theme.of(
                      context,
                    ).dividerColor.withValues(alpha: 0.05),
                    valueColor: AlwaysStoppedAnimation(
                      Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                ),
              ],
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.inbox_outlined,
                      size: 16,
                      color: Theme.of(
                        context,
                      ).textTheme.bodySmall?.color?.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'No cards yet — tap here to add some',
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(
                          context,
                        ).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ).animate().fadeIn().slideX(begin: 0.05),
    );
  }
}

class _LanguageProfileData {
  final String language;
  final int totalXp;
  final Map<String, double> lessonTypeAverages;
  final int streak;
  final ReviewStats reviewStats;
  final String? languageLevel;
  final String? performanceSummary;

  _LanguageProfileData({
    required this.language,
    required this.totalXp,
    required this.lessonTypeAverages,
    this.streak = 0,
    required this.reviewStats,
    this.languageLevel,
    this.performanceSummary,
  });

  factory _LanguageProfileData.empty(String language) {
    return _LanguageProfileData(
      language: language,
      totalXp: 0,
      lessonTypeAverages: const {
        'story_weaver': 0,
        'word_smith': 0,
        'echo_chamber': 0,
        'role_master': 0,
      },
      reviewStats: const ReviewStats(),
    );
  }
}

/// High-contrast body text for performance cards and the full report sheet.
/// Uses [TextTheme.bodyLarge], not [TextTheme.bodyMedium] (muted gray in app theme).
Color _performanceReportBodyColor(ThemeData theme) {
  final primary = theme.textTheme.bodyLarge?.color;
  if (primary != null) return primary;
  final isDark = theme.brightness == Brightness.dark;
  return isDark ? const Color(0xFFF5F6FA) : const Color(0xFF2D3436);
}

/// Accent color for a CEFR level string. Falls back to [fallback] when no
/// recognizable level code (A1…C2) is present.
Color _colorForLevel(String? level, Color fallback) {
  if (level == null) return fallback;
  final match = RegExp(r'\b([ABC][12])\b').firstMatch(level.toUpperCase());
  if (match == null) return fallback;
  switch (match.group(1)) {
    case 'A1':
      return const Color(0xFF27AE60);
    case 'A2':
      return const Color(0xFF2FB874);
    case 'B1':
      return const Color(0xFF2563EB);
    case 'B2':
      return const Color(0xFF7C3AED);
    case 'C1':
      return const Color(0xFFEA580C);
    case 'C2':
      return const Color(0xFFE11D48);
    default:
      return fallback;
  }
}

/// Flattens markdown into a short plain-text preview (drops headings markers,
/// bullets, emphasis markers and links) so we can show a few readable lines.
String _plainPreview(String markdown) {
  var text = markdown
      .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), ' ')
      .replaceAllMapped(
        RegExp(r'\[([^\]]*)\]\([^)]*\)'),
        (m) => m.group(1) ?? '',
      )
      .replaceAll(RegExp(r'^\s*(#{1,6}\s+|>\s*|[-*+]\s+)', multiLine: true), '')
      .replaceAll(RegExp(r'[*_`~]+'), '');

  return text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .join(' ');
}

/// Full-screen-ish bottom sheet that renders the complete AI performance
/// report as styled markdown.
class _PerformanceSummarySheet extends StatelessWidget {
  final String language;
  final String? languageLevel;
  final String? summary;

  const _PerformanceSummarySheet({
    required this.language,
    this.languageLevel,
    this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _colorForLevel(languageLevel, theme.colorScheme.secondary);

    final level = (languageLevel ?? '').trim();
    final body = (summary ?? '').trim();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.20),
                blurRadius: 24,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: Column(
            children: [
              // ── Grab handle ──
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // ── Header ──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 12, 12),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            accent.withValues(alpha: 0.9),
                            accent.withValues(alpha: 0.55),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.insights_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Performance Report',
                            style: GoogleFonts.nunito(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: theme.textTheme.titleLarge?.color,
                            ),
                          ),
                          Text(
                            '$language · latest AI analysis',
                            style: GoogleFonts.nunito(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _performanceReportBodyColor(theme)
                                  .withValues(alpha: 0.72),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        Icons.close_rounded,
                        color: theme.iconTheme.color?.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: theme.dividerColor.withValues(alpha: 0.15),
              ),
              // ── Body ──
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
                  children: [
                    if (level.isNotEmpty)
                      _MarkdownBlock(
                        icon: Icons.workspace_premium_rounded,
                        title: 'Language Level',
                        data: level,
                        accent: accent,
                      ),
                    if (level.isNotEmpty && body.isNotEmpty)
                      const SizedBox(height: 18),
                    if (body.isNotEmpty)
                      _MarkdownBlock(
                        icon: Icons.auto_awesome_rounded,
                        title: 'Performance Summary',
                        data: body,
                        accent: accent,
                      ),
                    if (level.isEmpty && body.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Center(
                          child: Text(
                            'Nothing here yet!',
                            style: GoogleFonts.nunito(
                              color: _performanceReportBodyColor(theme)
                                  .withValues(alpha: 0.75),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    if (isDark) const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One titled, colored card holding a markdown block.
class _MarkdownBlock extends StatelessWidget {
  final IconData icon;
  final String title;
  final String data;
  final Color accent;

  const _MarkdownBlock({
    required this.icon,
    required this.title,
    required this.data,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bodyColor = _performanceReportBodyColor(theme);

    final colors = theme.colorScheme;
    final insetColor = isDark
        ? colors.surfaceContainerHigh.withValues(alpha: 0.55)
        : colors.surfaceContainerLow;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: insetColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.35 : 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w900,
                    color: bodyColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(
            height: 1,
            thickness: 1,
            color: accent.withValues(alpha: isDark ? 0.28 : 0.22),
          ),
          const SizedBox(height: 12),
          DefaultTextStyle(
            style: GoogleFonts.nunito(
              fontSize: 16,
              height: 1.55,
              fontWeight: FontWeight.w800,
              color: bodyColor,
            ),
            child: MarkdownBody(
              data: data,
              selectable: true,
              styleSheet: _markdownStyleSheet(context, accent),
            ),
          ),
        ],
      ),
    );
  }
}

MarkdownStyleSheet _markdownStyleSheet(BuildContext context, Color accent) {
  final theme = Theme.of(context);
  final bodyColor = _performanceReportBodyColor(theme);
  const size = 16.0;

  TextStyle body({FontWeight weight = FontWeight.w800, double? fontSize}) {
    return GoogleFonts.nunito(
      fontSize: fontSize ?? size,
      height: 1.55,
      fontWeight: weight,
      color: bodyColor,
    );
  }

  final paragraph = body();
  final emphasis = body(weight: FontWeight.w900);

  return MarkdownStyleSheet(
    p: paragraph,
    h1: emphasis.copyWith(fontSize: 18, height: 1.35),
    h2: emphasis.copyWith(fontSize: 17, height: 1.35),
    h3: emphasis.copyWith(fontSize: 16, height: 1.4),
    h4: body(weight: FontWeight.w800, fontSize: 15),
    h5: paragraph,
    h6: paragraph,
    strong: emphasis,
    em: body(weight: FontWeight.w700).copyWith(fontStyle: FontStyle.italic),
    del: paragraph.copyWith(decoration: TextDecoration.lineThrough),
    blockquote: body(weight: FontWeight.w700),
    blockquoteDecoration: BoxDecoration(
      color: accent.withValues(alpha: 0.08),
      border: Border(left: BorderSide(color: accent, width: 3)),
    ),
    blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
    listBullet: emphasis.copyWith(fontSize: 14, height: 1.5),
    tableHead: emphasis.copyWith(fontSize: 14),
    tableBody: paragraph,
    code: GoogleFonts.jetBrainsMono(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      backgroundColor: accent.withValues(alpha: 0.12),
      color: bodyColor,
    ),
    codeblockDecoration: BoxDecoration(
      color: accent.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: accent.withValues(alpha: 0.2)),
    ),
    codeblockPadding: const EdgeInsets.all(12),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: accent.withValues(alpha: 0.25), width: 1),
      ),
    ),
    a: GoogleFonts.nunito(
      fontSize: size,
      fontWeight: FontWeight.w800,
      color: accent,
      decoration: TextDecoration.underline,
    ),
    listIndent: 20,
    blockSpacing: 8,
  );
}

/// A compact row showing SRS vocabulary review stats.
class _ReviewStatRow extends StatelessWidget {
  final int totalWords;
  final int dueCount;
  final double recallRate;
  final int masteredCount;
  final bool isDark;

  const _ReviewStatRow({
    required this.totalWords,
    required this.dueCount,
    required this.recallRate,
    required this.masteredCount,
    required this.isDark,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ReviewStatItem(
              icon: Icons.menu_book_rounded,
              value: _formatCount(totalWords),
              label: 'cards',
              color: const Color(0xFF4ECDC4),
              isDark: isDark,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _ReviewStatItem(
              icon: Icons.schedule_rounded,
              value: _formatCount(dueCount),
              label: 'due',
              color: dueCount > 0
                  ? const Color(0xFFE74C3C)
                  : const Color(0xFF27AE60),
              isDark: isDark,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _ReviewStatItem(
              icon: Icons.emoji_events_rounded,
              value: _formatCount(masteredCount),
              label: 'mastered',
              color: const Color(0xFF27AE60),
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewStatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final bool isDark;

  const _ReviewStatItem({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Text(
                value,
                style: GoogleFonts.nunito(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: GoogleFonts.nunito(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white38 : Colors.black45,
            ),
          ),
        ),
      ],
    );
  }
}

/// Formats a count for display — adds comma separators and uses compact
/// notation for large numbers (e.g. 1234 -> "1,234", 1234567 -> "1.2M").
String _formatCount(int count) {
  if (count >= 1000000) {
    final val = (count / 1000000).toStringAsFixed(1);
    return '${val}M';
  }
  if (count >= 10000) {
    final val = (count / 1000).toStringAsFixed(1);
    return '${val}K';
  }
  // Add comma separators for numbers < 10,000
  final parts = <String>[];
  var remaining = count;
  while (remaining >= 1000) {
    parts.insert(0, '${(remaining % 1000).toString().padLeft(3, '0')}');
    remaining ~/= 1000;
  }
  parts.insert(0, '$remaining');
  return parts.join(',');
}

// We will use a reliable TweenAnimationBuilder instead of relying on fl_chart's internal swaps
class _LessonRadarChart extends StatefulWidget {
  final Map<String, double> scores;
  final bool animate;

  const _LessonRadarChart({required this.scores, this.animate = true});

  @override
  State<_LessonRadarChart> createState() => _LessonRadarChartState();
}

class _LessonRadarChartState extends State<_LessonRadarChart> {
  bool _startAnimation = false;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      // Delay to allow the page route transition to finish before zooming out the radar
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) {
          setState(() {
            _startAnimation = true;
          });
        }
      });
    } else {
      _startAnimation = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    // We map out the 4 lesson types to values 0-100.
    final storyWeaverMax =
        widget.scores['story_weaver']?.clamp(0.0, 100.0) ?? 0.0;
    final wordSmithMax = widget.scores['word_smith']?.clamp(0.0, 100.0) ?? 0.0;
    final echoChamberMax =
        widget.scores['echo_chamber']?.clamp(0.0, 100.0) ?? 0.0;
    final roleMasterMax =
        widget.scores['role_master']?.clamp(0.0, 100.0) ?? 0.0;

    final primaryColor = Theme.of(context).primaryColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      height: 360,
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The Chart Itself using a highly reliable TweenAnimationBuilder
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 75.0,
                horizontal: 32.0,
              ),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  begin: 0.0,
                  end: _startAnimation ? 1.0 : 0.0,
                ),
                duration: const Duration(milliseconds: 1400),
                curve: Curves.elasticOut,
                builder: (context, value, child) {
                  return RadarChart(
                    RadarChartData(
                      dataSets: [
                        // Hidden dataset to force the outer bounds of the radar to always be 100.
                        // Without this, the chart auto-scales its grid to the animating values, making it look static!
                        RadarDataSet(
                          fillColor: Colors.transparent,
                          borderColor: Colors.transparent,
                          entryRadius: 0,
                          borderWidth: 0,
                          dataEntries: const [
                            RadarEntry(value: 100),
                            RadarEntry(value: 100),
                            RadarEntry(value: 100),
                            RadarEntry(value: 100),
                          ],
                        ),
                        // The actual animated user data
                        RadarDataSet(
                          fillColor: primaryColor.withValues(alpha: 0.25),
                          borderColor: primaryColor,
                          entryRadius: 6,
                          dataEntries: [
                            RadarEntry(value: wordSmithMax * value),
                            RadarEntry(value: storyWeaverMax * value),
                            RadarEntry(value: roleMasterMax * value),
                            RadarEntry(value: echoChamberMax * value),
                          ],
                          borderWidth: 3,
                        ),
                      ],
                      radarBackgroundColor: isDark
                          ? Colors.white.withValues(alpha: 0.02)
                          : Colors.black.withValues(alpha: 0.02),
                      borderData: FlBorderData(show: false),
                      radarBorderData: BorderSide(
                        color: Theme.of(
                          context,
                        ).dividerColor.withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                      tickCount: 4,
                      ticksTextStyle: const TextStyle(
                        color: Colors.transparent,
                        fontSize: 0,
                      ),
                      tickBorderData: BorderSide(
                        color: Theme.of(
                          context,
                        ).dividerColor.withValues(alpha: 0.2),
                        width: 1,
                      ),
                      gridBorderData: BorderSide(
                        color: Theme.of(
                          context,
                        ).dividerColor.withValues(alpha: 0.2),
                        width: 1,
                      ),
                      radarShape: RadarShape.polygon,
                      getTitle: (index, angle) {
                        return const RadarChartTitle(text: '');
                      },
                    ),
                    swapAnimationDuration: Duration
                        .zero, // Important: let Tween Builder handle this!
                  );
                },
              ),
            ),
          ),
          // Top label — centered horizontally above the chart
          Positioned(
            top: -5,
            left: 0,
            right: 0,
            height: 80,
            child: Center(
              child: _buildCustomLabel(
                context: context,
                title: 'Word Smith',
                score: wordSmithMax,
                color: Theme.of(context).colorScheme.tertiary,
              ),
            ),
          ),
          // Bottom label — centered horizontally below the chart
          Positioned(
            bottom: -5,
            left: 0,
            right: 0,
            height: 80,
            child: Center(
              child: _buildCustomLabel(
                context: context,
                title: 'Role Master',
                score: roleMasterMax,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),
          // Left label — centered vertically beside the chart
          Positioned(
            left: -15,
            top: 75,
            bottom: 75,
            width: 60,
            child: Center(
              child: _buildCustomLabel(
                context: context,
                title: 'Echo Chamber',
                score: echoChamberMax,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          // Right label — centered vertically beside the chart
          Positioned(
            right: -15,
            top: 75,
            bottom: 75,
            width: 60,
            child: Center(
              child: _buildCustomLabel(
                context: context,
                title: 'Story Weaver',
                score: storyWeaverMax,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _iconForLabel(String title) {
    switch (title) {
      case 'Word Smith':
        return _wordSmithIcon;
      case 'Story Weaver':
        return _storyWeaverIcon;
      case 'Echo Chamber':
        return _echoChamberIcon;
      case 'Role Master':
        return _roleMasterIcon;
      default:
        return _wordSmithIcon;
    }
  }

  Widget _buildCustomLabel({
    required BuildContext context,
    required String title,
    required double score,
    required Color color,
  }) {
    final iconPath = _iconForLabel(title);
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Circular background ensures all icons have the same visual footprint
        // regardless of the image's aspect ratio
        Container(
          width: 55,
          height: 55,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.2), width: 2),
          ),
          padding: const EdgeInsets.all(10),
          child: Image.asset(
            iconPath,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) =>
                Icon(Icons.school_rounded, size: 40, color: color),
          ),
        ),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Text(
            '${score.toInt()}%',
            style: GoogleFonts.nunito(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
