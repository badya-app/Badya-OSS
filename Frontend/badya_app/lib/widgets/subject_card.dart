import 'dart:ui';
import 'package:flutter/material.dart';

class SubjectCard extends StatefulWidget {
  final String title;
  final String description;
  final String imagePath;
  final double progress;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDelete;

  const SubjectCard({
    super.key,
    required this.title,
    required this.description,
    required this.imagePath,
    required this.progress,
    required this.color,
    required this.onTap,
    this.onLongPress,
    this.onDelete,
  });

  @override
  State<SubjectCard> createState() => _SubjectCardState();
}

class _SubjectCardState extends State<SubjectCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final int percentage = (widget.progress * 100).toInt();

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _isPressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Image Section with gradient overlay for title/description
                SizedBox(
                  height: 120,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Background Image with blur and directional fade
                      Positioned.fill(
                        child: ShaderMask(
                          shaderCallback: (Rect bounds) {
                            return LinearGradient(
                              begin: Alignment.topRight,
                              end: Alignment.bottomLeft,
                              colors: [
                                Colors.black.withValues(alpha: 0.6),
                                Colors.transparent,
                              ],
                              stops: const [0.01, 0.7],
                            ).createShader(bounds);
                          },
                          blendMode: BlendMode.dstIn,
                          child: ImageFiltered(
                            imageFilter: ImageFilter.blur(
                              sigmaX: 0.5,
                              sigmaY: 0.5,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.only(
                                left: 60,
                                bottom: 1,
                              ),
                              child: _buildImage(widget.imagePath),
                            ),
                          ),
                        ),
                      ),
                      // Title and Description at bottom
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 12,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    widget.title,
                                    style: textTheme.titleLarge?.copyWith(
                                      color: Colors.white,
                                      fontSize: 20,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black.withValues(alpha: 0.5),
                                          offset: const Offset(2, 2),
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (widget.onDelete != null)
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: Colors.white70,
                                      size: 20,
                                    ),
                                    onPressed: widget.onDelete,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.description,
                              style: textTheme.bodyMedium?.copyWith(
                                color: Colors.white.withValues(alpha: 0.95),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    offset: const Offset(1, 1),
                                    blurRadius: 2,
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Progress Bar Section - solid bottom bar
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 7,
                  ),
                  decoration: const BoxDecoration(
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildSegmentedProgressBar(
                          progress: widget.progress,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '$percentage%',
                        style: textTheme.bodyLarge?.copyWith(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentedProgressBar({
    required double progress,
    required Color color,
  }) {
    const int totalSegments = 5;
    final int filledSegments = (progress * totalSegments).ceil();

    return Row(
      children: List.generate(totalSegments, (index) {
        final bool isFilled = index < filledSegments;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: index < totalSegments - 1 ? 6 : 0),
            height: 8,
            decoration: BoxDecoration(
              color: isFilled ? color : color.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildImage(String path) {
    if (path.startsWith('http')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!
                  : null,
              color: Colors.white,
              strokeWidth: 2,
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => const Icon(
          Icons.broken_image_rounded,
          color: Colors.white,
          size: 40,
        ),
      );
    }
    return Image.asset(
      path,
      fit: BoxFit.fill,
      alignment: Alignment.topCenter,
      errorBuilder: (context, error, stackTrace) => const Icon(
        Icons.image_not_supported_rounded,
        color: Colors.white,
        size: 40,
      ),
    );
  }
}
