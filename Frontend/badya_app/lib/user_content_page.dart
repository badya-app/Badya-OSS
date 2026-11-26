import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:Badya/config/local_mode.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:Badya/config/api_config.dart';
import 'package:Badya/config/content_types.dart';
import 'package:Badya/models/user_content.dart';
import 'package:Badya/services/content_service.dart';
import 'package:Badya/services/language_manager.dart';
import 'package:Badya/services/firebase_storage_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:Badya/widgets/empty_state_widget.dart';
import 'package:Badya/widgets/import_dialog.dart';
import 'package:Badya/widgets/library_content_card.dart';
import 'package:Badya/widgets/filter_chip_row.dart';
import 'package:Badya/widgets/language_assignment_sheet.dart';
import 'package:Badya/widgets/edit_content_sheet.dart';
import 'package:Badya/pages/content_detail_page.dart';
import 'package:Badya/utils/ui_utils.dart';

/// Full list of the current user's content with filtering and search.
/// Navigated from Home -> "See all my content".
class UserContentPage extends StatefulWidget {
  const UserContentPage({super.key});

  @override
  State<UserContentPage> createState() => _UserContentPageState();
}

class _UserContentPageState extends State<UserContentPage> {
  final ContentService _contentService = ContentService();
  final TextEditingController _searchController = TextEditingController();
  List<UserContent> _myContent = [];
  bool _isLoading = true;
  String _activeFilter = 'all';
  String _searchQuery = '';

  // Semantic Search State
  Timer? _debounceTimer;
  List<double>? _queryEmbedding;
  bool _isSemanticSearching = false;

  StreamSubscription<List<UserContent>>? _contentSub;
  String? _lastLanguage;

  @override
  void initState() {
    super.initState();
    // Handled via manual onChange/debouncing
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final language = context.watch<LanguageManager>().currentLanguage;
    if (_lastLanguage != language) {
      _lastLanguage = language;
      _loadContent(language);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _contentSub?.cancel();
    super.dispose();
  }

  Future<void> _loadContent(String language) async {
    final uid = LocalMode.enabled
        ? LocalMode.guestUid
        : FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    if (mounted) setState(() => _isLoading = true);

    _contentSub?.cancel();
    _contentSub = _contentService.getMyContent(
      userId: uid,
      language: language,
      limit: 100,
    ).listen(
      (content) {
        if (mounted) {
          setState(() {
            _myContent = content;
            _isLoading = false;
          });
        }
      },
      onError: (_) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      },
    );

  }

  // --- Management Actions ---

  Future<void> _onEditLanguages(UserContent content) async {
    final languageManager = context.read<LanguageManager>();
    final result = await LanguageAssignmentSheet.show(
      context: context,
      availableLanguages: languageManager.myLanguages,
      initialAssigned: Set.from(content.assignedLanguages),
    );

    if (result != null && mounted) {
      await _contentService.assignLanguages(content.id, result.toList());
    }
  }

  Future<void> _onDeleteContent(UserContent content) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${content.title}"?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final displayTitle = content.title.characters.length > 24
          ? '${content.title.characters.take(24).toString()}…'
          : content.title;
      // Show notification immediately for responsive feedback
      UiUtils.showTopNotification(
        context,
        '"$displayTitle" deleted',
        type: NotificationType.success,
      );
      try {
        await _contentService.deleteContent(content.id);
      } catch (e) {
        if (mounted) {
          UiUtils.showTopNotification(
            context,
            'Failed to delete: $e',
            type: NotificationType.error,
          );
        }
      }
    }
  }

  Future<String?> _pickAndUploadThumbnail() async {
    try {
      final XFile? image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 800,
      );
      if (image == null) return null;
      final storageService = FirebaseStorageService();
      return await storageService.uploadFile(
        image.path,
        'content_thumbnails',
      );
    } catch (e) {
      if (mounted) {
        UiUtils.showTopNotification(
          context,
          'Failed to upload image: $e',
          type: NotificationType.error,
        );
      }
      return null;
    }
  }

  Future<void> _onEditContent(UserContent content) async {
    final currentThumbnail = content.metadata?['thumbnail_url'] as String?;
    final bool canEditSegmentation = _canEditSegmentation(content);
    final chapters = content.metadata?['chapters'];
    final chaptersAvailable = chapters is List && chapters.isNotEmpty;
    final languageManager = context.read<LanguageManager>();

    final result = await EditContentSheet.show(
      context: context,
      title: content.title,
      description: content.description,
      tags: content.tags,
      initialAssignedLanguages: content.assignedLanguages,
      availableLanguages: languageManager.myLanguages,
      isPublic: content.isPublic,
      initialDifficulty: content.metadata?['difficulty'] as String? ?? 'intermediate',
      showVisibilityToggle: content.canonicalContentId == null,
      initialThumbnailUrl: currentThumbnail,
      onPickImage: _pickAndUploadThumbnail,
      lessonCount: canEditSegmentation ? content.lessonCount : null,
      segmentBy: canEditSegmentation ? content.segmentBy : null,
      segmentValue: canEditSegmentation ? content.segmentValue : null,
      sourceType: content.type == ContentType.youtube ? 'video' : 'text',
      hasChapters: chaptersAvailable,
      onReSegment: canEditSegmentation
          ? (segmentBy, segmentValue) {
              _handleReSegment(content.id, segmentBy, segmentValue);
            }
          : null,
    );

    if (result == null || !mounted) return;

    final hasChanges = result.hasChanges(
      originalTitle: content.title,
      originalDescription: content.description,
      originalTags: content.tags,
      originalAssignedLanguages: content.assignedLanguages,
      originalIsPublic: content.isPublic,
      originalDifficulty: content.metadata?['difficulty'] as String? ?? 'intermediate',
      originalThumbnailUrl: currentThumbnail,
    );

    if (!hasChanges) return;

    final currentDifficulty = content.metadata?['difficulty'] as String? ?? 'intermediate';
    final difficultyChanged = result.difficulty != currentDifficulty;

    await _contentService.updateContent(
      content.id,
      title: result.title != content.title ? result.title : null,
      description: result.description != content.description ? result.description : null,
      tags: !_listsEqual(result.tags, content.tags) ? result.tags : null,
      assignedLanguages: !_listsEqual(result.assignedLanguages, content.assignedLanguages)
          ? result.assignedLanguages
          : null,
      thumbnailUrl: result.thumbnailUrl != null && result.thumbnailUrl != currentThumbnail ? result.thumbnailUrl : null,
      removeThumbnail: result.thumbnailChanged && result.thumbnailUrl == null && currentThumbnail != null ? true : null,
      metadata: difficultyChanged ? {'difficulty': result.difficulty} : null,
    );

    if (result.isPublic != content.isPublic) {
      await _contentService.toggleVisibility(content.id, result.isPublic);
    }

    if (mounted) {
      UiUtils.showTopNotification(
        context,
        'Content updated',
        type: NotificationType.success,
      );
    }
  }

  bool _listsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    return a.every((e) => b.contains(e)) && b.every((e) => a.contains(e));
  }

  bool _canEditSegmentation(UserContent content) {
    // AI-generated content doesn't use the import/lesson system, skip it.
    // All other content types support virtual segmentation via source/raw.
    if (content.type == ContentType.aiGenerated) return false;
    return true;
  }

  /// Re-segments the content with a new method and value.
  ///
  /// `updateSegmentationPreference` persists `segment_by`/`segment_value`,
  /// recalculates `lesson_count` from the new segmentation and saves it on
  /// the document; the `getMyContent` stream then refreshes this page's list
  /// so the new count is shown immediately.
  void _handleReSegment(String contentId, String segmentBy, int? segmentValue) {
    ContentService().updateSegmentationPreference(
      contentId: contentId,
      segmentBy: segmentBy,
      segmentValue: segmentValue,
    ).then((_) {
      if (mounted) {
        UiUtils.showTopNotification(
          context,
          'Content re-segmented successfully',
          type: NotificationType.success,
        );
      }
    }).catchError((e) {
      if (mounted) {
        UiUtils.showTopNotification(
          context,
          'Failed to re-segment: $e',
          type: NotificationType.error,
        );
      }
    });
  }

  List<UserContent> get _filteredContent {
    Iterable<UserContent> items = _myContent;

    // Type filter
    if (_activeFilter == 'ai_generated') {
      items = items.where((c) => c.type == ContentType.aiGenerated);
    } else if (_activeFilter == 'youtube') {
      items = items.where((c) => c.type == ContentType.youtube);
    } else if (_activeFilter == 'document') {
      items = items.where(
        (c) => c.type == ContentType.document || c.type == ContentType.article || c.type == ContentType.text,
      );
    } else if (_activeFilter == 'pdf') {
      items = items.where((c) => c.type == ContentType.pdf);
    }

    var list = items.toList();

    // Search filter (Hybrid Semantic & Keyword)
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      
      final scoredItems = list.map((item) {
        double textMatchScore = 0.0;
        if (item.title.toLowerCase().contains(query)) {
          textMatchScore = 1.0;
        } else if (item.tags.any((t) => t.toLowerCase().contains(query))) {
          textMatchScore = 0.7;
        } else if (item.description.toLowerCase().contains(query)) {
          textMatchScore = 0.4;
        }

        double semanticScore = 0.0;
        final embedding = item.metadata?['embedding'] as List<dynamic>?;
        if (_queryEmbedding != null && embedding != null) {
          semanticScore = _cosineSimilarity(_queryEmbedding!, embedding);
        }

        double finalScore = 0.0;
        if (_queryEmbedding != null && embedding != null) {
          finalScore = (semanticScore * 0.8) + (textMatchScore * 0.2);
        } else {
          finalScore = textMatchScore;
        }

        return MapEntry(item, finalScore);
      }).toList();

      final filteredScored = scoredItems.where((entry) {
        final item = entry.key;
        final hasTextMatch = item.title.toLowerCase().contains(query) ||
            item.description.toLowerCase().contains(query) ||
            item.tags.any((t) => t.toLowerCase().contains(query));
        
        if (hasTextMatch) return true;
        
        final embedding = item.metadata?['embedding'] as List<dynamic>?;
        if (_queryEmbedding != null && embedding != null) {
          final sim = _cosineSimilarity(_queryEmbedding!, embedding);
          return sim >= 0.65;
        }
        return false;
      }).toList();          filteredScored.sort((a, b) => b.value.compareTo(a.value));
      list = filteredScored.map((entry) => entry.key).toList();
    } else {
      list.sort((a, b) => (b.lastOpenedAt ?? b.updatedAt).compareTo(a.lastOpenedAt ?? a.updatedAt));
    }

    // Exclude non-ready content (processing/failed) to prevent rendering incomplete data
    return list.where((c) => c.status == ContentStatus.ready).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filteredContent;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFFDF4DD),
      extendBody: true,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.arrow_back_rounded, color: Color(0xFF4ECDC4), size: 24),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'My Content',
                      style: GoogleFonts.nunito(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),

          // Search bar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: _buildSearchBar(isDark),
            ).animate().fadeIn(duration: 200.ms),
          ),

          // Filter chips
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: FilterChipRow(
                filters: const [
                  FilterOption(label: 'All', type: 'all', icon: Icons.apps_rounded),
                  FilterOption(label: 'AI', type: 'ai_generated', icon: Icons.auto_awesome_rounded),
                  FilterOption(label: 'Videos', type: 'youtube', icon: Icons.play_circle_rounded),
                  FilterOption(label: 'Docs', type: 'document', icon: Icons.description_rounded),
                  FilterOption(label: 'PDF', type: 'pdf', icon: Icons.picture_as_pdf_rounded),
                ],
                activeFilter: _activeFilter,
                onFilterChanged: (type) => setState(() => _activeFilter = type),
              ),
            ),
          ),

          // Content count
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                '${filtered.length} ${filtered.length == 1 ? 'item' : 'items'}',
                style: GoogleFonts.nunito(
                  fontSize: 13, fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
            ),
          ),

          // Content list
          if (_isLoading)
            const SliverFillRemaining(
              hasScrollBody: true,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (filtered.isEmpty)
            SliverFillRemaining(
              hasScrollBody: true,
              child: _buildEmptyState(context),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 100),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final content = filtered[index];
                    return LibraryContentCard(
                      content: content,
                      progress: content.progress,
                      onTap: () => ContentDetailPage.navigate(
                        context: context,
                        content: content,
                        showLoading: true,
                      ),
                      onEdit: () => _onEditContent(content),
                      onDelete: () => _onDeleteContent(content),
                      onEditLanguages: () => _onEditLanguages(content),
                    ).animate().fadeIn(duration: 300.ms, delay: (index * 50).ms);
                  },
                  childCount: filtered.length,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openImportDialog,
        backgroundColor: const Color(0xFF4ECDC4),
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
    );
  }

  Future<void> _openImportDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const ImportDialog(importType: 'all'),
    );
    if (result == true && mounted) {
      UiUtils.showTopNotification(
        context,
        'Content imported successfully',
        type: NotificationType.success,
      );
    }
  }

  Widget _buildEmptyState(BuildContext context) {
    return const EmptyStateWidget(
      message: 'No content yet',
      subMessage: '',
    );
  }



  Widget _buildSearchBar(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF222220) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isSemanticSearching
              ? const Color(0xFFFF6B6B)
              : (isDark ? const Color(0x22FFFFFF) : const Color(0x1A2D3436)),
          width: _isSemanticSearching ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: _isSemanticSearching
                ? const Color(0xFFFF6B6B).withValues(alpha: 0.15)
                : const Color(0xFF2D3436).withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
      child: Row(
        children: [
                          Icon(
                            _isSemanticSearching ? Icons.auto_awesome_rounded : Icons.search_rounded,
                            color: _isSemanticSearching ? const Color(0xFFFF6B6B) : const Color(0xFF4ECDC4),
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              autofocus: false,
                              onChanged: _onSearchChanged,
                              decoration: InputDecoration(
                                filled: false,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                                isCollapsed: true,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                hintText: 'Semantic search your content...',
                                hintStyle: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                  color: isDark ? Colors.white30 : Colors.black38,
                                ),
                              ),
                              style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: isDark ? Colors.white : const Color(0xFF2A2A28),
                              ),
                            ),
                          ),
          if (_searchQuery.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchController.clear();
                _onSearchChanged('');
              },
              child: Icon(
                Icons.clear_rounded,
                size: 18,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
        ],
      ),
    );
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query.trim();
    });

    _debounceTimer?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _queryEmbedding = null;
        _isSemanticSearching = false;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      setState(() {
        _isSemanticSearching = true;
      });
      final embedding = await _fetchQueryEmbedding(query.trim());
      if (mounted) {
        setState(() {
          _queryEmbedding = embedding;
          _isSemanticSearching = false;
        });
      }
    });
  }

  Future<List<double>?> _fetchQueryEmbedding(String query) async {
    try {
      final url = Uri.parse('${ApiConfig.getBaseUrl()}/recommendations/embed');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': query,
          'description': '',
          'tags': <String>[],
        }),
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        final list = result['embedding'] as List<dynamic>;
        return list.map((v) => (v as num).toDouble()).toList();
      }
    } catch (e) {
      // Ignore errors for offline/fallback matching
    }
    return null;
  }

  double _cosineSimilarity(List<double> v1, List<dynamic> v2) {
    if (v1.length != v2.length || v1.isEmpty) return 0.0;
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    for (int i = 0; i < v1.length; i++) {
      final double val2 = (v2[i] as num).toDouble();
      dotProduct += v1[i] * val2;
      normA += v1[i] * v1[i];
      normB += val2 * val2;
    }
    if (normA == 0.0 || normB == 0.0) return 0.0;
    return dotProduct / (math.sqrt(normA) * math.sqrt(normB));
  }
}
