import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

/// A full-screen celebration overlay that shows a gift box, the amount of
/// coins awarded, sparkle particles, and plays a celebration sound.
///
/// Usage:
/// ```dart
/// await CoinCelebrationOverlay.show(context, coinsAwarded: 150);
/// ```
class CoinCelebrationOverlay extends StatefulWidget {
  final int coinsAwarded;
  final String? description;
  final bool showGiftBox;

  const CoinCelebrationOverlay({
    super.key,
    required this.coinsAwarded,
    this.description,
    this.showGiftBox = true,
  });

  /// Show the celebration as a full-screen dialog.
  /// Returns after the user taps or the auto-dismiss timer completes.
  static Future<void> show(
    BuildContext context, {
    required int coinsAwarded,
    String? description,
    bool showGiftBox = true,
  }) {
    return showGeneralDialog(
      context: context,
      pageBuilder: (context, anim1, anim2) => CoinCelebrationOverlay(
        coinsAwarded: coinsAwarded,
        description: description,
        showGiftBox: showGiftBox,
      ),
      barrierDismissible: true,
      barrierLabel: 'Coin Celebration',
      barrierColor: Colors.black.withValues(alpha: 0.6),
      transitionDuration: const Duration(milliseconds: 600),
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.8, end: 1.0).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<CoinCelebrationOverlay> createState() => _CoinCelebrationOverlayState();
}

class _CoinCelebrationOverlayState extends State<CoinCelebrationOverlay>
    with TickerProviderStateMixin {
  late AnimationController _counterController;
  late Animation<double> _counterAnimation;
  late AnimationController _sparkleController;
  late AudioPlayer _audioPlayer;

  @override
  void initState() {
    super.initState();

    // Coin counter animation (counts up from 0 to coinsAwarded)
    _counterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _counterAnimation = Tween<double>(
      begin: 0,
      end: widget.coinsAwarded.toDouble(),
    ).animate(
      CurvedAnimation(parent: _counterController, curve: Curves.easeOutCubic),
    );

    _counterController.forward();

    // Sparkle / glow pulsing animation
    _sparkleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    // Play celebration sound
    _audioPlayer = AudioPlayer();
    Future.delayed(const Duration(milliseconds: 200), () {
      _audioPlayer.play(AssetSource('sounds/mixkit-magical-coin-pitch.wav'));
    });

    // Auto-dismiss after 4 seconds so the user is never stuck
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _counterController.dispose();
    _sparkleController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.2,
              colors: [
                (isDark ? const Color(0xFF1A1A2E) : const Color(0xFFFFF8E7))
                    .withValues(alpha: 0.95),
                (isDark ? const Color(0xFF0F0F1A) : const Color(0xFFFFE8C8))
                    .withValues(alpha: 0.9),
              ],
            ),
          ),
          child: Stack(
            children: [
              // --- Background sparkle particles ---
              ...List.generate(12, (i) => _buildSparkle(i)),

              // --- Center content ---
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 40),

                    // Gift box with glow
                    if (widget.showGiftBox) _buildGiftBox(),
                    if (widget.showGiftBox) const SizedBox(height: 32) else const SizedBox(height: 24),

                    // Title
                    Text(
                      widget.description ?? 'Bonus!',
                      style: GoogleFonts.merriweather(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : const Color(0xFF2D3436),
                      ),
                    ).animate().fadeIn(
                      delay: 300.ms,
                      duration: 600.ms,
                    ).slideY(begin: 0.3, end: 0),

                    const SizedBox(height: 12),

                    // Coin counter
                    _buildCoinCounter(),

                    const SizedBox(height: 8),

                    // "Coins Earned" label
                    Text(
                      'Coins Earned',
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.6)
                            : Colors.black.withValues(alpha: 0.5),
                        letterSpacing: 1.2,
                      ),
                    ).animate().fadeIn(
                      delay: 800.ms,
                      duration: 500.ms,
                    ).slideY(begin: 0.2, end: 0),

                    const SizedBox(height: 48),

                    // Tap to continue
                    Text(
                      'Tap to continue',
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.35)
                            : Colors.black.withValues(alpha: 0.25),
                      ),
                    ).animate(delay: 1500.ms).shimmer(duration: 1500.ms),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Gift Box ──

  Widget _buildGiftBox() {
    return AnimatedBuilder(
      animation: _sparkleController,
      builder: (context, child) {
        final glowOpacity = 0.2 + (0.3 * _sparkleController.value);
        return Container(
          width: 180,
          height: 180,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF78B1E).withValues(alpha: glowOpacity),
                blurRadius: 40 + (20 * _sparkleController.value),
                spreadRadius: 8 + (8 * _sparkleController.value),
              ),
            ],
          ),
          child: child,
        );
      },
      child: SvgPicture.asset(
        'assets/images/giftbox.svg',
        width: 140,
        height: 140,
        fit: BoxFit.contain,
      ).animate().scale(
        delay: 0.ms,
        duration: 1000.ms,
        curve: Curves.elasticOut,
        begin: Offset.zero,
        end: const Offset(1.0, 1.0),
      ),
    );
  }

  // ── Coin Counter ──

  Widget _buildCoinCounter() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _counterAnimation,
      builder: (context, child) {
        final displayValue = _counterAnimation.value.round();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Coin icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD93D), Color(0xFFF59E0B)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFD93D).withValues(alpha: 0.4),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.monetization_on_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '+$displayValue',
              style: GoogleFonts.manrope(
                fontSize: 52,
                fontWeight: FontWeight.w900,
                height: 1.1,
                color: isDark ? Colors.white : const Color(0xFF2D3436),
              ),
            ).animate().fadeIn(delay: 200.ms, duration: 800.ms),
          ],
        );
      },
    );
  }

  // ── Sparkle Particles ──

  Widget _buildSparkle(int index) {
    // Distribute sparkles around the screen with different delays
    final angle = (index / 12) * 2 * math.pi;
    final distance = 0.3 + (index % 3) * 0.15;
    final size = 6.0 + (index % 4) * 4.0;
    final delay = (index * 150).ms;

    return AnimatedBuilder(
      animation: _sparkleController,
      builder: (context, child) {
        final phase = (_sparkleController.value + index * 0.15) % 1.0;
        final opacity = (1.0 - (phase - 0.5).abs() * 2).clamp(0.0, 1.0);
        final scale = 0.3 + 0.7 * (1.0 - phase);

        // Orbital position
        final xOffset = math.cos(angle + _sparkleController.value * 0.3) *
            distance *
            MediaQuery.of(context).size.width *
            0.4;
        final yOffset = math.sin(angle + _sparkleController.value * 0.2) *
            distance *
            MediaQuery.of(context).size.height *
            0.4;

        return Positioned(
          left: MediaQuery.of(context).size.width / 2 + xOffset - size / 2,
          top: MediaQuery.of(context).size.height / 2 + yOffset - size / 2,
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: [
                  const Color(0xFFFFD93D),
                  const Color(0xFFF78B1E),
                  const Color(0xFFFF6B6B),
                  const Color(0xFF4ECDC4),
                ][index % 4].withValues(alpha: opacity * 0.8),
                boxShadow: [
                  BoxShadow(
                    color: [
                      const Color(0xFFFFD93D),
                      const Color(0xFFF78B1E),
                      const Color(0xFFFF6B6B),
                      const Color(0xFF4ECDC4),
                    ][index % 4].withValues(alpha: opacity * 0.3),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
