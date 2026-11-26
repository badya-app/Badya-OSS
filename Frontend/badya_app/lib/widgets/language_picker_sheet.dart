import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';

/// Shows a language picker bottom sheet and calls [onLanguageSelected] when
/// the user picks a language.
void showLanguagePickerSheet({
  required BuildContext context,
  required List<String> myLanguages,
  required String currentLanguage,
  required Map<String, String> languageCodes,
  required void Function(String language) onLanguageSelected,
}) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.dividerColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Select Language',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          ...myLanguages.map(
            (lang) => ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: lang == currentLanguage
                      ? colorScheme.secondary.withValues(alpha: 0.1)
                      : theme.dividerColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: lang == currentLanguage
                        ? colorScheme.secondary
                        : theme.dividerColor,
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
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              trailing: lang == currentLanguage
                  ? Icon(Icons.check_circle, color: colorScheme.secondary)
                  : null,
              onTap: () {
                onLanguageSelected(lang);
                Navigator.pop(ctx);
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
