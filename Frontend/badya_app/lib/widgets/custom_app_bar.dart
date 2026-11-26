import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/app_theme.dart';

class CustomAppBar extends StatelessWidget {
  final VoidCallback? onMenuPressed;
  final VoidCallback? onLanguagePressed;
  final String? languageCode;
  final bool showLanguageButton;
  final bool showMenuButton;
  final String? title;
  final List<Widget>? actions;

  final String menuTooltip;
  final Widget? customTitle;

  const CustomAppBar({
    super.key,
    this.onMenuPressed,
    this.onLanguagePressed,
    this.languageCode,
    this.showLanguageButton = true,
    this.showMenuButton = true,
    this.title,
    this.actions,
    this.menuTooltip = 'Menu',
    this.customTitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badyaTheme = theme.extension<BadyaThemeExtension>();

    return SliverAppBar(
      backgroundColor: theme.scaffoldBackgroundColor,
      pinned: true,
      title:
          customTitle ??
          (title != null
              ? Text(
                  title!,
                  style: GoogleFonts.nunito(
                    color: theme.appBarTheme.titleTextStyle?.color,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                  ),
                )
              : null),
      centerTitle: true,
      leading: showMenuButton
          ? Container(
              margin: const EdgeInsets.only(left: 8),
              child: IconButton(
                onPressed: onMenuPressed,
                icon: Icon(
                  Icons.menu_rounded,
                  color: theme.appBarTheme.iconTheme?.color,
                  size: 28,
                ),
                tooltip: menuTooltip,
              ),
            )
          : null,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(gradient: badyaTheme?.appBarGradient),
        ),
      ),
      actions: [
        if (actions != null) ...actions!,
        if (showLanguageButton)
          GestureDetector(
            onTap: onLanguagePressed,
            child: Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.only(right: 12, left: 8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.5),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: ClipOval(
                child: languageCode != null
                    ? CountryFlag.fromCountryCode(languageCode!)
                    : Center(
                        child: Text(
                          '🌐',
                          style: TextStyle(
                            fontSize: 24,
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                        ),
                      ),
              ),
            ),
          ),
      ],
    );
  }
}
