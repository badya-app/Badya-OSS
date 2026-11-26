import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

class LoginHeader extends StatelessWidget {
  const LoginHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtitleColor = isDark
        ? Colors.white.withValues(alpha: 0.9)
        : const Color(0xFF2D3436);

    return Column(
      children: [
        Text(
              'Badya',
              style: GoogleFonts.merriweather(
                fontSize: 40,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                color: const Color(0xFFF78B1E),
                shadows: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.5),
                    blurRadius: 0,
                    offset: const Offset(2, 2),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
            )
            .animate()
            .fadeIn(delay: 200.ms)
            .slideY(begin: 0.5, curve: Curves.easeOutBack),
        const SizedBox(height: 4),
        Text(
              "Immerse yourself in language.",
              style: GoogleFonts.nunito(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: subtitleColor,
              ),
            )
            .animate()
            .fadeIn(delay: 400.ms)
            .slideY(begin: 0.5, curve: Curves.easeOutBack),
      ],
    );
  }
}
