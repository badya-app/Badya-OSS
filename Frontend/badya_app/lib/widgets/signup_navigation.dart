import 'package:Badya/sign_up_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

class SignUpNavigation extends StatelessWidget {
  const SignUpNavigation({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomTextColor = isDark ? Colors.white : const Color(0xFF2D3436);
    final bottomButtonBg = isDark ? Colors.white : const Color(0xFFF78B1E);
    final bottomButtonText = isDark ? const Color(0xFFF78B1E) : Colors.white;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "New here? ",
          style: GoogleFonts.nunito(
            color: bottomTextColor,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SignUpPage()),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: bottomButtonBg,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: bottomButtonBg.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              'Create Account',
              style: GoogleFonts.nunito(
                color: bottomButtonText,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ],
    ).animate().fadeIn(delay: 1300.ms).slideY(begin: 0.5);
  }
}
