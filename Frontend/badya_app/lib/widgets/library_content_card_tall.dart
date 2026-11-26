import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:Badya/config/content_types.dart';
import 'package:Badya/models/user_content.dart';
import 'package:Badya/utils/profile_images.dart';
import 'package:Badya/widgets/tag_chip.dart';
import 'package:Badya/widgets/content_thumbnail.dart';

/// Large media card for the library page — consistent across all content types.
///
/// Features:
/// - Thumbnail with type + duration badges
/// - Title + description (2 lines)
/// - Tag pills (neutral)
/// - Author bar with avatar and name
class LibraryContentCardTall extends StatefulWidget {
  final UserContent content;
  final double progress;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;

  /// Shown in the 3-dot menu for **other users'** content — blocks the author
  /// (hides their content everywhere) via [BlockService].
  final VoidCallback? onBlockUser;

  /// Shown in the 3-dot menu for **other users'** content — opens the report
  /// sheet for the author via [ReportUserSheet].
  final VoidCallback? onReportUser;

  const LibraryContentCardTall({
    super.key,
    required this.content,
    this.progress = 0.0,
    this.onTap,
    this.onDelete,
    this.onEdit,
    this.onBlockUser,
    this.onReportUser,
  });

  @override
  State<LibraryContentCardTall> createState() => _LibraryContentCardTallState();
}

class _LibraryContentCardTallState extends State<LibraryContentCardTall> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.3)
                    : Colors.black.withValues(alpha: 0.06),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Author bar — neutral consistent color
                if (widget.content.authorName.isNotEmpty)
                  _buildAuthorBar(context, isDark),

                // Thick accent-colored separator between author bar and thumbnail
                _buildTypeSeparator(context, widget.content.type.accentColor),

                // Thumbnail / Media section
                _buildMediaSection(context),

                // Content info
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        widget.content.title,
                        style: GoogleFonts.nunito(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),

                      // Description
                      Text(
                        widget.content.description.isNotEmpty
                            ? widget.content.description
                            : '',
                        style: GoogleFonts.nunito(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white38 : Colors.black45,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),

                      // Tag pills (show first 3 tags, +N more)
                      if (widget.content.tags.isNotEmpty)
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            ...widget.content.tags
                                .take(3)
                                .map(
                                  (tag) => TagPill(label: tag, isCompact: true),
                                ),
                            if (widget.content.tags.length > 3)
                              TagPill(
                                label: '+${widget.content.tags.length - 3}',
                                isCompact: true,
                              ),
                          ],
                        ),
                      const SizedBox(height: 10),
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

  Widget _buildMediaSection(BuildContext context) {
    final type = widget.content.type;

    // Compute whether a custom thumbnail exists (for icon overlay logic)
    final thumbnailUrl =
        (widget.content.metadata?['thumbnail_url'] ??
                widget.content.metadata?['thumbnail'])
            as String?;
    final hasRealThumbnail = thumbnailUrl != null && thumbnailUrl.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(0),
      child: SizedBox(
        height: 160,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Thumbnail image (handles asset, network, and default fallback)
            ContentThumbnail(content: widget.content),

            // Duration badge (top-right, for video types)
            if (type == ContentType.youtube)
              Positioned(top: 12, right: 12, child: _buildDurationBadge()),

            // Type icon (bottom-left, for cards without a real thumbnail)
            if (!hasRealThumbnail)
              Positioned(
                left: 16,
                bottom: 16,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: type.accentColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: type.accentColor.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Icon(type.icon, color: type.accentColor, size: 22),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDurationBadge() {
    final metadata = widget.content.metadata;
    final durationSeconds = metadata?['duration_seconds'] as int?;
    if (durationSeconds == null) return const SizedBox.shrink();

    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    final label =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.play_arrow_rounded,
                size: 12,
                color: Colors.white,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.nunito(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuthorBar(BuildContext context, bool isDark) {
    final type = widget.content.type;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF252525) : const Color(0xFFF5F5F5),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: Row(
        children: [
          // Avatar with neutral ring
          Container(
            padding: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 12,
              backgroundColor: Colors.grey.withValues(alpha: 0.15),
              backgroundImage: resolveProfileImage(
                widget.content.authorPhotoUrl,
              ),
            ),
          ),
          const SizedBox(width: 9),

          // Author name — neutral text color
          Expanded(
            child: Text(
              widget.content.authorName,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.95)
                    : Colors.black87,
                letterSpacing: 0.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),

          // Content-type pill badge — matches topic type color
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: type.accentColor.withValues(alpha: isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: type.accentColor.withValues(alpha: isDark ? 0.4 : 0.2),
                width: 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(type.icon, size: 11, color: type.accentColor),
                const SizedBox(width: 4),
                Text(
                  type.displayName,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: type.accentColor,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),

          // 3-dot menu button (moved from title row to topbar)
          if (widget.onEdit != null ||
              widget.onDelete != null ||
              widget.onBlockUser != null ||
              widget.onReportUser != null) ...[
            const SizedBox(width: 4),
            _buildMenuButton(context, isDark),
          ],
        ],
      ),
    );
  }

  Widget _buildTypeSeparator(BuildContext context, Color accentColor) {
  	return SizedBox(
  	  width: double.infinity,
  	  height: 4,
  	  child: CustomPaint(painter: _LensPainter(color: accentColor)),
    );
  }

  Widget _buildMenuButton(BuildContext context, bool isDark) {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      icon: Icon(
        Icons.more_vert_rounded,
        size: 20,
        color: isDark ? Colors.white38 : Colors.black38,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (value) {
        switch (value) {
          case 'edit':
            widget.onEdit?.call();
          case 'delete':
            widget.onDelete?.call();
          case 'block':
            widget.onBlockUser?.call();
          case 'report':
            widget.onReportUser?.call();
        }
      },
      itemBuilder: (context) {
        return [
          if (widget.onEdit != null)
            const PopupMenuItem(
              value: 'edit',
              child: _MenuRow(icon: Icons.tune_rounded, label: 'Edit'),
            ),
          if (widget.onDelete != null)
            const PopupMenuItem(
              value: 'delete',
              child: _MenuRow(
                icon: Icons.delete_outline_rounded,
                label: 'Delete',
                isDestructive: true,
              ),
            ),
          if (widget.onBlockUser != null)
            const PopupMenuItem(
              value: 'block',
              child: _MenuRow(
                icon: Icons.person_off_rounded,
                label: 'Block user',
                isDestructive: true,
              ),
            ),
          if (widget.onReportUser != null)
            const PopupMenuItem(
              value: 'report',
              child: _MenuRow(
                icon: Icons.flag_rounded,
                label: 'Report user',
                isDestructive: true,
              ),
            ),
        ];
      },
    );
  }
}

/// Paints a lens/cigar shape — full width, thick in the middle, thin at edges.
class _LensPainter extends CustomPainter {
  final Color color;
  _LensPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, size.height / 2)
      ..quadraticBezierTo(size.width / 2, 0, size.width, size.height / 2)
      ..quadraticBezierTo(size.width / 2, size.height, 0, size.height / 2)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_LensPainter oldDelegate) => oldDelegate.color != color;
}

/// Reusable menu row widget for popup menu items.
class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDestructive;

  const _MenuRow({
    required this.icon,
    required this.label,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: isDestructive ? Colors.redAccent : null),
        const SizedBox(width: 10),
        Text(
          label,
          style: GoogleFonts.nunito(
            fontWeight: FontWeight.w600,
            color: isDestructive ? Colors.redAccent : null,
          ),
        ),
      ],
    );
  }
}
