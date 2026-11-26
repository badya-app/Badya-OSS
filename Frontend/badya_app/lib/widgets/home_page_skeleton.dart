import 'package:flutter/material.dart';

/// Skeleton shimmer placeholder that mirrors the HomePage layout while data loads.
/// [showTopSection] controls whether stats banner and nav card placeholders appear.
class HomePageSkeleton extends StatefulWidget {
  final bool showTopSection;

  const HomePageSkeleton({super.key, this.showTopSection = true});

  @override
  State<HomePageSkeleton> createState() => _HomePageSkeletonState();
}

class _HomePageSkeletonState extends State<HomePageSkeleton>
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
    final cardBorderColor = (isDark ? Colors.white : Colors.black)
        .withValues(alpha: 0.08);

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
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(color: cardBorderColor),
        ),
        child: child,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Stats Banner ──────────────────────────────────────────
          if (widget.showTopSection) ...[
            skeletonCard(
              height: 84,
              borderRadius: 24,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: List.generate(
                    4,
                    (i) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        placeholderBox(width: 36, height: 20),
                        const SizedBox(height: 6),
                        placeholderBox(
                          width: [24, 44, 32, 28][i].toDouble(),
                          height: 12,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ─── Navigation Cards ──────────────────────────────────────
            Row(
              children: List.generate(
                2,
                (i) => Expanded(
                  child: skeletonCard(
                    height: 110,
                    borderRadius: 18,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              placeholderBox(
                                width: 34,
                                height: 34,
                                borderRadius: 10,
                              ),
                              placeholderBox(
                                width: 18,
                                height: 18,
                                borderRadius: 9,
                              ),
                            ],
                          ),
                          const Spacer(),
                          placeholderBox(
                            width: [60, 74][i].toDouble(),
                            height: 18,
                          ),
                          const SizedBox(height: 4),
                          placeholderBox(
                            width: [84, 96][i].toDouble(),
                            height: 10,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ).expand((w) => [w, const SizedBox(width: 12)]).toList()
                ..removeLast(),
            ),
            const SizedBox(height: 20),
          ],

          // ─── Filter Chips ─────────────────────────────────────────
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
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
          const SizedBox(height: 20),

          // ─── Recommended Topics Section ────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              placeholderBox(width: 156, height: 18),
              placeholderBox(width: 44, height: 13),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 3,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, __) => SizedBox(
                width: 280,
                child: skeletonCard(
                  borderRadius: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Thumbnail area
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Stack(
                            children: [
                              placeholderBox(
                                width: double.infinity,
                                height: double.infinity,
                                borderRadius: 12,
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Info area
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            placeholderBox(
                              width: 200,
                              height: 15,
                            ),
                            const SizedBox(height: 6),
                            placeholderBox(
                              width: 120,
                              height: 11,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),

          // ─── Continue Watching Section ────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              placeholderBox(width: 152, height: 18),
              placeholderBox(width: 44, height: 13),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 3,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, __) => SizedBox(
                width: 280,
                child: skeletonCard(
                  borderRadius: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      placeholderBox(
                        width: double.infinity,
                        height: 4,
                        borderRadius: 0,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Stack(
                            children: [
                              placeholderBox(
                                width: double.infinity,
                                height: double.infinity,
                                borderRadius: 12,
                              ),
                              Positioned(
                                top: 0,
                                left: 0,
                                child: placeholderBox(
                                  width: 60,
                                  height: 22,
                                  borderRadius: 8,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            placeholderBox(
                              width: 180,
                              height: 15,
                            ),
                            const SizedBox(height: 8),
                            placeholderBox(
                              width: double.infinity,
                              height: 4,
                              borderRadius: 2,
                            ),
                            const SizedBox(height: 6),
                            placeholderBox(
                              width: 28,
                              height: 11,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),

          // ─── Recent Additions Section ─────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              placeholderBox(width: 132, height: 18),
              placeholderBox(width: 44, height: 13),
            ],
          ),
          const SizedBox(height: 14),
          ...List.generate(
            3,
            (i) => Padding(
              padding: EdgeInsets.only(bottom: i < 2 ? 12 : 0),
              child: skeletonCard(
                height: 100,
                borderRadius: 20,
                child: Row(
                  children: [
                    // Accent bar
                    placeholderBox(
                      width: 4,
                      height: double.infinity,
                      borderRadius: 0,
                    ),
                    const SizedBox(width: 14),
                    // Thumbnail
                    placeholderBox(
                      width: 72,
                      height: 72,
                      borderRadius: 14,
                    ),
                    const SizedBox(width: 14),
                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          placeholderBox(
                            height: 16,
                          ),
                          const SizedBox(height: 6),
                          placeholderBox(
                            width: 140,
                            height: 12,
                          ),
                          const SizedBox(height: 8),
                          placeholderBox(
                            width: 100,
                            height: 4,
                            borderRadius: 2,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ─── See all button ───────────────────────────────────────
          skeletonCard(
            height: 52,
            borderRadius: 16,
            child: Center(
              child: placeholderBox(width: 120, height: 15),
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }
}
