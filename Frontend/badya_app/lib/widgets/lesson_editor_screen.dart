import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:Badya/services/content_service.dart';
import 'package:Badya/utils/ui_utils.dart';
import 'package:Badya/widgets/segmentation_selector.dart';

/// Full-screen editor for modifying lessons within an import.
///
/// Implements CoW (Copy-on-Write) editing:
/// - Each lesson can be expanded to edit title and text content
/// - Saving a lesson sets `has_custom_lessons = true` on the parent import
/// - "Reset to original" re-reads raw text and re-segments from scratch
/// - "Re-Segment" allows changing the segmentation method entirely
class LessonEditorScreen extends StatefulWidget {
  final String importId;
  final String contentId;
  final String title;

  const LessonEditorScreen({
    super.key,
    required this.importId,
    required this.contentId,
    this.title = 'Edit Lessons',
  });

  /// Push this screen onto the navigator.
  static Future<void> navigate({
    required BuildContext context,
    required String importId,
    required String contentId,
    String title = 'Edit Lessons',
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LessonEditorScreen(
          importId: importId,
          contentId: contentId,
          title: title,
        ),
      ),
    );
  }

  @override
  State<LessonEditorScreen> createState() => _LessonEditorScreenState();
}

class _LessonEditorScreenState extends State<LessonEditorScreen> {
  final ContentService _contentService = ContentService();
  final Map<String, TextEditingController> _titleControllers = {};
  final Map<String, TextEditingController> _contentControllers = {};
  final Set<String> _savedLessons = {};
  final Set<String> _modifiedLessons = {};
  bool _isResetting = false;
  bool _isReSegmenting = false;

  /// Track original values for detecting changes
  final Map<String, String> _originalTitles = {};
  final Map<String, String> _originalContents = {};

  /// Cached current lessons for orderIndex lookup during saves.
  List<Map<String, dynamic>> _currentLessons = [];

  @override
  void dispose() {
    for (final c in _titleControllers.values) {
      c.dispose();
    }
    for (final c in _contentControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Get the orderIndex from a lesson segment map.
  int _orderIndex(Map<String, dynamic> lesson) {
    return (lesson['order_index'] as num?)?.toInt() ?? 0;
  }

  void _initControllers(List<Map<String, dynamic>> lessons) {
    for (final lesson in lessons) {
      final id = lesson['id'] as String;
      if (!_titleControllers.containsKey(id)) {
        final title = lesson['title'] as String? ?? '';
        final content = lesson['text_content'] as String? ?? '';
        _titleControllers[id] = TextEditingController(text: title);
        _contentControllers[id] = TextEditingController(text: content);
        _originalTitles[id] = title;
        _originalContents[id] = content;
      }
    }
  }

  void _markModified(String lessonId) {
    if (!_modifiedLessons.contains(lessonId)) {
      setState(() => _modifiedLessons.add(lessonId));
    }
  }

  bool _hasChanges(String lessonId) {
    final tc = _titleControllers[lessonId];
    final cc = _contentControllers[lessonId];
    if (tc == null || cc == null) return false;
    return tc.text != (_originalTitles[lessonId] ?? '') ||
        cc.text != (_originalContents[lessonId] ?? '');
  }

  Future<void> _saveLesson(String lessonId, int orderIndex) async {
    final title = _titleControllers[lessonId]?.text ?? '';
    final content = _contentControllers[lessonId]?.text ?? '';

    // Skip if nothing changed
    if (!_hasChanges(lessonId)) return;

    try {
      await _contentService.updateLessonOverride(
        contentId: widget.contentId,
        orderIndex: orderIndex,
        title: title,
        textContent: content,
      );
      // Update originals so subsequent saves don't re-save unchanged fields
      _originalTitles[lessonId] = title;
      _originalContents[lessonId] = content;
      setState(() {
        _savedLessons.add(lessonId);
        _modifiedLessons.remove(lessonId);
      });
      if (mounted) {
        UiUtils.showTopNotification(context, 'Lesson saved', type: NotificationType.success);
      }
    } catch (e) {
      if (mounted) {
        UiUtils.showErrorSnackbar(context, 'Failed to save: $e');
      }
    }
  }

  Future<void> _saveAllModified() async {
    final lessonIds = List<String>.from(_modifiedLessons);
    if (lessonIds.isEmpty) {
      UiUtils.showTopNotification(context, 'No changes to save', type: NotificationType.info);
      return;
    }

    // Map lessonId to current segment data to get orderIndex
    final currentLessons = _currentLessons;
    for (final id in lessonIds) {
      final lesson = currentLessons.firstWhere(
        (l) => l['id'] == id,
        orElse: () => <String, dynamic>{},
      );
      final orderIndex = _orderIndex(lesson);
      await _saveLesson(id, orderIndex);
    }

    if (mounted) {
      UiUtils.showTopNotification(context, 'All lessons saved', type: NotificationType.success);
    }
  }

  Future<void> _resetToOriginal() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Reset lessons?',
            style: GoogleFonts.nunito(
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          content: Text(
            'This will discard all your edits and re-generate lessons from the original content.',
            style: GoogleFonts.nunito(
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Cancel',
                style: GoogleFonts.nunito(
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Reset',
                style: GoogleFonts.nunito(
                  fontWeight: FontWeight.w700,
                  color: Colors.redAccent,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isResetting = true);

    try {
      await _contentService.updateSegmentationPreference(
        contentId: widget.contentId,
        segmentBy: 'words',
      );
      await _contentService.clearLegacySegments(widget.contentId);
      await _contentService.clearLessonOverrides(widget.contentId);

      // Clear cached controllers so they get rebuilt from fresh data
      for (final c in _titleControllers.values) {
        c.dispose();
      }
      for (final c in _contentControllers.values) {
        c.dispose();
      }
      _titleControllers.clear();
      _contentControllers.clear();
      _originalTitles.clear();
      _originalContents.clear();
      _savedLessons.clear();
      _modifiedLessons.clear();

      if (mounted) {
        UiUtils.showTopNotification(context, 'Lessons reset to original', type: NotificationType.success);
      }
    } catch (e) {
      if (mounted) {
        UiUtils.showErrorSnackbar(context, 'Failed to reset: $e');
      }
    } finally {
      if (mounted) setState(() => _isResetting = false);
    }
  }

  Future<void> _onReSegment() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Check if chapters metadata is available
    final content = await _contentService.getContent(widget.contentId);
    final chapters = content?.metadata?['chapters'];
    final hasChapters = chapters is List && chapters.isNotEmpty;

    if (!mounted) return;
    final result = await showModalBottomSheet<SegmentationSelection>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: _ReSegmentEditorSheet(
            hasChapters: hasChapters,
            onReSegment: (segmentBy, segmentValue) async {
              Navigator.pop(ctx);
              await _performReSegment(segmentBy, segmentValue);
            },
          ),
        ),
      ),
    );

    if (result != null && mounted) {
      await _performReSegment(result.segmentBy, result.segmentValue);
    }
  }

  Future<void> _performReSegment(String segmentBy, int? segmentValue) async {
    setState(() => _isReSegmenting = true);

    try {
      await _contentService.updateSegmentationPreference(
        contentId: widget.contentId,
        segmentBy: segmentBy,
        segmentValue: segmentValue,
      );

      // Clear cached controllers so they get rebuilt from fresh data
      for (final c in _titleControllers.values) {
        c.dispose();
      }
      for (final c in _contentControllers.values) {
        c.dispose();
      }
      _titleControllers.clear();
      _contentControllers.clear();
      _originalTitles.clear();
      _originalContents.clear();
      _savedLessons.clear();
      _modifiedLessons.clear();
      _currentLessons = [];

      if (mounted) {
        UiUtils.showTopNotification(context, 'Lessons re-segmented successfully', type: NotificationType.success);
      }
    } catch (e) {
      if (mounted) {
        UiUtils.showErrorSnackbar(context, 'Failed to re-segment: $e');
      }
    } finally {
      if (mounted) setState(() => _isReSegmenting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final modifiedCount = _modifiedLessons.length;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFFDF4DD),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFFDF4DD),
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.title,
          style: GoogleFonts.nunito(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        actions: [
          // Save All button (only visible when there are unsaved changes)
          if (modifiedCount > 0)
            Center(
              child: GestureDetector(
                onTap: _saveAllModified,
                child: Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4ECDC4).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF4ECDC4).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.save_rounded,
                        size: 16,
                        color: Color(0xFF4ECDC4),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Save All ($modifiedCount)',
                        style: GoogleFonts.nunito(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF4ECDC4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Re-Segment button
          if (!_isReSegmenting)
            IconButton(
              icon: const Icon(
                Icons.change_circle_rounded,
                color: Colors.blueAccent,
              ),
              tooltip: 'Re-segment',
              onPressed: _onReSegment,
            ),
          const SizedBox(width: 4),
          // Reset button
          IconButton(
            icon: _isResetting
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  )
                : Icon(
                    Icons.refresh_rounded,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
            tooltip: 'Reset to original',
            onPressed: _isResetting ? null : _resetToOriginal,
          ),
        ],
      ),        body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _contentService.getContentSegments(
          widget.contentId,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final lessons = snapshot.data ?? [];

          if (lessons.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.menu_book_rounded,
                    size: 64,
                    color: isDark ? Colors.white24 : Colors.black12,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No lessons available',
                    style: GoogleFonts.nunito(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white54 : Colors.black38,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Lessons are generated during content import.',
                    style: GoogleFonts.nunito(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white30 : Colors.black26,
                    ),
                  ),
                ],
              ),
            );
          }

          // Initialize controllers on first data load
          _initControllers(lessons);
          _currentLessons = lessons;

          return Column(
            children: [
              // Header info bar
              Container(
                margin: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${lessons.length} ${lessons.length == 1 ? 'lesson' : 'lessons'} — tap to expand and edit',
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  ],
                ),
              ),

              // Lesson list
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  itemCount: lessons.length,
                  itemBuilder: (context, index) {
                    final lesson = lessons[index];
                    final lessonId = lesson['id'] as String;
                    final orderIndex = _orderIndex(lesson);
                    final title = lesson['title'] as String? ?? 'Part ${index + 1}';
                    final isSaved = _savedLessons.contains(lessonId);
                    final isModified = _modifiedLessons.contains(lessonId);

                    return _LessonTile(
                      index: index,
                      lessonId: lessonId,
                      title: title,
                      isSaved: isSaved,
                      isModified: isModified,
                      titleController: _titleControllers[lessonId]!,
                      contentController: _contentControllers[lessonId]!,
                      onChanged: () => _markModified(lessonId),
                      onSave: () => _saveLesson(lessonId, orderIndex),
                      isDark: isDark,
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Expandable lesson tile with inline editing of title and text content.
class _LessonTile extends StatefulWidget {
  final int index;
  final String lessonId;
  final String title;
  final bool isSaved;
  final bool isModified;
  final TextEditingController titleController;
  final TextEditingController contentController;
  final VoidCallback onChanged;
  final VoidCallback onSave;
  final bool isDark;

  const _LessonTile({
    required this.index,
    required this.lessonId,
    required this.title,
    required this.isSaved,
    required this.isModified,
    required this.titleController,
    required this.contentController,
    required this.onChanged,
    required this.onSave,
    required this.isDark,
  });

  @override
  State<_LessonTile> createState() => _LessonTileState();
}

class _LessonTileState extends State<_LessonTile> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: widget.isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isDark
              ? Colors.white.withValues(alpha: _isExpanded ? 0.12 : 0.06)
              : Colors.black.withValues(alpha: _isExpanded ? 0.10 : 0.06),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header — always visible
            InkWell(
              onTap: () => setState(() => _isExpanded = !_isExpanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                child: Row(
                  children: [
                    // Index badge
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4ECDC4).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          '${widget.index + 1}',
                          style: GoogleFonts.nunito(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF4ECDC4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Title
                    Expanded(
                      child: Text(
                        widget.titleController.text.isNotEmpty
                            ? widget.titleController.text
                            : widget.title,
                        style: GoogleFonts.nunito(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: widget.isDark ? Colors.white : Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Status indicators
                    if (widget.isSaved)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(
                          Icons.check_circle_rounded,
                          size: 18,
                          color: const Color(0xFF2ECC71),
                        ),
                      ),
                    if (widget.isModified)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Colors.orangeAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    AnimatedRotation(
                      turns: _isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 22,
                        color: widget.isDark
                            ? Colors.white38
                            : Colors.black38,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Expanded editor section
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Divider(
                      color: widget.isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.08),
                      height: 1,
                    ),
                    const SizedBox(height: 16),

                    // Title field
                    _buildSectionLabel('Title'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: widget.titleController,
                      onChanged: (_) => widget.onChanged(),
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color:
                            widget.isDark ? Colors.white : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: widget.isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.03),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: widget.isDark
                                ? Colors.white.withValues(alpha: 0.10)
                                : Colors.black.withValues(alpha: 0.10),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: widget.isDark
                                ? Colors.white.withValues(alpha: 0.10)
                                : Colors.black.withValues(alpha: 0.10),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFF4ECDC4),
                            width: 2,
                          ),
                        ),
                        hintText: 'Lesson title',
                        hintStyle: GoogleFonts.nunito(
                          fontWeight: FontWeight.w500,
                          color: widget.isDark
                              ? Colors.white24
                              : Colors.black26,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Content field
                    _buildSectionLabel('Content'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: widget.contentController,
                      onChanged: (_) => widget.onChanged(),
                      maxLines: null,
                      minLines: 5,
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.6,
                        color:
                            widget.isDark ? Colors.white70 : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: widget.isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.03),
                        contentPadding: const EdgeInsets.all(14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: widget.isDark
                                ? Colors.white.withValues(alpha: 0.10)
                                : Colors.black.withValues(alpha: 0.10),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: widget.isDark
                                ? Colors.white.withValues(alpha: 0.10)
                                : Colors.black.withValues(alpha: 0.10),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: Color(0xFF4ECDC4),
                            width: 2,
                          ),
                        ),
                        hintText: 'Lesson content...',
                        hintStyle: GoogleFonts.nunito(
                          fontWeight: FontWeight.w500,
                          color: widget.isDark
                              ? Colors.white24
                              : Colors.black26,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Save button
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: widget.isModified ? widget.onSave : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: widget.isModified
                                ? const Color(0xFF4ECDC4)
                                : (widget.isDark
                                    ? Colors.white.withValues(alpha: 0.06)
                                    : Colors.black.withValues(alpha: 0.04)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      widget.isSaved
                                          ? Icons.check_rounded
                                          : Icons.save_rounded,
                                      size: 16,
                                      color: widget.isModified
                                          ? Colors.white
                                          : (widget.isDark
                                              ? Colors.white24
                                              : Colors.black26),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      widget.isSaved ? 'Saved' : 'Save',
                                      style: GoogleFonts.nunito(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: widget.isModified
                                            ? Colors.white
                                            : (widget.isDark
                                                ? Colors.white24
                                                : Colors.black26),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              crossFadeState: _isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.nunito(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: widget.isDark ? Colors.white38 : Colors.black45,
        letterSpacing: 0.5,
      ),
    );
  }
}

/// Internal bottom sheet widget for re-segmenting from the lesson editor.
class _ReSegmentEditorSheet extends StatefulWidget {
  final bool hasChapters;
  final Future<void> Function(String segmentBy, int? segmentValue) onReSegment;

  const _ReSegmentEditorSheet({
    this.hasChapters = false,
    required this.onReSegment,
  });

  @override
  State<_ReSegmentEditorSheet> createState() => _ReSegmentEditorSheetState();
}

class _ReSegmentEditorSheetState extends State<_ReSegmentEditorSheet> {
  SegmentationSelection _selection = const SegmentationSelection(
    segmentBy: 'words',
    segmentValue: 500,
  );
  bool _isApplying = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Drag handle
        Center(
          child: Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.black.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Re-Segment Lessons',
          style: GoogleFonts.nunito(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'This will replace all existing lessons.',
          style: GoogleFonts.nunito(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white38 : Colors.black45,
          ),
        ),
        const SizedBox(height: 20),
        SegmentationSelector(
          sourceType: 'import',
          hasChapters: widget.hasChapters,
          initialSegmentBy: 'words',
          initialSegmentValue: 500,
          onChanged: (selection) {
            _selection = selection;
          },
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (_selection.isValid && !_isApplying)
                ? () async {
                    setState(() => _isApplying = true);
                    try {
                      await widget.onReSegment(
                        _selection.segmentBy,
                        _selection.segmentValue ?? 0,
                      );
                    } finally {
                      if (mounted) setState(() => _isApplying = false);
                    }
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4ECDC4),
              foregroundColor: Colors.black,
              disabledBackgroundColor: const Color(0xFF4ECDC4).withValues(alpha: 0.25),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
            child: _isApplying
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black87,
                    ),
                  )
                : Text(
                    'Apply',
                    style: GoogleFonts.nunito(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
