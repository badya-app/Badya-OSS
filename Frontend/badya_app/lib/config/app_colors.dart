import 'package:flutter/material.dart';

class AppColors {
  // Brand Colors
  static const Color primary = Color(0xFF1ABC9C);
  static const Color primaryDark = Color(0xFF16A085);
  static const Color secondary = Color(0xFF8B5CF6);
  static const Color secondaryDark = Color(0xFF6366F1);
  
  // Status Colors
  static const Color error = Color(0xFFEF4444);
  static const Color errorDark = Color(0xFFDC2626);
  static const Color warning = Color(0xFFF59E0B);
  static const Color success = Color(0xFF10B981);
  
  // Background & Surfaces (Dark)
  static const Color bgDark = Color(0xFF0F172A);
  static const Color bgDarkIndigo = Color(0xFF1E1B4B);
  static const Color surfaceDark = Color(0xFF1E293B);
  
  // Background & Surfaces (Light)
  static const Color bgLight = Color(0xFFF8FAFC);
  static const Color bgLightBlue = Color(0xFFEFF6FF);
  static const Color surfaceLight = Colors.white;

  // Custom UI Elements
  static const Color accentCyan = Color(0xFF06B6D4);
  static const Color accentIndigo = Color(0xFF4F46E5);
  
  // Glassmorphism
  static Color glassWhite(double opacity) => Colors.white.withValues(alpha: opacity);
  static Color glassBlack(double opacity) => Colors.black.withValues(alpha: opacity);
}
