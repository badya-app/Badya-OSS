import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:Badya/utils/constants.dart';

/// Bottom sheet for assigning content to the user's learning languages.
class LanguageAssignmentSheet extends StatefulWidget {
  final List<String> availableLanguages;
  final Set<String> assignedLanguages;
  final ValueChanged<Set<String>> onSave;

  const LanguageAssignmentSheet({
    super.key,
    required this.availableLanguages,
    required this.assignedLanguages,
    required this.onSave,
  });

  /// Show the language assignment bottom sheet.
  /// Returns the updated set of assigned languages, or null if cancelled.
  static Future<Set<String>?> show({
    required BuildContext context,
    required List<String> availableLanguages,
    Set<String>? initialAssigned,
  }) {
    return showModalBottomSheet<Set<String>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => LanguageAssignmentSheet(
        availableLanguages: availableLanguages,
        assignedLanguages: initialAssigned ?? {},
        onSave: (languages) => Navigator.pop(context, languages),
      ),
    );
  }

  @override
  State<LanguageAssignmentSheet> createState() =>
      _LanguageAssignmentSheetState();
}

class _LanguageAssignmentSheetState extends State<LanguageAssignmentSheet> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.assignedLanguages);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.black.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Assign to languages',
                    style: GoogleFonts.nunito(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  if (_selected.isNotEmpty)
                    GestureDetector(
                      onTap: () => setState(() => _selected.clear()),
                      child: Text(
                        'Clear',
                        style: GoogleFonts.nunito(
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF4ECDC4),
                          fontSize: 14,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (widget.availableLanguages.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Text(
                  'No learning languages yet. Add one in Language settings.',
                  style: GoogleFonts.nunito(
                    color: isDark ? Colors.white38 : Colors.black38,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              )
            else
              ...widget.availableLanguages.map((language) {
                final isChecked = _selected.contains(language);
                final countryCode = languageCodes[language] ?? 'US';

                return InkWell(
                  onTap: () {
                    setState(() {
                      if (isChecked) {
                        _selected.remove(language);
                      } else {
                        _selected.add(language);
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 4,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isChecked
                            ? (isDark
                                ? Color(0xFF4ECDC4).withValues(alpha: 0.15)
                                : Color(0xFF4ECDC4).withValues(alpha: 0.10))
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isChecked
                              ? Color(0xFF4ECDC4).withValues(alpha: 0.5)
                              : (isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.08)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.2)
                                    : Colors.black.withValues(alpha: 0.1),
                              ),
                            ),
                            child: ClipOval(
                              child: CountryFlag.fromCountryCode(
                                countryCode,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              language,
                              style: GoogleFonts.nunito(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: isChecked
                                  ? const Color(0xFF4ECDC4)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isChecked
                                    ? const Color(0xFF4ECDC4)
                                    : (isDark
                                        ? Colors.white.withValues(alpha: 0.2)
                                        : Colors.black.withValues(alpha: 0.15)),
                                width: 2,
                              ),
                            ),
                            child: isChecked
                                ? const Icon(
                                    Icons.check_rounded,
                                    size: 16,
                                    color: Colors.black,
                                  )
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            const SizedBox(height: 8),
            // Save button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => widget.onSave(_selected),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4ECDC4),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Save',
                    style: GoogleFonts.nunito(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
