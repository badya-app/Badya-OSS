import 'package:flutter/material.dart';

class TranscriptSkeleton extends StatefulWidget {
  const TranscriptSkeleton({super.key});

  @override
  State<TranscriptSkeleton> createState() => _TranscriptSkeletonState();
}

class _TranscriptSkeletonState extends State<TranscriptSkeleton>
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

  static const _widths = [0.60, 0.80, 0.45, 0.90, 0.50, 0.75, 0.55];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark
        ? const Color(0xFF2A2A2A)
        : const Color(0xFFE0E0E0);
    final shimmerColor = isDark
        ? const Color(0xFF3E3E3E)
        : const Color(0xFFF5F5F5);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
        ),
      ),
      child: AnimatedBuilder(
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
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: 7,
          itemBuilder: (context, index) {
            final w = _widths[index % _widths.length];
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 50,
                    height: 20,
                    margin: const EdgeInsets.only(right: 10, top: 2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  Expanded(
                    child: FractionallySizedBox(
                      widthFactor: w,
                      alignment: Alignment.centerLeft,
                      child: Container(
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
