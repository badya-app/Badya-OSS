import 'package:flutter/material.dart';
import 'package:Badya/utils/level_service.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

class LevelPathPage extends StatelessWidget {
  final int totalXp;

  const LevelPathPage({super.key, required this.totalXp});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final xpProgress = LevelService.xpProgress(totalXp);
    final int xpForCurrent = xpProgress.xpForCurrentLevel;
    final int xpForNext = xpProgress.xpForNextLevel;
    final int xpToNext = xpProgress.xpToNextLevel;
    final int currentLevel = LevelService.levelForXp(totalXp);

    final double progressFraction = xpForNext == xpForCurrent
        ? 1
        : ((totalXp - xpForCurrent) / (xpForNext - xpForCurrent)).clamp(0, 1);

    // Precompute a set of milestones around the user.
    final List<_LevelMilestone> milestones = List.generate(20, (index) {
      final level = index + 1;
      final xp = LevelService.xpForLevel(level);
      return _LevelMilestone(level: level, totalXpRequired: xp);
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Level Path')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeaderCard(
              context,
              currentLevel: currentLevel,
              totalXp: totalXp,
              xpToNext: xpToNext,
              progressFraction: progressFraction,
            ),
            const SizedBox(height: 24),
            Text(
              'Your Journey',
              style: GoogleFonts.nunito(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: theme.textTheme.titleLarge?.color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'See how far you\'ve come and what\'s ahead.',
              style: GoogleFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: theme.textTheme.bodyMedium?.color,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: milestones.length,
                itemBuilder: (context, index) {
                  final milestone = milestones[index];
                  final isCurrent = milestone.level == currentLevel;
                  final isCompleted = milestone.level < currentLevel;
                  final isFuture = milestone.level > currentLevel;

                  final remainingXp = milestone.totalXpRequired - totalXp;
                  final xpRemaining = remainingXp > 0 ? remainingXp : 0;
                  final coinsReward = LevelService.coinsForLevel(
                    milestone.level,
                  );

                  // Nice loading-style effect using flutter_animate:
                  // each tile fades and slides in when it first enters view,
                  // with a slight stagger based on its index.
                  return _LevelMilestoneTile(
                        milestone: milestone,
                        isCurrent: isCurrent,
                        isCompleted: isCompleted,
                        isFuture: isFuture,
                        currentXp: totalXp,
                        xpRemaining: xpRemaining,
                        coinsReward: coinsReward,
                      )
                      .animate()
                      .fadeIn(
                        delay: (80 * index).ms,
                        duration: 350.ms,
                        curve: Curves.easeOutCubic,
                      )
                      .slideY(
                        begin: 0.15,
                        end: 0,
                        duration: 400.ms,
                        curve: Curves.easeOutBack,
                      );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(
    BuildContext context, {
    required int currentLevel,
    required int totalXp,
    required int xpToNext,
    required double progressFraction,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: theme.cardTheme.color,
        boxShadow: [
          BoxShadow(
            color: Color(0xFF4ECDC4).withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(
          color: Color(0xFF4ECDC4).withValues(alpha: 0.6),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF4ECDC4), Color(0xFF45B7AF)],
                  ),
                ),
                child: Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutBack,
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: 0.9 + 0.1 * value,
                        child: child,
                      );
                    },
                    child: Text(
                      '$currentLevel',
                      style: GoogleFonts.nunito(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current Level',
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: theme.textTheme.bodyMedium?.color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Level $currentLevel',
                      style: GoogleFonts.nunito(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: theme.textTheme.titleLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$totalXp XP total',
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.textTheme.bodyMedium?.color?.withValues(
                          alpha: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progressFraction),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 10,
                  backgroundColor: theme.dividerColor.withValues(alpha: 0.2),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFFFF6B6B)),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'On your way to the next level!',
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.textTheme.bodyMedium?.color,
                ),
              ),
              Text(
                '$xpToNext XP left',
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFFF6B6B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LevelMilestone {
  final int level;
  final int totalXpRequired;

  const _LevelMilestone({required this.level, required this.totalXpRequired});
}

class _LevelMilestoneTile extends StatelessWidget {
  final _LevelMilestone milestone;
  final bool isCurrent;
  final bool isCompleted;
  final bool isFuture;
  final int currentXp;
  final int xpRemaining;
  final int coinsReward;

  const _LevelMilestoneTile({
    required this.milestone,
    required this.isCurrent,
    required this.isCompleted,
    required this.isFuture,
    required this.currentXp,
    required this.xpRemaining,
    required this.coinsReward,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color bgColor = theme.cardTheme.color ?? theme.cardColor;
    Color borderColor = theme.dividerColor;
    IconData icon;

    if (isCurrent) {
      bgColor = Color(0xFF4ECDC4).withValues(alpha: 0.12);
      borderColor = const Color(0xFF4ECDC4);
      icon = Icons.radio_button_checked_rounded;
    } else if (isCompleted) {
      bgColor = (theme.cardTheme.color ?? theme.cardColor);
      borderColor = Color(0xFF4ECDC4).withValues(alpha: 0.4);
      icon = Icons.check_circle_rounded;
    } else {
      bgColor = (theme.cardTheme.color ?? theme.cardColor);
      borderColor = theme.dividerColor.withValues(alpha: 0.4);
      icon = Icons.radio_button_unchecked_rounded;
    }

    final bool hasReachedXp = currentXp >= milestone.totalXpRequired;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: isCurrent ? 2 : 1.4),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 22,
            color: isCurrent
                ? const Color(0xFF4ECDC4)
                : (isCompleted
                      ? const Color(0xFF4ECDC4)
                      : theme.iconTheme.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Level ${milestone.level}',
                      style: GoogleFonts.nunito(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: theme.textTheme.bodyLarge?.color,
                      ),
                    ),
                    if (isCurrent)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Color(
                              0xFFFFD93D,
                            ).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Current',
                            style: GoogleFonts.nunito(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFFFFA000),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${milestone.totalXpRequired} XP total required',
                  style: GoogleFonts.nunito(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.textTheme.bodyMedium?.color?.withValues(
                      alpha: 0.9,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                if (isFuture)
                  Text(
                    '$xpRemaining XP remaining to reach this level',
                    style: GoogleFonts.nunito(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFFF6B6B),
                    ),
                  )
                else if (isCompleted)
                  Text(
                    'Level reached!',
                    style: GoogleFonts.nunito(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF4ECDC4),
                    ),
                  )
                else
                  const SizedBox.shrink(),
                const SizedBox(height: 2),
                Text(
                  'Reward: $coinsReward coins',
                  style: GoogleFonts.nunito(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.textTheme.bodyMedium?.color?.withValues(
                      alpha: 0.9,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (hasReachedXp)
            Icon(Icons.star_rounded, color: const Color(0xFFFFD93D), size: 22),
        ],
      ),
    );
  }
}
