import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:Badya/config/content_types.dart';
import 'package:Badya/models/user_content.dart';
import 'package:Badya/widgets/tag_chip.dart';
import 'package:Badya/widgets/content_thumbnail.dart';

/// Compact horizontal content card for list views (library, home recent, my content).
///
/// Features (same elements as before, now in a horizontal layout):
/// - Accent bar (vertical, left side — color by type)
/// - Square thumbnail (left) with type badge overlay
/// - Right: title, description, tags, meta row, Add/Added button, popup menu
class LibraryContentCard extends StatefulWidget {
  final UserContent content;
  final double progress;
  final bool isAdded;
  final VoidCallback? onTap;
  final VoidCallback? onAdd;
  final VoidCallback? onEditLanguages;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;

  /// Shown in the 3-dot menu for **other users'** content — blocks the author
  /// (hides their content everywhere) via [BlockService].
  final VoidCallback? onBlockUser;

  /// Shown in the 3-dot menu for **other users'** content — opens the report
  /// sheet for the author via [ReportUserSheet].
  final VoidCallback? onReportUser;

  const LibraryContentCard({
    super.key,
    required this.content,
    this.progress = 0.0,
    this.isAdded = false,
    this.onTap,
    this.onAdd,
    this.onEditLanguages,
    this.onDelete,
    this.onEdit,
    this.onBlockUser,
    this.onReportUser,
  });

  @override
  State<LibraryContentCard> createState() => _LibraryContentCardState();
}

class _LibraryContentCardState extends State<LibraryContentCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final type = widget.content.type;
    final accentColor = type.accentColor;

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
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 128),
              child: Row(
                children: [
                  // ── Vertical accent bar ───────────────────────────
                  Container(width: 4, color: accentColor),

                  // ── Square thumbnail ──────────────────────────────
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: 82,
                        height: 82,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ContentThumbnail(content: widget.content),
                            // Type badge (top-left)
                            Positioned(
                              top: 4,
                              left: 4,
                              child: _buildMiniBadge(type),
                            ),
                            // Duration badge (bottom-right, for videos)
                            if (type == ContentType.youtube)
                              Positioned(
                                bottom: 4,
                                right: 4,
                                child: _buildDurationBadge(),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ── Content info ──────────────────────────────────
                  Flexible(
                    fit: FlexFit.loose,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title + 3-dot menu
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  widget.content.title,
                                  style: GoogleFonts.nunito(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (widget.onEdit != null ||
                                  widget.onDelete != null ||
                                  widget.onBlockUser != null ||
                                  widget.onReportUser != null)
                                _buildMenuButton(context, isDark)
                              else
                                const SizedBox(width: 8),
                            ],
                          ),
                          const SizedBox(height: 2),

                          // Author name (if available)
                          if (widget.content.authorName.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                widget.content.authorName,
                                style: GoogleFonts.nunito(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF4ECDC4),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),

                          // Description (1 line)
                          Text(
                            widget.content.description.isNotEmpty
                                ? widget.content.description
                                : '',
                            style: GoogleFonts.nunito(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white38 : Colors.black45,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),

                          // Tags row — constrained height, scrolls if needed
                          if (widget.content.tags.isNotEmpty)
                            SizedBox(
                              height: 26,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    ...widget.content.tags
                                        .take(3)
                                        .map(
                                          (tag) => Padding(
                                            padding: const EdgeInsets.only(
                                              right: 6,
                                            ),
                                            child: TagPill(
                                              label: tag,
                                              isCompact: true,
                                            ),
                                          ),
                                        ),
                                    if (widget.content.tags.length > 3)
                                      TagPill(
                                        label:
                                            '+${widget.content.tags.length - 3}',
                                        isCompact: true,
                                      ),
                                  ],
                                ),
                              ),
                            )
                          else
                            const SizedBox(height: 12),

                          // Progress bar
                          if (widget.progress > 0)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: widget.progress.clamp(0.0, 1.0),
                                        minHeight: 4,
                                        backgroundColor: isDark
                                            ? Colors.white.withValues(
                                                alpha: 0.10,
                                              )
                                            : Colors.black.withValues(
                                                alpha: 0.06,
                                              ),
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              widget.content.type.accentColor,
                                            ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${(widget.progress * 100).toInt()}%',
                                    style: GoogleFonts.nunito(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.white38
                                          : Colors.black38,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Bottom meta + Add/Added
                          Row(
                            children: [
                              const Spacer(),
                              if (!widget.isAdded && widget.onAdd != null)
                                _buildAddButton(context, isDark)
                              else if (widget.isAdded)
                                _buildAddedIndicator(context, isDark),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Thumbnail badges ──────────────────────────────────────────

  Widget _buildMiniBadge(ContentType type) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(type.icon, color: type.accentColor, size: 9),
              const SizedBox(width: 3),
              Text(
                type.displayName,
                style: GoogleFonts.nunito(
                  fontSize: 8,
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

  Widget _buildDurationBadge() {
    final metadata = widget.content.metadata;
    final durationSeconds = metadata?['duration_seconds'] as int?;
    if (durationSeconds == null) return const SizedBox.shrink();

    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    final label =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.play_arrow_rounded,
                size: 10,
                color: Colors.white,
              ),
              const SizedBox(width: 2),
              Text(
                label,
                style: GoogleFonts.nunito(
                  fontSize: 9,
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

  // ─── Add / Added buttons ───────────────────────────────────────

  Widget _buildAddButton(BuildContext context, bool isDark) {
    return GestureDetector(
      onTap: widget.onAdd,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF4ECDC4).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: const Color(0xFF4ECDC4).withValues(alpha: 0.3),
          ),
        ),
        child: const Icon(
          Icons.add_rounded,
          size: 14,
          color: Color(0xFF4ECDC4),
        ),
      ),
    );
  }

  Widget _buildAddedIndicator(BuildContext context, bool isDark) {
    return GestureDetector(
      onTap: widget.onEditLanguages,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF2ECC71).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(
          Icons.check_rounded,
          size: 12,
          color: Color(0xFF2ECC71),
        ),
      ),
    );
  }

  // ─── Menu button ───────────────────────────────────────────────

  Widget _buildMenuButton(BuildContext context, bool isDark) {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
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
      child: SizedBox(
        width: 24,
        height: 24,
        child: Icon(
          Icons.more_horiz_rounded,
          size: 18,
          color: isDark ? Colors.white38 : Colors.black38,
        ),
      ),
    );
  }
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
