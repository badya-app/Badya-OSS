import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:Badya/config/content_types.dart';
import 'package:Badya/models/user_content.dart';

/// Reusable content thumbnail widget.
///
/// Fills the constraints of its parent. Handles three source types:
/// 1. **Asset path** (starts with `assets/`) — `Image.asset`
/// 2. **Network URL** — `CachedNetworkImage`
/// 3. **No thumbnail** — falls back to the content type's default thumbnail,
///    then to gradient + icon.
///
/// Includes a gradient overlay for text readability.
/// Wrap in a `SizedBox` to set fixed dimensions (e.g. `SizedBox(height: 160)`).
class ContentThumbnail extends StatelessWidget {
  final UserContent content;

  const ContentThumbnail({super.key, required this.content});

  String? get _thumbnailUrl {
    return (content.metadata?['thumbnail_url'] ??
            content.metadata?['thumbnail'])
        as String?;
  }

  bool get _hasThumbnail => _thumbnailUrl != null && _thumbnailUrl!.isNotEmpty;
  bool get _isAssetThumbnail =>
      _hasThumbnail && _thumbnailUrl!.startsWith('assets/');

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Background / Thumbnail
        if (_isAssetThumbnail)
          Image.asset(
            _thumbnailUrl!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) => _buildDefault(context),
          )
        else if (_hasThumbnail)
          CachedNetworkImage(
            imageUrl: _thumbnailUrl!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorWidget: (_, __, ___) => _buildDefault(context),
            placeholder: (_, __) => _buildDefault(context),
          )
        else
          _buildDefault(context),

        // Gradient overlay for text readability
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.4),
                ],
                stops: const [0.6, 1.0],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDefault(BuildContext context) {
    final type = content.type;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.03),
      ),
      child: ClipRRect(
        child: Image.asset(
          type.defaultThumbnail,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  type.accentColor.withValues(alpha: 0.12),
                  type.accentColor.withValues(alpha: 0.02),
                ],
              ),
            ),
            child: Center(
              child: Icon(
                type.icon,
                size: 56,
                color: type.accentColor.withValues(alpha: 0.25),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
