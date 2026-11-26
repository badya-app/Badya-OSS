import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:Badya/models/leaderboard_entry.dart';
import 'package:Badya/services/leaderboard_service.dart';
import 'package:Badya/utils/profile_images.dart';
import 'package:Badya/widgets/custom_app_bar.dart';

/// Leaderboard page displaying top users across 3 metrics:
/// - Overall XP
/// - Active streak days
/// - Per-language score (expanding multi-language learners)
class LeaderboardPage extends StatefulWidget {
  const LeaderboardPage({super.key});

  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage> {
  final LeaderboardService _service = LeaderboardService();

  int _selectedCategory = 0;
  List<LeaderboardEntry>? _entries;
  bool _isLoading = true;
  String? _errorMessage;

  /// Category configuration matching LeaderboardService expectations.
  static const List<({String key, String label, IconData icon})> _categories = [
    (key: 'xp', label: '', icon: Icons.emoji_events_rounded),
    (key: 'streak', label: '', icon: Icons.local_fire_department_rounded),
    (key: 'language', label: '', icon: Icons.translate_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _loadLeaderboard();
  }

  Future<void> _loadLeaderboard() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final entries =
          await _service.getTopUsers(_categories[_selectedCategory].key);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load leaderboard';
        _isLoading = false;
      });
    }
  }

  void _onCategorySelected(int index) {
    if (index == _selectedCategory) return;
    setState(() => _selectedCategory = index);
    _loadLeaderboard();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          _service.clearCache();
          await _loadLeaderboard();
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const CustomAppBar(
              title: 'Leaderboard',
              showLanguageButton: false,
              showMenuButton: false,
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: _buildCategoryChips(),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              sliver: _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Category chip row ──────────────────────────────────────────────

  Widget _buildCategoryChips() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final activeColor =
        theme.bottomNavigationBarTheme.selectedItemColor ??
        const Color(0xFFFF6B6B);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(_categories.length, (index) {
          final isSelected = _selectedCategory == index;
          final category = _categories[index];
          final inactiveColor = isDark ? Colors.white60 : Colors.black54;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => _onCategorySelected(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? activeColor.withValues(alpha: 0.15)
                      : isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? activeColor.withValues(alpha: 0.5)
                        : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      category.icon,
                      size: 25,
                      color: isSelected ? activeColor : inactiveColor,
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ─── Body content (loading / empty / error / list) ──────────────────

  Widget _buildBody() {
    if (_isLoading) {
      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildSkeletonRow(),
          childCount: 5,
        ),
      );
    }

    if (_errorMessage != null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildMessageState(
          icon: Icons.error_outline_rounded,
          message: _errorMessage!,
        ),
      );
    }

    if (_entries == null || _entries!.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildMessageState(
          icon: Icons.emoji_events_outlined,
          message: 'No leaderboard data yet.\nStart learning to rank up!',
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) => _buildEntryRow(_entries![index]),
        childCount: _entries!.length,
      ),
    );
  }

  // ─── Skeleton loading row ───────────────────────────────────────────

  Widget _buildSkeletonRow() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shimmerBase =
        isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: shimmerBase,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  // ─── Empty / error state ────────────────────────────────────────────

  Widget _buildMessageState({
    required IconData icon,
    required String message,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 64,
            color: isDark ? Colors.white24 : Colors.black26,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Leaderboard entry row ──────────────────────────────────────────

  Widget _buildEntryRow(LeaderboardEntry entry) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final activeColor =
        theme.bottomNavigationBarTheme.selectedItemColor ??
        const Color(0xFFFF6B6B);

    // Medal colours for top 3. Fills stay readable on both card backgrounds;
    // silver especially disappears on white without a deeper tone.
    Color? medalColor;
    const medalIcon = Icons.emoji_events_rounded;
    switch (entry.rank) {
      case 1:
        medalColor = isDark
            ? const Color(0xFFFFE566) // Gold
            : const Color(0xFFE0A800);
        break;
      case 2:
        medalColor = isDark
            ? const Color(0xFFE6E6E6) // Silver
            : const Color(0xFF7A7A7A);
        break;
      case 3:
        medalColor = isDark
            ? const Color(0xFFE8A15A) // Bronze
            : const Color(0xFFB86A28);
        break;
    }

    final categoryKey = _categories[_selectedCategory].key;

    // Format score badge
    String scoreText;
    switch (categoryKey) {
      case 'streak':
        scoreText = '🔥 ${entry.score} d';
        break;
      case 'language':
      case 'xp':
      default:
        scoreText = '${entry.score} XP';
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: entry.isCurrentUser
              ? activeColor.withValues(alpha: 0.1)
              : isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: entry.isCurrentUser
              ? Border.all(
                  color: activeColor.withValues(alpha: 0.4),
                  width: 1.5,
                )
              : null,
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          children: [
            // Rank badge
            SizedBox(
              width: 36,
              child: medalColor != null
                  ? _MedalCup(color: medalColor, icon: medalIcon)
                  : Center(
                      child: Text(
                        '${entry.rank}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            // Avatar
            CircleAvatar(
              radius: 20,
              backgroundImage: resolveProfileImage(entry.photoUrl),
            ),
            const SizedBox(width: 12),
            // Name + optional Language badge
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: entry.isCurrentUser
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  if (categoryKey == 'language' && entry.language != null) ...[
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.1)
                            : activeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        entry.language!,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : activeColor,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Score badge
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                scoreText,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: activeColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Trophy cup with a black outline so gold, silver, and bronze stay
/// readable on both the light card and the dark translucent row.
class _MedalCup extends StatelessWidget {
  const _MedalCup({
    required this.icon,
    required this.color,
  });

  final IconData icon;
  final Color color;

  static const double _size = 26;
  static const double _stroke = 1.4;

  static const List<Offset> _ring = [
    Offset(-_stroke, 0),
    Offset(_stroke, 0),
    Offset(0, -_stroke),
    Offset(0, _stroke),
    Offset(-_stroke, -_stroke),
    Offset(_stroke, -_stroke),
    Offset(-_stroke, _stroke),
    Offset(_stroke, _stroke),
  ];

  @override
  Widget build(BuildContext context) {
    const outline = Color(0xFF1C1C1C);

    return SizedBox(
      width: 36,
      height: 32,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (final offset in _ring)
            Transform.translate(
              offset: offset,
              child: Icon(icon, size: _size, color: outline),
            ),
          Icon(icon, size: _size, color: color),
        ],
      ),
    );
  }
}
