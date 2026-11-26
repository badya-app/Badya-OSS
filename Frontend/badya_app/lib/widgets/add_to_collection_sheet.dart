import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:google_fonts/google_fonts.dart';
import 'package:country_flags/country_flags.dart';
import 'package:Badya/config/content_types.dart';
import 'package:Badya/models/user_content.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:Badya/services/language_manager.dart';
import 'package:Badya/utils/ui_utils.dart';
import 'package:Badya/utils/constants.dart';

/// Result returned when the user confirms adding content to their collection.
class AddToCollectionResult {
  final List<String> assignedLanguages;
  final List<String> additionalTags;
  final String difficulty;

  const AddToCollectionResult({
    required this.assignedLanguages,
    this.additionalTags = const [],
    this.difficulty = 'intermediate',
  });
}

/// Bottom sheet shown when tapping unowned content in the Library.
///
/// Lets the user:
/// 1. Preview the content (title, description, tags)
/// 2. Select which languages to assign (multi-select)
/// 3. Optionally add extra tags
/// 4. Confirm add — returns [AddToCollectionResult] with merged languages
class AddToCollectionSheet extends StatefulWidget {
  final UserContent content;
  final List<String> availableLanguages;
  /// Languages the content is already assigned to in the user's fork.
  /// These will be shown as inactive (not selectable) in the picker.
  final List<String> preAssignedLanguages;

  const AddToCollectionSheet({
    super.key,
    required this.content,
    required this.availableLanguages,
    this.preAssignedLanguages = const [],
  });

  /// Show the bottom sheet and return [AddToCollectionResult] or null if cancelled.
  static Future<AddToCollectionResult?> show({
    required BuildContext context,
    required UserContent content,
    required List<String> availableLanguages,
    List<String> preAssignedLanguages = const [],
  }) {
    return showModalBottomSheet<AddToCollectionResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => AddToCollectionSheet(
        content: content,
        availableLanguages: availableLanguages,
        preAssignedLanguages: preAssignedLanguages,
      ),
    );
  }

  @override
  State<AddToCollectionSheet> createState() => _AddToCollectionSheetState();
}

class _AddToCollectionSheetState extends State<AddToCollectionSheet> {
  late Set<String> _selectedLanguages;
  late List<String> _visibleLanguages;
  late TextEditingController _tagController;
  late List<String> _additionalTags;
  String _selectedDifficulty = 'intermediate';
  bool _isAdding = false;

  @override
  void initState() {
    super.initState();
    // Show all available languages — pre-assigned ones appear inactive
    _visibleLanguages = List.from(widget.availableLanguages);
    // Pre-select the user's current language (from LanguageManager) by default,
    // so they don't have to choose it every time — but they can still change it.
    final languageManager = _lookupLanguageManager();
    final defaultLanguage = languageManager?.currentLanguage;
    _selectedLanguages = <String>{};
    if (defaultLanguage != null &&
        _visibleLanguages.contains(defaultLanguage) &&
        !widget.preAssignedLanguages.contains(defaultLanguage)) {
      _selectedLanguages.add(defaultLanguage);
    }
    _tagController = TextEditingController();
    _additionalTags = [];
  }

  /// Locates the [LanguageManager] from the nearest [BuildContext].
  /// Returns null if the sheet is used outside a provider tree (e.g. tests).
  LanguageManager? _lookupLanguageManager() {
    try {
      return context.read<LanguageManager>();
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  void _addTag() {
    final tag = _tagController.text.trim();
    if (tag.isEmpty || _additionalTags.contains(tag)) return;
    setState(() {
      _additionalTags.add(tag);
      _tagController.clear();
    });
  }

  void _removeTag(String tag) {
    setState(() => _additionalTags.remove(tag));
  }

  Future<void> _onConfirm() async {
    if (_selectedLanguages.isEmpty) {
      UiUtils.showTopNotification(context, 'Please assign at least one language', type: NotificationType.info);
      return;
    }
    setState(() => _isAdding = true);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) {
        Navigator.pop(context);
      }
      return;
    }

    // Merge pre-assigned + newly selected languages
    final mergedLanguages = [
      ...widget.preAssignedLanguages,
      ..._selectedLanguages,
    ];

    if (mounted) {
      Navigator.pop(
        context,
        AddToCollectionResult(
          assignedLanguages: mergedLanguages,
          additionalTags: List.from(_additionalTags),
          difficulty: _selectedDifficulty,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
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

            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
              child: Text(
                'Add to your collection',
                style: GoogleFonts.nunito(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),

            // Scrollable content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ─── Content Preview ─────────────────────────────
                    _buildContentPreview(isDark),
                    const SizedBox(height: 16),

                    // ─── Language assignment ─────────────────────────
                    _buildSectionLabel('Assign to languages'),
                    const SizedBox(height: 6),
                    if (_visibleLanguages.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No learning languages yet. Add one in Language settings.',
                          style: GoogleFonts.nunito(
                            color: isDark ? Colors.white38 : Colors.black38,
                            fontSize: 13,
                          ),
                        ),
                      )
                    else
                      ..._visibleLanguages.map((lang) {
                        final isPreAssigned = widget.preAssignedLanguages.contains(lang);
                        final isChecked = _selectedLanguages.contains(lang);
                        final countryCode = languageCodes[lang] ?? 'US';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: InkWell(
                            onTap: isPreAssigned
                                ? null
                                : () {
                                    setState(() {
                                      if (isChecked) {
                                        _selectedLanguages.remove(lang);
                                      } else {
                                        _selectedLanguages.add(lang);
                                      }
                                    });
                                  },
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedOpacity(
                              opacity: isPreAssigned ? 0.45 : 1.0,
                              duration: const Duration(milliseconds: 200),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: isPreAssigned
                                      ? (isDark
                                          ? Colors.white.withValues(alpha: 0.03)
                                          : Colors.black.withValues(alpha: 0.02))
                                      : (isChecked
                                          ? (isDark
                                              ? const Color(0xFF4ECDC4).withValues(alpha: 0.15)
                                              : const Color(0xFF4ECDC4).withValues(alpha: 0.10))
                                          : Colors.transparent),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isPreAssigned
                                        ? (isDark
                                            ? Colors.white.withValues(alpha: 0.06)
                                            : Colors.black.withValues(alpha: 0.06))
                                        : (isChecked
                                            ? const Color(0xFF4ECDC4).withValues(alpha: 0.5)
                                            : (isDark
                                                ? Colors.white.withValues(alpha: 0.08)
                                                : Colors.black.withValues(alpha: 0.08))),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    // Flag
                                    Opacity(
                                      opacity: isPreAssigned ? 0.5 : 1.0,
                                      child: Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: isDark
                                                ? Colors.white.withValues(alpha: isPreAssigned ? 0.1 : 0.2)
                                                : Colors.black.withValues(alpha: isPreAssigned ? 0.05 : 0.1),
                                          ),
                                        ),
                                        child: ClipOval(
                                          child: CountryFlag.fromCountryCode(countryCode),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        lang,
                                        style: GoogleFonts.nunito(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: isPreAssigned
                                              ? (isDark ? Colors.white38 : Colors.black38)
                                              : (isDark ? Colors.white : Colors.black87),
                                        ),
                                      ),
                                    ),
                                    // Status indicator
                                    if (isPreAssigned)
                                      Text(
                                        'Added',
                                        style: GoogleFonts.nunito(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? Colors.white38 : Colors.black38,
                                        ),
                                      )
                                    else
                                      Container(
                                        width: 22,
                                        height: 22,
                                        decoration: BoxDecoration(
                                          color: isChecked
                                              ? const Color(0xFF4ECDC4)
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(5),
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
                                                size: 14,
                                                color: Colors.black,
                                              )
                                            : null,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),

                    const SizedBox(height: 12),

                    // ─── Difficulty selector ─────────────────────────
                    _buildSectionLabel('Difficulty level'),
                    const SizedBox(height: 6),
                    _buildDifficultySelector(isDark),

                    const SizedBox(height: 12),

                    // ─── Additional Tags ─────────────────────────────
                    _buildSectionLabel('Additional tags (optional)'),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : Colors.black.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.black.withValues(alpha: 0.08),
                              ),
                            ),
                            child: TextField(
                              controller: _tagController,
                              decoration: InputDecoration(
                                hintText: 'Add tag...',
                                hintStyle: GoogleFonts.nunito(
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? Colors.white30 : Colors.black26,
                                ),
                                border: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                                isDense: true,
                              ),
                              style: GoogleFonts.nunito(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              onSubmitted: (_) => _addTag(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _addTag,
                          child: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: const Color(0xFF4ECDC4).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              color: Color(0xFF4ECDC4),
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_additionalTags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _additionalTags.map((tag) => Chip(
                            label: Text(
                              tag,
                              style: GoogleFonts.nunito(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            deleteIcon: const Icon(Icons.close_rounded, size: 14),
                            onDeleted: () => _removeTag(tag),
                            backgroundColor: const Color(0xFF4ECDC4).withValues(alpha: 0.12),
                            side: BorderSide.none,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          )).toList(),
                        ),
                      ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // ─── Buttons ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isAdding ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        side: BorderSide(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.15)
                              : Colors.black.withValues(alpha: 0.12),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.nunito(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isAdding ? null : _onConfirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4ECDC4),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: _isAdding
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black54,
                              ),
                            )
                          : Text(
                              'Add to My Collection',
                              style: GoogleFonts.nunito(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentPreview(bool isDark) {
    final content = widget.content;
    return Container(
      padding: const EdgeInsets.all(12),
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
      child: Row(
        children: [
          // Type icon
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: content.type.accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              content.type.icon,
              color: content.type.accentColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  content.title,
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (content.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    content.description,
                    style: GoogleFonts.nunito(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white38 : Colors.black45,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (content.tags.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    content.tags.take(3).join(' · '),
                    style: GoogleFonts.nunito(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white24 : Colors.black26,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      label,
      style: GoogleFonts.nunito(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: isDark ? Colors.white54 : Colors.black45,
      ),
    );
  }

  Widget _buildDifficultySelector(bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildDifficultyOption(isDark, 'beginner', 'Beginner',
            'Simple vocabulary, basic sentences, slow pace'),
        const SizedBox(height: 6),
        _buildDifficultyOption(isDark, 'intermediate', 'Intermediate',
            'Natural language, mixed tenses, moderate complexity'),
        const SizedBox(height: 6),
        _buildDifficultyOption(isDark, 'advanced', 'Advanced',
            'Complex structures, idioms, nuanced expressions'),
      ],
    );
  }

  Widget _buildDifficultyOption(bool isDark, String value, String label, String subtitle) {
    final isSelected = _selectedDifficulty == value;
    return InkWell(
      onTap: () {
        setState(() => _selectedDifficulty = value);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
                  ? const Color(0xFF4ECDC4).withValues(alpha: 0.15)
                  : const Color(0xFF4ECDC4).withValues(alpha: 0.10))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF4ECDC4).withValues(alpha: 0.5)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.08)),
          ),
        ),
        child: Row(
          children: [
            // Radio indicator
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF4ECDC4)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF4ECDC4)
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.2)
                          : Colors.black.withValues(alpha: 0.15)),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: Colors.black,
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.nunito(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.nunito(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
