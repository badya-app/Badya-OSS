import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

enum CardLayout { list, horizontal, square }

class UnifiedImportCard extends StatefulWidget {
  final String title;
  final String description;
  final double? progress;
  final String? imagePath;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onRename;
  final VoidCallback? onMove;
  final VoidCallback? onRetry;
  final bool isNetworkImage;
  final String? duration;
  final String? language;
  final String? fileSize;
  final String? openedDate;
  final String status;
  final String? transcriptQuality;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onLongPress;
  final VoidCallback? onSelectionToggle;
  final CardLayout layout;

  const UnifiedImportCard({
    super.key,
    required this.title,
    required this.description,
    this.progress,
    this.imagePath,
    this.color = Colors.teal,
    required this.onTap,
    this.onDelete,
    this.onRename,
    this.onMove,
    this.onRetry,
    this.isNetworkImage = false,
    this.duration,
    this.language,
    this.fileSize,
    this.openedDate,
    this.status = 'ready',
    this.transcriptQuality,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onLongPress,
    this.onSelectionToggle,
    this.layout = CardLayout.list,
  });

  @override
  State<UnifiedImportCard> createState() => _UnifiedImportCardState();
}

class _UnifiedImportCardState extends State<UnifiedImportCard>
    with SingleTickerProviderStateMixin {
  bool _isPressed = false;

  bool get _isProcessing => widget.status == 'processing';
  bool get _isFailed => widget.status == 'failed';

  @override
  Widget build(BuildContext context) {
    switch (widget.layout) {
      case CardLayout.list:
        return _buildListCard(context);
      case CardLayout.horizontal:
        return _buildHorizontalCard(context);
      case CardLayout.square:
        return _buildSquareCard(context);
    }
  }

  // ─── List Card Layout ──────────────────────────────────────────────────

  Widget _buildListCard(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;
    final Color effectiveColor = _effectiveColor(isDark);

    Widget cardBody = GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.isSelectionMode ? widget.onSelectionToggle : widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _isPressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? (isDark
                      ? Colors.teal.withValues(alpha: 0.2)
                      : Colors.teal.withValues(alpha: 0.1))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.isSelected ? Colors.teal : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (widget.isSelectionMode)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Icon(
                        widget.isSelected
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                        color: widget.isSelected
                            ? Colors.teal
                            : (isDark ? Colors.white38 : Colors.black26),
                        size: 24,
                      ),
                    ),
                  _buildThumbnail(context, 80, 80),
                  const SizedBox(width: 16),
                  Expanded(
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
                                style: textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 17,
                                  color: theme.brightness == Brightness.dark
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (!widget.isSelectionMode)
                              _buildMenu(context, isDark),
                          ],
                        ),
                        const SizedBox(height: 2),
                        _buildListMetaRow(
                          context,
                          textTheme,
                          isDark,
                          effectiveColor,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_isProcessing) ...[
                const SizedBox(height: 8),
                _buildProcessingBar(isDark),
              ],
              if (_isFailed) ...[
                const SizedBox(height: 6),
                _buildFailedHint(context),
              ],
            ],
          ),
        ),
      ),
    );

    if (_isProcessing) {
      cardBody = cardBody
          .animate(onPlay: (c) => c.repeat())
          .shimmer(
            duration: 1600.ms,
            color: (isDark ? Colors.white : Colors.black).withValues(
              alpha: 0.04,
            ),
          );
    }

    return cardBody;
  }

  Widget _buildListMetaRow(
    BuildContext context,
    TextTheme textTheme,
    bool isDark,
    Color effectiveColor,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (widget.duration != null && widget.duration!.isNotEmpty) ...[
            Text(
              widget.duration!,
              style: textTheme.bodySmall?.copyWith(
                color: (isDark ? Colors.white : Colors.black87).withValues(
                  alpha: 0.4,
                ),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              " • ",
              style: textTheme.bodySmall?.copyWith(
                color: (isDark ? Colors.white : Colors.black87).withValues(
                  alpha: 0.2,
                ),
              ),
            ),
          ],
          if (widget.fileSize != null && widget.fileSize!.isNotEmpty) ...[
            Text(
              widget.fileSize!,
              style: textTheme.bodySmall?.copyWith(
                color: (isDark ? Colors.white : Colors.black87).withValues(
                  alpha: 0.4,
                ),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              "  •  ",
              style: textTheme.bodySmall?.copyWith(
                color: (isDark ? Colors.white : Colors.black87).withValues(
                  alpha: 0.2,
                ),
              ),
            ),
          ],
          _buildStatusBadge(textTheme, effectiveColor),
          if (widget.language != null && widget.language!.isNotEmpty) ...[
            const SizedBox(width: 8),
            _buildTypeBadge(),
          ],
          if (widget.language == 'VIDEO' &&
              widget.transcriptQuality != null &&
              widget.transcriptQuality != 'none') ...[
            const SizedBox(width: 6),
            _buildTranscriptBadge(),
          ],
        ],
      ),
    );
  }

  // ─── Horizontal Card Layout ────────────────────────────────────────────

  Widget _buildHorizontalCard(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color effectiveColor = _effectiveColor(isDark);

    final String? displayLabel =
        (widget.duration != null && widget.duration!.isNotEmpty)
        ? widget.duration
        : (widget.fileSize != null && widget.fileSize!.isNotEmpty
              ? widget.fileSize
              : null);

    return GestureDetector(
      onTap: widget.isSelectionMode ? widget.onSelectionToggle : widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF1E1E1E)
              : Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: widget.isSelected
                ? const Color(0xFF4ECDC4)
                : (isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.08)),
            width: widget.isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                _buildThumbnail(context, 90, 90),
                if (displayLabel != null)
                  Positioned(
                    bottom: 6,
                    left: 6,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          color: Colors.black.withValues(alpha: 0.35),
                          child: Text(
                            displayLabel,
                            style: GoogleFonts.nunito(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (widget.isSelected)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Color(0xFF4ECDC4),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    style: GoogleFonts.nunito(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Flexible(child: _buildProgressBadge(effectiveColor)),
                      const SizedBox(width: 6),
                      if (widget.language != null &&
                          widget.language!.isNotEmpty)
                        _buildTypeBadge(),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          widget.openedDate ?? 'Never opened',
                          style: GoogleFonts.nunito(
                            fontSize: 11,
                            color: (isDark ? Colors.white : Colors.black87)
                                .withValues(alpha: 0.4),
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        height: 24,
                        width: 24,
                        child: Material(
                          color: Colors.transparent,
                          child: PopupMenuButton<String>(
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              Icons.more_horiz_rounded,
                              size: 18,
                              color: (isDark ? Colors.white : Colors.black87)
                                  .withValues(alpha: 0.3),
                            ),
                            onSelected: (value) {
                              if (value == 'rename') widget.onRename?.call();
                              if (value == 'delete') widget.onDelete?.call();
                              if (value == 'move') widget.onMove?.call();
                            },
                            itemBuilder: (context) => [
                              _menuItem(
                                'rename',
                                Icons.edit_rounded,
                                'Rename',
                                isDark,
                              ),
                              _menuItem(
                                'move',
                                Icons.drive_file_move_rounded,
                                'Move',
                                isDark,
                              ),
                              _menuItem(
                                'delete',
                                Icons.delete_outline_rounded,
                                'Delete',
                                isDark,
                                isDestructive: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Square Card Layout ────────────────────────────────────────────────

  Widget _buildSquareCard(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: widget.onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  Positioned.fill(child: _buildCardImage()),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Material(
                      color: Colors.transparent,
                      child: PopupMenuButton<String>(
                        icon: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.4),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.more_horiz_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        onSelected: (value) {
                          if (value == 'rename') widget.onRename?.call();
                          if (value == 'delete') widget.onDelete?.call();
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'rename',
                            child: Row(
                              children: [
                                Icon(Icons.edit_rounded, size: 18),
                                SizedBox(width: 8),
                                Text('Rename'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                  color: Colors.red,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Delete',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: GoogleFonts.nunito(
                    color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (widget.duration != null)
                      Flexible(
                        child: Text(
                          widget.duration!,
                          style: GoogleFonts.nunito(
                            color: (isDark ? Colors.white : Colors.black87)
                                .withValues(alpha: 0.5),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (widget.duration != null && widget.language != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: Icon(
                          Icons.circle,
                          size: 3,
                          color: (isDark ? Colors.white : Colors.black)
                              .withValues(alpha: 0.2),
                        ),
                      ),
                    if (widget.language != null)
                      Text(
                        widget.language!.toUpperCase(),
                        style: GoogleFonts.nunito(
                          color: _typeBadgeColor(),
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Shared Sub-Widgets ────────────────────────────────────────────────

  Widget _buildThumbnail(BuildContext context, double width, double height) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(width: width, height: height, child: _buildCardImage()),
    );
  }

  Widget _buildCardImage() {
    final hasValidNetwork =
        widget.isNetworkImage &&
        widget.imagePath != null &&
        !widget.imagePath!.contains('portrait.png');
    final hasValidAsset =
        widget.imagePath != null && !widget.imagePath!.contains('portrait.png');

    if (hasValidNetwork) {
      return Image.network(
        widget.imagePath!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
      );
    } else if (hasValidAsset) {
      return Image.asset(
        widget.imagePath!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    final bool isVideo = widget.language == 'VIDEO';
    final bool isText = widget.language == 'TEXT';

    final Color iconColor = isVideo
        ? const Color(0xFFFF6B6B)
        : (isText ? const Color(0xFF4ECDC4) : const Color(0xFF9D8CF2));

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.02)
            : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: iconColor.withValues(alpha: 0.12),
          width: 0.8,
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            iconColor.withValues(alpha: 0.08),
            iconColor.withValues(alpha: 0.01),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          isVideo
              ? Icons.videocam_rounded
              : (isText
                    ? Icons.sticky_note_2_rounded
                    : Icons.insert_drive_file_rounded),
          color: iconColor.withValues(alpha: 0.4),
          size: 32,
        ),
      ),
    );
  }

  Widget _buildMenu(BuildContext context, bool isDark) {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      icon: Icon(
        Icons.more_horiz,
        color:
            (Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black54)
                .withValues(alpha: 0.6),
        size: 20,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (value) {
        if (value == 'rename') widget.onRename?.call();
        if (value == 'move') widget.onMove?.call();
        if (value == 'delete') widget.onDelete?.call();
        if (value == 'retry') widget.onRetry?.call();
      },
      itemBuilder: (BuildContext context) => [
        if (_isFailed)
          PopupMenuItem<String>(
            value: 'retry',
            child: Row(
              children: [
                Icon(
                  Icons.refresh_rounded,
                  size: 20,
                  color: isDark ? Colors.tealAccent : Colors.teal,
                ),
                const SizedBox(width: 12),
                Text(
                  'Retry',
                  style: GoogleFonts.raleway(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.tealAccent : Colors.teal,
                  ),
                ),
              ],
            ),
          ),
        _menuItem('rename', Icons.edit_rounded, 'Rename', isDark),
        _menuItem('move', Icons.drive_file_move_rounded, 'Move', isDark),
        _menuItem(
          'delete',
          Icons.delete_outline_rounded,
          'Delete',
          isDark,
          isDestructive: true,
        ),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label,
    bool isDark, {
    bool isDestructive = false,
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: isDestructive
                ? Colors.redAccent
                : (isDark ? Colors.white70 : Colors.black54),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: GoogleFonts.raleway(
              fontWeight: FontWeight.w600,
              color: isDestructive ? Colors.redAccent : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(TextTheme textTheme, Color effectiveColor) {
    final bool hasProgress =
        widget.progress != null &&
        widget.progress! > 0 &&
        widget.progress! < 0.995;

    if (widget.progress != null &&
        widget.progress! > 0 &&
        widget.progress! < 0.995) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              value: widget.progress,
              strokeWidth: 2.5,
              backgroundColor: effectiveColor.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(effectiveColor),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            "${(widget.progress! * 100).toInt()}%",
            style: textTheme.bodySmall?.copyWith(
              color: effectiveColor,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isProcessing
                ? Icons.hourglass_top_rounded
                : (_isFailed
                      ? Icons.error_outline_rounded
                      : Icons.menu_book_rounded),
            size: 11,
            color: _isFailed ? Colors.redAccent : effectiveColor,
          ),
          const SizedBox(width: 4),
          Text(
            widget.description,
            style: TextStyle(
              color: _isFailed ? Colors.redAccent : effectiveColor,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBadge(Color effectiveColor) {
    if (widget.progress != null &&
        widget.progress! > 0 &&
        widget.progress! < 0.995) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              value: widget.progress,
              strokeWidth: 2.5,
              backgroundColor: effectiveColor.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(effectiveColor),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            "${(widget.progress! * 100).toInt()}%",
            style: GoogleFonts.nunito(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: effectiveColor,
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.menu_book_rounded, size: 11, color: effectiveColor),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              widget.description,
              style: GoogleFonts.nunito(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: effectiveColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeBadge() {
    final isV = widget.language == 'VIDEO';
    final isT = widget.language == 'TEXT';
    final Color tagColor = _typeBadgeColor();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tagColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tagColor.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isV
                ? Icons.play_circle_fill_rounded
                : (isT
                      ? Icons.sticky_note_2_rounded
                      : Icons.description_rounded),
            size: 11,
            color: tagColor,
          ),
          const SizedBox(width: 4),
          Text(
            widget.language!.toUpperCase(),
            style: TextStyle(
              color: tagColor,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTranscriptBadge() {
    final bool isManual = widget.transcriptQuality == 'manual';
    final Color badgeColor = isManual
        ? const Color(0xFF43E97B)
        : const Color(0xFFF7B731);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: badgeColor.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isManual
                ? Icons.verified_rounded
                : Icons.auto_awesome_mosaic_rounded,
            size: 9,
            color: badgeColor,
          ),
          const SizedBox(width: 3),
          Text(
            isManual ? 'Manual CC' : 'Auto CC',
            style: TextStyle(
              color: badgeColor,
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingBar(bool isDark) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: null,
        minHeight: 3,
        backgroundColor: (isDark ? Colors.white : Colors.blueGrey).withValues(
          alpha: 0.1,
        ),
        valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueGrey),
      ),
    );
  }

  Widget _buildFailedHint(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: 4),
        const Icon(
          Icons.info_outline_rounded,
          size: 12,
          color: Colors.redAccent,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            'Import failed — tap ••• › Retry to try again',
            style: GoogleFonts.nunito(
              fontSize: 11,
              color: Colors.redAccent.withValues(alpha: 0.8),
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ─── Helpers ───────────────────────────────────────────────────────────

  Color _effectiveColor(bool isDark) {
    final Color c = widget.color;
    if (isDark && c == Colors.teal) return Colors.tealAccent;
    if (isDark) return c;
    if (c == Colors.teal) return Colors.teal.shade700;
    return c;
  }

  Color _typeBadgeColor() {
    if (widget.language == 'VIDEO') return const Color(0xFFFF6B6B);
    if (widget.language == 'TEXT') return const Color(0xFF4ECDC4);
    return const Color(0xFF9D8CF2);
  }
}
