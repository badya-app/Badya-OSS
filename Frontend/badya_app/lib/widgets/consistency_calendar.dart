import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';

class ConsistencyCalendar extends StatefulWidget {
  /// Real activity days (day-of-month ints) for the displayed month, fetched
  /// from the user's `daily_activity` collection. These are the days the user
  /// actually earned the daily XP goal.
  final Set<int> activeDays;

  /// Called when the user navigates to a different month. The parent can
  /// re-fetch activity data for the new [year] / [month] and rebuild with
  /// fresh [activeDays].
  final ValueChanged<DateTime>? onMonthChanged;

  /// Months in which the user has at least one qualifying activity day.
  /// When provided, the left/right arrows are disabled at the boundaries
  /// (earliest available month on the left, current month on the right).
  final Set<DateTime>? availableMonths;

  const ConsistencyCalendar({
    super.key,
    this.activeDays = const <int>{},
    this.onMonthChanged,
    this.availableMonths,
  });

  @override
  State<ConsistencyCalendar> createState() => _ConsistencyCalendarState();
}

class _ConsistencyCalendarState extends State<ConsistencyCalendar> {
  late DateTime _focusedDay = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    final daysInMonth = DateUtils.getDaysInMonth(
      _focusedDay.year,
      _focusedDay.month,
    );
    final firstDayOfMonth = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final int firstWeekday = firstDayOfMonth.weekday; // 1 = Mon, 7 = Sun

    final now = DateTime.now();
    final isCurrentMonth = _focusedDay.year == now.year && _focusedDay.month == now.month;

    // Design Colors
    final secondaryTurquoise = const Color(0xFF4ECDC4);
    
    final hairlineColor = isDark ? const Color(0x22FFFFFF) : const Color(0x1A2D3436);
    final slotBg = isDark ? const Color(0xFF2A2A28) : const Color(0xFFF5F4F0);
    final inkDeep = isDark ? const Color(0xFFF5F6FA) : const Color(0xFF2A2A28);
    final inkMuted = isDark ? const Color(0xFFB2BEC3) : const Color(0xFF636E72);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: hairlineColor,
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.03),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildNavArrow(
                icon: Icons.chevron_left_rounded,
                onTap: _canGoBack ? () => _changeMonth(-1) : null,
                inkDeep: inkDeep,
              ),
              Text(
                DateFormat('MMMM yyyy').format(_focusedDay),
                style: GoogleFonts.playfairDisplay(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: inkDeep,
                ),
              ),
              _buildNavArrow(
                icon: Icons.chevron_right_rounded,
                onTap: _canGoForward ? () => _changeMonth(1) : null,
                inkDeep: inkDeep,
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Days of Week Labels
          Row(
            children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                .map(
                  (day) => Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                          color: inkMuted.withValues(alpha: 0.6),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          Divider(color: hairlineColor, height: 1, thickness: 1),
          const SizedBox(height: 8),
          
          // Calendar Grid
          GridView.builder(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: ((firstWeekday - 1 + daysInMonth) / 7).ceil() * 7, // Dynamically calculate only needed rows
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.0,
            ),
            itemBuilder: (context, index) {
              final int dayOffset = index - (firstWeekday - 1);
              final int day = dayOffset + 1;

              if (day < 1 || day > daysInMonth) {
                return const SizedBox();
              }

              final bool isActive = widget.activeDays.contains(day);
              final bool isToday = isCurrentMonth && day == now.day;

              if (isActive) {
                return _buildSoftActiveDay(
                  day: day,
                  isToday: isToday,
                  secondaryTurquoise: secondaryTurquoise,
                );
              }

              return Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: isToday
                        ? secondaryTurquoise.withValues(alpha: 0.12)
                        : slotBg,
                    border: isToday
                        ? Border.all(color: secondaryTurquoise, width: 1.5)
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      '$day',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isToday ? secondaryTurquoise : inkDeep,
                      ),
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: (day * 10).ms).scale(begin: const Offset(0.9, 0.9), curve: Curves.easeOutBack);
            },
          ),
        ],
      ),
    );
  }

  bool get _canGoBack {
    if (widget.availableMonths == null || widget.availableMonths!.isEmpty) {
      return true; // no data yet — allow navigation
    }
    final earliest = widget.availableMonths!
        .reduce((a, b) => a.isBefore(b) ? a : b);
    return DateTime(_focusedDay.year, _focusedDay.month)
        .isAfter(earliest);
  }

  bool get _canGoForward {
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    return DateTime(_focusedDay.year, _focusedDay.month).isBefore(currentMonth);
  }

  void _changeMonth(int delta) {
    setState(() {
      _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + delta, 1);
    });
    widget.onMonthChanged?.call(_focusedDay);
  }

  Widget _buildNavArrow({
    required IconData icon,
    required VoidCallback? onTap,
    required Color inkDeep,
  }) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.25,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: inkDeep.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 24, color: inkDeep),
        ),
      ),
    );
  }

  /// Builds a subdued highlight for an active (worked) day that is not part
  /// of the current streak — shows real monthly activity without glowing.
  Widget _buildSoftActiveDay({
    required int day,
    required bool isToday,
    required Color secondaryTurquoise,
  }) {
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: LinearGradient(
            colors: [
              secondaryTurquoise.withValues(alpha: 0.35),
              secondaryTurquoise.withValues(alpha: 0.15),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: isToday
                ? secondaryTurquoise
                : secondaryTurquoise.withValues(alpha: 0.45),
            width: isToday ? 1.5 : 1,
          ),
        ),
        child: Center(
          child: Text(
            '$day',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: secondaryTurquoise,
            ),
          ),
        ),
      ),
    );
  }

}

