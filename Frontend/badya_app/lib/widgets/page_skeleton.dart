import 'package:flutter/material.dart';
import 'package:Badya/widgets/transcript_skeleton.dart';

class PageSkeleton extends StatefulWidget {
  const PageSkeleton({super.key});

  @override
  State<PageSkeleton> createState() => _PageSkeletonState();
}

class _PageSkeletonState extends State<PageSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark
        ? const Color(0xFF2A2A2A)
        : const Color(0xFFE0E0E0);
    final shimmerColor = isDark
        ? const Color(0xFF3E3E3E)
        : const Color(0xFFF5F5F5);

    Widget shader(Widget child) {
      return AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) {
              return LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [baseColor, shimmerColor, baseColor],
                stops: [
                  (_controller.value - 0.25).clamp(0.0, 1.0),
                  _controller.value.clamp(0.0, 1.0),
                  (_controller.value + 0.25).clamp(0.0, 1.0),
                ],
              ).createShader(bounds);
            },
            child: child!,
          );
        },
        child: child,
      );
    }

    return Column(
      children: [
        // ── Video placeholder ──────────────────────────────────────────
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: shader(
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(color: Colors.white),
            ),
          ),
        ),
        // ── Transcript skeleton ────────────────────────────────────────
        const Expanded(child: TranscriptSkeleton()),
        // ── Controls bar placeholder ───────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              shader(
                Container(
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  shader(
                    Container(
                      width: 60,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // ── Bottom bar placeholder ─────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: (isDark ? Colors.white : Colors.black).withValues(
                  alpha: 0.1,
                ),
              ),
            ),
          ),
          child: SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                shader(
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                shader(
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
