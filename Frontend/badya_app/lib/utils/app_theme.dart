import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class BadyaThemeExtension extends ThemeExtension<BadyaThemeExtension> {
  final Gradient appBarGradient;
  final Color bottomNavBackground;
  final Color cardActionColor;
  final Color interactiveTextHoverColor;

  const BadyaThemeExtension({
    required this.appBarGradient,
    required this.bottomNavBackground,
    required this.cardActionColor,
    required this.interactiveTextHoverColor,
  });

  @override
  BadyaThemeExtension copyWith({
    Gradient? appBarGradient,
    Color? bottomNavBackground,
    Color? cardActionColor,
    Color? interactiveTextHoverColor,
  }) {
    return BadyaThemeExtension(
      appBarGradient: appBarGradient ?? this.appBarGradient,
      bottomNavBackground: bottomNavBackground ?? this.bottomNavBackground,
      cardActionColor: cardActionColor ?? this.cardActionColor,
      interactiveTextHoverColor:
          interactiveTextHoverColor ?? this.interactiveTextHoverColor,
    );
  }

  @override
  BadyaThemeExtension lerp(
    ThemeExtension<BadyaThemeExtension>? other,
    double t,
  ) {
    if (other is! BadyaThemeExtension) return this;
    return BadyaThemeExtension(
      appBarGradient: Gradient.lerp(appBarGradient, other.appBarGradient, t)!,
      bottomNavBackground: Color.lerp(
        bottomNavBackground,
        other.bottomNavBackground,
        t,
      )!,
      cardActionColor: Color.lerp(cardActionColor, other.cardActionColor, t)!,
      interactiveTextHoverColor: Color.lerp(
        interactiveTextHoverColor,
        other.interactiveTextHoverColor,
        t,
      )!,
    );
  }
}

class AppTheme {
  static final ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xfffdf4dd),
    primaryColor: const Color(0xFFFF6B6B),
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFFFF6B6B),
      primary: const Color(0xFFFF6B6B),
      secondary: const Color(0xFF4ECDC4),
      tertiary: const Color(0xFFFFD93D),
      surface: const Color(0xFFFEF9EB),
      error: const Color(0xFFE57373),
      brightness: Brightness.light,
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFF8F4E5),
      surfaceContainer: const Color(0xFFF2EEE0),
      surfaceContainerHigh: const Color(0xFFECE8DA),
      surfaceContainerHighest: const Color(0xFFE6E2D5),
      onSurface: const Color(0xFF1D1C13),
      onSurfaceVariant: const Color(0xFF564241),
      outline: const Color(0xFF897271),
      outlineVariant: const Color(0xFFDCC0BF),
    ),
    extensions: <ThemeExtension<dynamic>>[
      BadyaThemeExtension(
        appBarGradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFEAD4BB), Color(0xFFFCECC4)],
        ),
        bottomNavBackground: const Color(0xfffbe9c1),
        cardActionColor: const Color(0xFFFF6B6B),
        interactiveTextHoverColor: Color(0xFF4ECDC4).withValues(alpha: 0.2),
      ),
    ],
    textTheme:
        GoogleFonts.nunitoTextTheme(
          ThemeData.light().textTheme.apply(
            bodyColor: const Color(0xFF2D3436), // Dark Grey for readability
            displayColor: const Color(0xFF2D3436),
          ),
        ).copyWith(
          displayLarge: GoogleFonts.nunito(
            fontWeight: FontWeight.w900,
            color: const Color(0xFF2D3436),
          ),
          displayMedium: GoogleFonts.nunito(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF2D3436),
          ),
          titleLarge: GoogleFonts.nunito(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF2D3436),
          ),
          titleMedium: GoogleFonts.nunito(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF2D3436),
          ),
          bodyLarge: GoogleFonts.nunito(
            fontWeight: FontWeight.w600,
            color: const Color(0xFF2D3436),
          ),
          bodyMedium: GoogleFonts.nunito(
            fontWeight: FontWeight.w500,
            color: const Color(0xFF636E72),
          ),
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: Color(0xFF2D3436)),
      titleTextStyle: TextStyle(
        color: Color(0xFF2D3436),
        fontSize: 24,
        fontWeight: FontWeight.w900,
        fontFamily: 'Nunito',
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24.0),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24.0),
        borderSide: BorderSide(
          color: Color(0xFF4ECDC4).withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24.0),
        borderSide: const BorderSide(color: Color(0xFF4ECDC4), width: 3),
      ),
      floatingLabelStyle: const TextStyle(
        color: Color(0xFF4ECDC4),
        fontWeight: FontWeight.bold,
      ),
      labelStyle: TextStyle(
        color: Colors.grey[500],
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(color: Colors.grey[400], fontSize: 16),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style:
          ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF6B6B), // Coral CTA
            foregroundColor: Colors.white,
            elevation: 0,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30.0),
            ),
            padding: const EdgeInsets.symmetric(vertical: 18.0, horizontal: 32),
            textStyle: GoogleFonts.nunito(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ).copyWith(
            elevation: WidgetStateProperty.resolveWith<double>((
              Set<WidgetState> states,
            ) {
              if (states.contains(WidgetState.pressed)) return 0;
              return 6; // Bouncy shadow
            }),
            shadowColor: WidgetStateProperty.all(
              Color(0xFFFF6B6B).withValues(alpha: 0.4),
            ),
          ),
    ),
    cardTheme: CardThemeData(
      elevation: 4,
      shadowColor: Color(0xFF2D3436).withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      color: Colors.white,
      margin: const EdgeInsets.all(12),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: Color(0xFFFF6B6B),
      unselectedItemColor: Color(0xFFB6B1AA),
      showUnselectedLabels: true,
      type: BottomNavigationBarType.fixed,
      elevation: 12,
      selectedLabelStyle: TextStyle(
        fontWeight: FontWeight.w800,
        fontFamily: 'Nunito',
      ),
      unselectedLabelStyle: TextStyle(
        fontWeight: FontWeight.w600,
        fontFamily: 'Nunito',
      ),
    ),
  );

  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF1A1A1A), // Dark Background
    primaryColor: const Color(0xFFFF6B6B),
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFFFF6B6B),
      primary: const Color(0xFFFF6B6B),
      secondary: const Color(0xFF4ECDC4),
      tertiary: const Color(0xFFFFD93D),
      surface: const Color(0xFF2D2D2D),
      error: const Color(0xFFE57373),
      brightness: Brightness.dark,
      surfaceContainerLowest: const Color(0xFF111111),
      surfaceContainerLow: const Color(0xFF1E1E1E),
      surfaceContainer: const Color(0xFF2D2D2D),
      surfaceContainerHigh: const Color(0xFF383838),
      surfaceContainerHighest: const Color(0xFF454545),
      onSurface: const Color(0xFFF5F6FA),
      onSurfaceVariant: const Color(0xFFB2BEC3),
      outline: const Color(0xFF8E8E8E),
      outlineVariant: const Color(0xFF505050),
    ),
    extensions: <ThemeExtension<dynamic>>[
      BadyaThemeExtension(
        appBarGradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1A1A), Color(0xFF1A1A1A)],
        ),
        bottomNavBackground: const Color(0xFF2D2D2D),
        cardActionColor: const Color(0xFFFF6B6B),
        interactiveTextHoverColor: Color(0xFF4ECDC4).withValues(alpha: 0.3),
      ),
    ],
    textTheme:
        GoogleFonts.nunitoTextTheme(
          ThemeData.dark().textTheme.apply(
            bodyColor: const Color(0xFFF5F6FA), // Light Grey for readability
            displayColor: const Color(0xFFF5F6FA),
          ),
        ).copyWith(
          displayLarge: GoogleFonts.nunito(
            fontWeight: FontWeight.w900,
            color: const Color(0xFFF5F6FA),
          ),
          displayMedium: GoogleFonts.nunito(
            fontWeight: FontWeight.w800,
            color: const Color(0xFFF5F6FA),
          ),
          titleLarge: GoogleFonts.nunito(
            fontWeight: FontWeight.w800,
            color: const Color(0xFFF5F6FA),
          ),
          titleMedium: GoogleFonts.nunito(
            fontWeight: FontWeight.w700,
            color: const Color(0xFFF5F6FA),
          ),
          bodyLarge: GoogleFonts.nunito(
            fontWeight: FontWeight.w600,
            color: const Color(0xFFF5F6FA),
          ),
          bodyMedium: GoogleFonts.nunito(
            fontWeight: FontWeight.w500,
            color: const Color(0xFFB2BEC3), // Muted grey for secondary text
          ),
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      iconTheme: IconThemeData(color: Color(0xFFF5F6FA)),
      titleTextStyle: TextStyle(
        color: Color(0xFFF5F6FA),
        fontSize: 24,
        fontWeight: FontWeight.w900,
        fontFamily: 'Nunito',
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF2D2D2D),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24.0),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24.0),
        borderSide: BorderSide(
          color: Color(0xFF4ECDC4).withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24.0),
        borderSide: const BorderSide(color: Color(0xFF4ECDC4), width: 3),
      ),
      floatingLabelStyle: const TextStyle(
        color: Color(0xFF4ECDC4),
        fontWeight: FontWeight.bold,
      ),
      labelStyle: TextStyle(
        color: Colors.grey[400],
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(color: Colors.grey[600], fontSize: 16),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style:
          ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF6B6B),
            foregroundColor: Colors.white,
            elevation: 0,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30.0),
            ),
            padding: const EdgeInsets.symmetric(vertical: 18.0, horizontal: 32),
            textStyle: GoogleFonts.nunito(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ).copyWith(
            elevation: WidgetStateProperty.resolveWith<double>((
              Set<WidgetState> states,
            ) {
              if (states.contains(WidgetState.pressed)) return 0;
              return 6;
            }),
            shadowColor: WidgetStateProperty.all(
              Color(0xFFFF6B6B).withValues(alpha: 0.4),
            ),
          ),
    ),
    cardTheme: CardThemeData(
      elevation: 4,
      shadowColor: Color(0xFF000000).withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      color: const Color(0xFF2D2D2D),
      margin: const EdgeInsets.all(12),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFF2D2D2D),
      selectedItemColor: Color(0xFFFF6B6B),
      unselectedItemColor: Color(0xFF636E72),
      showUnselectedLabels: true,
      type: BottomNavigationBarType.fixed,
      elevation: 12,
      selectedLabelStyle: TextStyle(
        fontWeight: FontWeight.w800,
        fontFamily: 'Nunito',
      ),
      unselectedLabelStyle: TextStyle(
        fontWeight: FontWeight.w600,
        fontFamily: 'Nunito',
      ),
    ),
  );
}
