import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

class EmptyStateWidget extends StatelessWidget {
  final String message;
  final String? subMessage;

  const EmptyStateWidget({
    super.key,
    required this.message,
    this.subMessage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              'assets/images/straw.svg',
              width: 120,
              height: 120,
              placeholderBuilder: (BuildContext context) => const SizedBox(
                width: 120,
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              ),
            )
                .animate(onPlay: (controller) => controller.repeat(reverse: true))
                .moveX(
                  begin: -60,
                  end: 60,
                  duration: 2.seconds,
                  curve: Curves.easeInOutSine,
                )
                .rotate(
                  begin: -0.1,
                  end: 0.1,
                  duration: 2.seconds,
                  curve: Curves.easeInOutSine,
                ),
            const SizedBox(height: 48),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: theme.textTheme.titleLarge?.color,
              ),
            ),
            if (subMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                subMessage!,
                textAlign: TextAlign.center,
                style: GoogleFonts.nunito(
                  fontSize: 16,
                  color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
