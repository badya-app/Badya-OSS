import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService {
  static final ValueNotifier<ThemeMode> themeMode = ValueNotifier(
    ThemeMode.system,
  );

  static const String _themeKey = 'theme_mode';

  static Future<void> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final String? themeString = prefs.getString(_themeKey);
    if (themeString == 'light') {
      themeMode.value = ThemeMode.light;
    } else if (themeString == 'dark') {
      themeMode.value = ThemeMode.dark;
    } else {
      themeMode.value = ThemeMode.system;
    }
  }

  static Future<void> saveTheme(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    themeMode.value = mode;
    String value;
    switch (mode) {
      case ThemeMode.light:
        value = 'light';
        break;
      case ThemeMode.dark:
        value = 'dark';
        break;
      case ThemeMode.system:
        value = 'system';
        break;
    }
    await prefs.setString(_themeKey, value);
  }
}
