/// CEFR level parsing and rough guided-study time to the next sub-level.
class CefrStudyEstimate {
  final String current;
  final String next;
  final int minHours;
  final int maxHours;

  const CefrStudyEstimate({
    required this.current,
    required this.next,
    required this.minHours,
    required this.maxHours,
  });

  /// Midpoint of the guided-hour range, converted to days at [cefrGuidedStudyHoursPerDay].
  int get estimatedStudyDays {
    final avgHours = (minHours + maxHours) / 2;
    return (avgHours / cefrGuidedStudyHoursPerDay).round();
  }
}

/// Assumed average guided study per day when showing day counts.
const double cefrGuidedStudyHoursPerDay = 1.0;

const List<String> cefrLevelOrder = [
  'A1',
  'A2',
  'B1',
  'B2',
  'C1',
  'C2',
];

const Map<String, (int min, int max)> _guidedHoursToNext = {
  'A1': (100, 120),
  'A2': (150, 180),
  'B1': (180, 220),
  'B2': (200, 250),
  'C1': (220, 280),
};

String? parseCefrCode(String? level) {
  if (level == null || level.trim().isEmpty) return null;
  return RegExp(r'\b([ABC][12])\b').firstMatch(level.toUpperCase())?.group(1);
}

bool isTopCefrLevel(String? level) => parseCefrCode(level) == 'C2';

CefrStudyEstimate? estimateHoursToNextLevel(String? level) {
  final code = parseCefrCode(level);
  if (code == null || code == 'C2') return null;

  final index = cefrLevelOrder.indexOf(code);
  if (index < 0 || index >= cefrLevelOrder.length - 1) return null;

  final range = _guidedHoursToNext[code];
  if (range == null) return null;

  return CefrStudyEstimate(
    current: code,
    next: cefrLevelOrder[index + 1],
    minHours: range.$1,
    maxHours: range.$2,
  );
}

/// One-line copy for UI, e.g. "~200 days to B2".
String? daysToNextCefrLevelLine(String? level) {
  final estimate = estimateHoursToNextLevel(level);
  if (estimate == null) return null;
  return '~${estimate.estimatedStudyDays} days to ${estimate.next}';
}
