import 'package:flutter/material.dart';

class LessonListSkeleton extends StatefulWidget {
  const LessonListSkeleton({super.key});

  @override
  State<LessonListSkeleton> createState() => _LessonListSkeletonState();
}

class _LessonListSkeletonState extends State<LessonListSkeleton>
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
    final cardColor = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.white;

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

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      child: Column(
        children: List.generate(3, (index) {
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: (isDark ? Colors.white : Colors.black).withValues(
                  alpha: 0.1,
                ),
                width: 1.5,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      shader(
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            shader(
                              Container(
                                width: index == 0 ? 200 : 160,
                                height: 18,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            shader(
                              Container(
                                width: index == 1 ? 120 : 100,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            shader(
                              Container(
                                width: 80,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  shader(
                    Container(
                      width: double.infinity,
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
