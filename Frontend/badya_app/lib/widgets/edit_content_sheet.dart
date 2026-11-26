import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:country_flags/country_flags.dart';
import 'package:http/http.dart' as http;
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:Badya/widgets/segmentation_selector.dart';
import 'package:Badya/utils/constants.dart';
import 'package:Badya/utils/ui_utils.dart';

/// A modal bottom sheet for editing basic content metadata and segmentation.
///
/// Fields: title, description, tags, thumbnail, visibility (public/private).
/// The "Segmentation" section shows lesson count, Reset, and Change Method
/// controls — the "Edit Lessons" button has been removed so users cannot
/// directly modify lesson content, only the segmentation method+value.
class EditContentSheet extends StatefulWidget {
  final String initialTitle;
  final String initialDescription;
  final List<String> initialTags;
  final List<String> initialAssignedLanguages;
  final List<String> availableLanguages;
  final bool initialIsPublic;
  final String initialDifficulty;

  /// Whether to show the Public/Private visibility toggle.
  /// Forked topics should hide this — the original creator controls visibility.
  final bool showVisibilityToggle;

  final String? initialThumbnailUrl;

  /// Callback for picking and uploading an image.
  /// Returns the download URL, or null if cancelled.
  final Future<String?> Function()? onPickImage;

  /// Number of lessons (imported content only).
  /// Shown in the segmentation section.
  final int? lessonCount;

  /// Current segmentation method name for display (e.g., 'words', 'minutes', 'none').
  final String? segmentBy;

  /// Current segmentation threshold value (e.g., 500 for words, 10 for minutes).
  final int? segmentValue;

  /// The source type for determining which segmentation options to show.
  /// Pass `'video'` for YouTube content, `'text'` for others.
  final String? sourceType;

  /// Whether chapter metadata is available (extracted by backend).
  final bool hasChapters;

  /// Triggers re-segmentation with the given method and value.
  final void Function(String segmentBy, int? segmentValue)? onReSegment;

  const EditContentSheet({
    super.key,
    required this.initialTitle,
    required this.initialDescription,
    this.initialTags = const [],
    this.initialAssignedLanguages = const [],
    this.availableLanguages = const [],
    this.initialIsPublic = false,
    this.initialDifficulty = 'intermediate',
    this.showVisibilityToggle = true,
    this.initialThumbnailUrl,
    this.onPickImage,
    this.lessonCount,
    this.segmentBy,
    this.segmentValue,
    this.sourceType,
    this.hasChapters = false,
    this.onReSegment,
  });

  /// Show the edit content bottom sheet.
  static Future<ContentEditResult?> show({
    required BuildContext context,
    required String title,
    String description = '',
    List<String> tags = const [],
    List<String> initialAssignedLanguages = const [],
    List<String> availableLanguages = const [],
    bool isPublic = false,
    String initialDifficulty = 'intermediate',
    bool showVisibilityToggle = true,
    String? initialThumbnailUrl,
    Future<String?> Function()? onPickImage,
    int? lessonCount,
    String? segmentBy,
    int? segmentValue,
    String? sourceType,
    bool hasChapters = false,
    void Function(String segmentBy, int? segmentValue)? onReSegment,
  }) {
    return showModalBottomSheet<ContentEditResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => EditContentSheet(
        initialTitle: title,
        initialDescription: description,
        initialTags: tags,
        initialAssignedLanguages: initialAssignedLanguages,
        availableLanguages: availableLanguages,
        initialIsPublic: isPublic,
        initialDifficulty: initialDifficulty,
        showVisibilityToggle: showVisibilityToggle,
        initialThumbnailUrl: initialThumbnailUrl,
        onPickImage: onPickImage,
        lessonCount: lessonCount,
        segmentBy: segmentBy,
        segmentValue: segmentValue,
        sourceType: sourceType,
        hasChapters: hasChapters,
        onReSegment: onReSegment,
      ),
    );
  }

  @override
  State<EditContentSheet> createState() => _EditContentSheetState();
}

class _EditContentSheetState extends State<EditContentSheet> {
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _tagInputController;
  late List<String> _tags;
  late Set<String> _selectedLanguages;
  late bool _isPublic;
  late String _selectedDifficulty;
  String? _thumbnailUrl;
  bool _isUploadingThumbnail = false;
  bool _thumbnailChanged = false;

  // Segmentation state — initialized from the widget and updated in place
  // after a re-segment so the sheet can stay open with the new selection.
  String? _segmentBy;
  int? _segmentValue;
  int? _lessonCount;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _descriptionController = TextEditingController(
      text: widget.initialDescription,
    );
    _tagInputController = TextEditingController();
    _tags = List.from(widget.initialTags);
    _selectedLanguages = Set.from(widget.initialAssignedLanguages);
    _isPublic = widget.initialIsPublic;
    _selectedDifficulty = widget.initialDifficulty;
    _thumbnailUrl = widget.initialThumbnailUrl;
    _segmentBy = widget.segmentBy;
    _segmentValue = widget.segmentValue;
    _lessonCount = widget.lessonCount;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _tagInputController.dispose();
    super.dispose();
  }

  void _addTag() {
    final tag = _tagInputController.text.trim();
    if (tag.isEmpty || _tags.contains(tag)) return;
    setState(() {
      _tags.add(tag);
      _tagInputController.clear();
    });
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
    });
  }

  Future<void> _onChangeThumbnail() async {
    final result = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final hasThumbnail =
            _thumbnailUrl != null && _thumbnailUrl!.isNotEmpty;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(24),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Thumbnail',
                style: GoogleFonts.nunito(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 16),

              // ── Choose from Gallery ─────────────────────────────────
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4ECDC4).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.photo_library_rounded,
                    color: Color(0xFF4ECDC4),
                  ),
                ),
                title: Text(
                  'Choose from Gallery',
                  style: GoogleFonts.nunito(fontWeight: FontWeight.w700),
                ),
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
              // ── Save to Gallery ─────────────────────────────────────
              if (hasThumbnail)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.download_rounded,
                      color: Colors.blueAccent,
                    ),
                  ),
                  title: Text(
                    'Save to Gallery',
                    style: GoogleFonts.nunito(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () => Navigator.pop(ctx, 'save'),
                ),
              // ── Remove Photo ───────────────────────────────────────
              if (hasThumbnail)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.red,
                    ),
                  ),
                  title: Text(
                    'Remove Photo',
                    style: GoogleFonts.nunito(
                      fontWeight: FontWeight.w700,
                      color: Colors.red,
                    ),
                  ),
                  onTap: () => Navigator.pop(ctx, 'remove'),
                ),
            ],
          ),
        );
      },
    );

    if (result == null || !mounted) return;        switch (result) {
      case 'remove':
        setState(() {
          _thumbnailUrl = null;
          _thumbnailChanged = true;
        });
        if (mounted) {
          UiUtils.showTopNotification(
            context,
            'Thumbnail removed',
            type: NotificationType.success,
          );
        }
        break;
      case 'gallery':
        if (widget.onPickImage != null) {
          setState(() => _isUploadingThumbnail = true);
          try {
            final url = await widget.onPickImage!();
            if (mounted && url != null) {
              setState(() {
                _thumbnailUrl = url;
                _thumbnailChanged = true;
              });
              UiUtils.showTopNotification(
                context,
                'Thumbnail updated',
                type: NotificationType.success,
              );
            }
          } finally {
            if (mounted) {
              setState(() => _isUploadingThumbnail = false);
            }
          }
        }
        break;
      case 'save':
        await _saveThumbnailToGallery();
        break;
    }
  }

  /// Downloads the current thumbnail and saves it to the device gallery.
  Future<void> _saveThumbnailToGallery() async {
    final url = _thumbnailUrl;
    if (url == null || url.isEmpty) return;

    try {
      // 1. Check & request gallery access permission
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final granted = await Gal.requestAccess();
        if (!granted) {
          if (mounted) {
            UiUtils.showTopNotification(
              context,
              'Gallery access permission is required to save photos',
              type: NotificationType.error,
            );
          }
          return;
        }
      }

      Uint8List bytes;
      String extension = 'png';

      // 2. Load bytes depending on whether the thumbnail is a local asset or network URL
      if (url.startsWith('assets/')) {
        final byteData = await rootBundle.load(url);
        bytes = byteData.buffer.asUint8List();
        if (url.toLowerCase().endsWith('.jpg') || url.toLowerCase().endsWith('.jpeg')) {
          extension = 'jpg';
        } else if (url.toLowerCase().endsWith('.webp')) {
          extension = 'webp';
        }
      } else {
        final response = await http.get(Uri.parse(url)).timeout(
          const Duration(seconds: 15),
        );

        if (response.statusCode != 200) {
          if (mounted) {
            UiUtils.showTopNotification(
              context,
              'Failed to download thumbnail (${response.statusCode})',
              type: NotificationType.error,
            );
          }
          return;
        }

        bytes = response.bodyBytes;
        final contentType = response.headers['content-type']?.toLowerCase() ?? '';
        if (contentType.contains('jpeg') || contentType.contains('jpg') || url.contains('.jpg') || url.contains('.jpeg')) {
          extension = 'jpg';
        } else if (contentType.contains('webp') || url.contains('.webp')) {
          extension = 'webp';
        }
      }

      if (!mounted) return;

      // 3. Write bytes to temporary file with correct extension
      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/badya_thumbnail_${DateTime.now().millisecondsSinceEpoch}.$extension',
      );
      await file.writeAsBytes(bytes);

      // 4. Save to device gallery using Gal
      await Gal.putImage(file.path);

      // 5. Clean up temporary file
      if (await file.exists()) {
        await file.delete().catchError((_) => file);
      }

      if (mounted) {
        UiUtils.showTopNotification(
          context,
          'Thumbnail saved to gallery',
          type: NotificationType.success,
        );
      }
    } on GalException catch (e) {
      if (mounted) {
        final String message = switch (e.type) {
          GalExceptionType.accessDenied =>
            'Permission denied to save photos. Please allow gallery access in Settings.',
          GalExceptionType.notEnoughSpace =>
            'Not enough storage space to save thumbnail.',
          _ => 'Failed to save to gallery: ${e.type.message}',
        };
        UiUtils.showTopNotification(
          context,
          message,
          type: NotificationType.error,
        );
      }
    } catch (e) {
      if (mounted) {
        UiUtils.showTopNotification(
          context,
          'Failed to save: $e',
          type: NotificationType.error,
        );
      }
    }
  }

  void _onSave() {
    Navigator.pop(
      context,
      ContentEditResult(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        tags: List.from(_tags),
        assignedLanguages: _selectedLanguages.toList(),
        isPublic: _isPublic,
        difficulty: _selectedDifficulty,
        thumbnailUrl: _thumbnailUrl,
        thumbnailChanged: _thumbnailChanged,
      ),
    );
  }

  /// Human-readable summary of the current segmentation configuration.
  /// Shows the lesson count when known, plus the method label (with a
  /// sensible default when no preference has been stored yet).
  String get _segmentationSummary {
    final count = _lessonCount;
    if (count != null) {
      return '$count ${count == 1 ? 'lesson' : 'lessons'} · $_segmentMethodLabel';
    }
    return _segmentMethodLabel;
  }

  /// Human-readable segmentation method label. Falls back to the default
  /// word-based behaviour used by `ContentSegmenter` when no `segment_by`
  /// preference has been stored (e.g. forked imported content).
  String get _segmentMethodLabel {
    switch (_segmentBy) {
      case 'words':
        return 'Word-based';
      case 'minutes':
        return 'Time-based';
      case 'chapters':
        return 'Chapter-based';
      case 'none':
        return 'Default (whole content)';
      default:
        return 'Default (word-based)';
    }
  }

  Future<void> _onReSegment() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
        child: _ReSegmentSheet(
          sourceType: widget.sourceType ?? 'text',
          hasChapters: widget.hasChapters,
          initialSegmentBy: _segmentBy ?? 'none',
          initialSegmentValue: _segmentValue,
        ),
      ),
    );

    if (result != null && mounted && widget.onReSegment != null) {
      // Keep the sheet open and reflect the new selection locally, then
      // notify the parent so it can persist the preference and refresh.
      setState(() {
        _segmentBy = result.segmentBy;
        _segmentValue = result.segmentValue;
        // The stored lesson count is now stale — the parent recalculates it
        // in Firestore; hide it rather than showing an outdated number.
        _lessonCount = null;
      });
      widget.onReSegment!(result.segmentBy, result.segmentValue ?? 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
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
              ),

              // Title
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
                child: Text(
                  'Edit Content',
                  style: GoogleFonts.nunito(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 4),

              // ─── Thumbnail section ────────────────────────────────────
              _buildThumbnailSection(isDark),

              // ─── Title field ──────────────────────────────────────────
              _buildSectionLabel('Title'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildTextField(
                  controller: _titleController,
                  hint: 'Content title',
                  maxLines: 1,
                  isDark: isDark,
                ),
              ),

              // ─── Description field ────────────────────────────────────
              const SizedBox(height: 8),
              _buildSectionLabel('Description'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildTextField(
                  controller: _descriptionController,
                  hint: 'Add a description...',
                  maxLines: 3,
                  isDark: isDark,
                ),
              ),

              // ─── Tags ─────────────────────────────────────────────────
              const SizedBox(height: 8),
              _buildSectionLabel('Tags'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_tags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: _tags.map((tag) => Chip(
                            label: Text(
                              tag,
                              style: GoogleFonts.nunito(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            deleteIcon: Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: isDark ? Colors.white38 : Colors.black38,
                            ),
                            onDeleted: () => _removeTag(tag),
                            backgroundColor: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.05),
                            side: BorderSide.none,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          )).toList(),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _tagInputController,
                            hint: 'Add tag...',
                            maxLines: 1,
                            isDark: isDark,
                            onSubmitted: (_) => _addTag(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _addTag,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFF4ECDC4).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              color: Color(0xFF4ECDC4),
                              size: 22,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ─── Language Assignment ────────────────────────────────────
              if (widget.availableLanguages.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildSectionLabel('Assign to languages'),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildLanguageSelector(isDark),
                ),
                const SizedBox(height: 8),
              ],

              // ─── Visibility toggle ────────────────────────────────────
              if (widget.showVisibilityToggle) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.04)
                          : Colors.black.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.06),
                      ),
                    ),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Public',
                        style: GoogleFonts.nunito(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      activeTrackColor: const Color(0xFF4ECDC4),
                      value: _isPublic,
                      onChanged: (v) => setState(() {
                        _isPublic = v;
                      }),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // ─── Difficulty selector ────────────────────────────────────
              const SizedBox(height: 8),
              _buildSectionLabel('Difficulty level'),
              const SizedBox(height: 6),
              _buildDifficultySelector(isDark),
              const SizedBox(height: 8),

              // ─── Segmentation section ────────────────────────────────
              // Shown whenever re-segmentation is allowed (all non-AI
              // content), even when lessonCount/segmentBy were never set
              // (e.g. forked imported content before this plan).
              if (widget.onReSegment != null) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF2D2D2D)
                          : const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.06),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Section header
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFF4ECDC4).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.segment_rounded,
                                size: 18,
                                color: Color(0xFF4ECDC4),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Segmentation',
                              style: GoogleFonts.nunito(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Current segmentation info — method label always
                        // shown (with lesson count when known) so content
                        // with a null lessonCount still communicates its
                        // configuration.
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Icon(
                                Icons.menu_book_rounded,
                                size: 14,
                                color: isDark ? Colors.white38 : Colors.black38,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _segmentationSummary,
                                style: GoogleFonts.nunito(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white54 : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Configure Segmentation button
                        if (widget.onReSegment != null)
                          GestureDetector(
                            onTap: _onReSegment,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.blue.withValues(alpha: 0.15),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.tune_rounded,
                                    size: 15,
                                    color: Colors.blueAccent,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Configure Segmentation',
                                    style: GoogleFonts.nunito(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.blueAccent,
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
                const SizedBox(height: 8),
              ],

              // ─── Save button ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _onSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4ECDC4),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Save',
                      style: GoogleFonts.nunito(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnailSection(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: _isUploadingThumbnail ? null : _onChangeThumbnail,
        child: Container(
          height: 140,
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.black.withValues(alpha: 0.08),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_isUploadingThumbnail)
                Container(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.black.withValues(alpha: 0.03),
                  child: const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF4ECDC4),
                    ),
                  ),
                )
              else if (_thumbnailUrl != null && _thumbnailUrl!.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: _thumbnailUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => _buildThumbnailPlaceholder(isDark),
                  placeholder: (_, __) => _buildThumbnailPlaceholder(isDark),
                )
              else
                _buildThumbnailPlaceholder(isDark),

              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.center,
                      colors: [
                        Colors.black.withValues(alpha: 0.5),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              Positioned(
                bottom: 12,
                left: 12,
                child: Row(
                  children: [
                    Icon(
                      _thumbnailUrl != null
                          ? Icons.edit_rounded
                          : Icons.add_photo_alternate_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _thumbnailUrl != null ? 'Change thumbnail' : 'Add thumbnail',
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              if (_thumbnailUrl != null && !_isUploadingThumbnail)
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _thumbnailUrl = null;
                        _thumbnailChanged = true;
                      });
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageSelector(bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: widget.availableLanguages.map((language) {
        final isChecked = _selectedLanguages.contains(language);
        final countryCode = languageCodes[language] ?? 'US';
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: InkWell(
            onTap: () {
              setState(() {
                if (isChecked) {
                  _selectedLanguages.remove(language);
                } else {
                  _selectedLanguages.add(language);
                }
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: isChecked
                    ? (isDark
                        ? const Color(0xFF4ECDC4).withValues(alpha: 0.15)
                        : const Color(0xFF4ECDC4).withValues(alpha: 0.10))
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isChecked
                      ? const Color(0xFF4ECDC4).withValues(alpha: 0.5)
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.08)),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.2)
                            : Colors.black.withValues(alpha: 0.1),
                      ),
                    ),
                    child: ClipOval(
                      child: CountryFlag.fromCountryCode(countryCode),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      language,
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: isChecked
                          ? const Color(0xFF4ECDC4)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: isChecked
                            ? const Color(0xFF4ECDC4)
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.2)
                                : Colors.black.withValues(alpha: 0.15)),
                        width: 2,
                      ),
                    ),
                    child: isChecked
                        ? const Icon(
                            Icons.check_rounded,
                            size: 14,
                            color: Colors.black,
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildThumbnailPlaceholder(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  Colors.white.withValues(alpha: 0.06),
                  Colors.white.withValues(alpha: 0.02),
                ]
              : [
                  const Color(0xFFF8F9FA),
                  const Color(0xFFF0F1F3),
                ],
        ),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
          width: 1.5,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : const Color(0xFF4ECDC4).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.image_outlined,
                size: 24,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.35)
                    : const Color(0xFF4ECDC4),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'No thumbnail',
              style: GoogleFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white.withValues(alpha: 0.40) : Colors.black45,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap to add an image',
              style: GoogleFonts.nunito(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.25)
                    : Colors.black.withValues(alpha: 0.30),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 6),
      child: Text(
        label,
        style: GoogleFonts.nunito(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white54 : Colors.black45,
        ),
      ),
    );
  }

  Widget _buildDifficultySelector(bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildDifficultyOption(isDark, 'beginner', 'Beginner',
            'Simple vocabulary, basic sentences, slow pace'),
        const SizedBox(height: 6),
        _buildDifficultyOption(isDark, 'intermediate', 'Intermediate',
            'Natural language, mixed tenses, moderate complexity'),
        const SizedBox(height: 6),
        _buildDifficultyOption(isDark, 'advanced', 'Advanced',
            'Complex structures, idioms, nuanced expressions'),
      ],
    );
  }

  Widget _buildDifficultyOption(bool isDark, String value, String label, String subtitle) {
    final isSelected = _selectedDifficulty == value;
    return InkWell(
      onTap: () {
        setState(() => _selectedDifficulty = value);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
                  ? const Color(0xFF4ECDC4).withValues(alpha: 0.15)
                  : const Color(0xFF4ECDC4).withValues(alpha: 0.10))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF4ECDC4).withValues(alpha: 0.5)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.08)),
          ),
        ),
        child: Row(
          children: [
            // Radio indicator
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF4ECDC4)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF4ECDC4)
                      : (isDark
                          ? Colors.white.withValues(alpha: 0.2)
                          : Colors.black.withValues(alpha: 0.15)),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: Colors.black,
                    )
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.nunito(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.nunito(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required int maxLines,
    required bool isDark,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.03),
        hintText: hint,
        hintStyle: GoogleFonts.nunito(
          fontWeight: FontWeight.w500,
          color: isDark ? Colors.white30 : Colors.black26,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Color(0xFF4ECDC4),
            width: 2,
          ),
        ),
      ),
      style: GoogleFonts.nunito(
        fontWeight: FontWeight.w600,
        fontSize: 15,
        color: isDark ? Colors.white : Colors.black87,
      ),
    );
  }
}

/// Result model returned by [EditContentSheet].
class ContentEditResult {
  final String title;
  final String description;
  final List<String> tags;
  final List<String> assignedLanguages;
  final bool isPublic;
  final String difficulty;

  /// The thumbnail URL after upload.
  final String? thumbnailUrl;

  /// Whether the thumbnail was deliberately changed (set or removed).
  final bool thumbnailChanged;

  const ContentEditResult({
    required this.title,
    required this.description,
    required this.tags,
    this.assignedLanguages = const [],
    required this.isPublic,
    required this.difficulty,
    this.thumbnailUrl,
    this.thumbnailChanged = false,
  });

  /// Whether any field actually changed from the initial values.
  bool hasChanges({
    required String originalTitle,
    required String originalDescription,
    required List<String> originalTags,
    required List<String> originalAssignedLanguages,
    required bool originalIsPublic,
    required String originalDifficulty,
    String? originalThumbnailUrl,
  }) {
    return title != originalTitle ||
        description != originalDescription ||
        isPublic != originalIsPublic ||
        difficulty != originalDifficulty ||
        !_listsEqual(tags, originalTags) ||
        !_listsEqual(assignedLanguages, originalAssignedLanguages) ||
        thumbnailChanged;
  }

  static bool _listsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    return a.every((e) => b.contains(e)) && b.every((e) => a.contains(e));
  }
}

/// Internal bottom sheet widget that hosts the [SegmentationSelector].
class _ReSegmentSheet extends StatefulWidget {
  final String sourceType;
  final bool hasChapters;
  final String initialSegmentBy;
  final int? initialSegmentValue;

  const _ReSegmentSheet({
    required this.sourceType,
    this.hasChapters = false,
    required this.initialSegmentBy,
    this.initialSegmentValue,
  });

  @override
  State<_ReSegmentSheet> createState() => _ReSegmentSheetState();
}

class _ReSegmentSheetState extends State<_ReSegmentSheet> {
  late SegmentationSelection _selection;

  @override
  void initState() {
    super.initState();
    _selection = SegmentationSelection(
      segmentBy: widget.initialSegmentBy,
      segmentValue: widget.initialSegmentValue,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
              'Change Segmentation',
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
              sourceType: widget.sourceType,
              hasChapters: widget.hasChapters,
              initialSegmentBy: widget.initialSegmentBy,
              initialSegmentValue: widget.initialSegmentValue,
              onChanged: (selection) {
                _selection = selection;
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selection.isValid
                    ? () => Navigator.pop(context, _selection)
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
                child: Text(
                  'Apply',
                  style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
