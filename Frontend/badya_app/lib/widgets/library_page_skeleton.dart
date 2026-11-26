import 'package:flutter/material.dart';

/// Skeleton shimmer placeholder that mirrors the LibraryPage layout.
class LibraryPageSkeleton extends StatefulWidget {
  const LibraryPageSkeleton({super.key});

  @override
  State<LibraryPageSkeleton> createState() => _LibraryPageSkeletonState();
}

class _LibraryPageSkeletonState extends State<LibraryPageSkeleton>
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
    final cardBorderColor = (isDark ? Colors.white : Colors.black).withValues(
      alpha: 0.08,
    );

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

    Widget placeholderBox({
      double? width,
      required double height,
      double borderRadius = 6,
    }) {
      return shader(
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        ),
      );
    }

    Widget skeletonCard({
      double height = 120,
      double borderRadius = 20,
      Widget? child,
    }) {
      return Container(
        height: height,
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(color: cardBorderColor),
        ),
        child: child,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),

        // ─── Filter Chips ─────────────────────────────────────────
        SizedBox(
          height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 5,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => placeholderBox(
              width: [36, 32, 52, 44, 36][i].toDouble(),
              height: 36,
              borderRadius: 18,
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ─── Sort / Count Header ──────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              placeholderBox(width: 44, height: 13),
              const Spacer(),
              placeholderBox(width: 90, height: 28, borderRadius: 16),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ─── Content Cards (Tall) ─────────────────────────────────
        ...List.generate(3, (index) {
          return skeletonCard(
            height: 320,
            borderRadius: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                placeholderBox(
                  width: double.infinity,
                  height: 44,
                  borderRadius: 0,
                ),
                placeholderBox(
                  width: double.infinity,
                  height: 152,
                  borderRadius: 0,
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      placeholderBox(width: 200, height: 18),
                      const SizedBox(height: 8),
                      placeholderBox(width: double.infinity, height: 14),
                      const SizedBox(height: 4),
                      placeholderBox(width: 180, height: 14),
                      const SizedBox(height: 12),
                      Row(
                        children: List.generate(
                          3,
                          (i) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: placeholderBox(
                              width: 50,
                              height: 20,
                              borderRadius: 10,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
