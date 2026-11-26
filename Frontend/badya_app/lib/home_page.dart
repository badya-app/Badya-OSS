import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:Badya/config/content_types.dart';
import 'package:Badya/config/local_mode.dart';
import 'package:Badya/models/user_content.dart';
import 'package:Badya/services/block_service.dart';
import 'package:Badya/services/content_service.dart';
import 'package:Badya/services/fork_tracking_provider.dart';
import 'package:Badya/services/language_manager.dart';
import 'package:Badya/services/firebase_storage_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:Badya/widgets/library_content_card.dart';
import 'package:Badya/widgets/content_thumbnail.dart';
import 'package:Badya/widgets/report_user_sheet.dart';
import 'package:Badya/widgets/balance_widget.dart';
import 'package:Badya/widgets/custom_app_bar.dart';
import 'package:Badya/widgets/import_dialog.dart';
import 'package:Badya/widgets/filter_chip_row.dart';
import 'package:Badya/widgets/home_page_skeleton.dart';
import 'package:Badya/widgets/smooth_refresh.dart';
import 'package:Badya/utils/score_service.dart';
import 'package:Badya/utils/level_service.dart';
import 'package:Badya/utils/constants.dart';
import 'package:Badya/utils/topic_action_helper.dart';
import 'package:Badya/utils/ui_utils.dart';
import 'package:Badya/pages/content_detail_page.dart';
import 'package:Badya/strange_words_page.dart';
import 'package:Badya/user_content_page.dart';
import 'package:Badya/widgets/language_assignment_sheet.dart';
import 'package:Badya/widgets/empty_state_widget.dart';
import 'package:Badya/widgets/edit_content_sheet.dart';
import 'package:country_flags/country_flags.dart';

/// Home dashboard — user's personal space with nav cards, recommended topics,
/// continue watching, and recent additions.
class HomePage extends StatefulWidget {
  final VoidCallback? onNavigateToLibrary;

  const HomePage({super.key, this.onNavigateToLibrary});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ContentService _contentService = ContentService();
  List<UserContent> _myContent = [];
  List<UserContent> _recommendedContent = [];
  bool _isLoading = true;
  bool _isTopReady = false;
  int _pendingInitialLoads = 0;
  int _streak = 0;
  int _totalXp = 0;
  String _activeFilterType = 'all';
  StreamSubscription<List<UserContent>>? _myContentSub;

  /// Live XP/streak subscription — keeps the header stats fresh the moment
  /// XP is awarded anywhere (home stays mounted in the shell's tab cache,
  /// so it never reloads on its own).
  StreamSubscription<
    ({int totalXp, int streak, Map<String, int> languageXp})
  >? _xpSub;

  /// Uids of users the current user has blocked — their content is filtered
  /// out of recommendations. Updated on load and immediately after a block
  /// from a content card's menu.
  Set<String> _blockedUids = const {};

  String? _lastLanguage;

  @override
  void initState() {
    super.initState();
    // Update XP/streak instantly when a write lands on the user document
    // (e.g. the unscramble game awarding XP) — no manual refresh needed.
    _xpSub = ScoreService.xpSnapshotStream().listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _totalXp = snapshot.totalXp;
        _streak = snapshot.streak;
      });
    });
    // Data will be loaded in didChangeDependencies
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final language = context.watch<LanguageManager>().currentLanguage;
    if (_lastLanguage != language) {
      _lastLanguage = language;
      _loadData(language);
    }
  }

  @override
  void dispose() {
    _myContentSub?.cancel();
    _xpSub?.cancel();
    super.dispose();
  }

  Future<void> _loadData([String? language]) async {
    if (!mounted) return;
    final currentLanguage =
        language ?? context.read<LanguageManager>().currentLanguage;

    if (LocalMode.enabled) {
      try {
        final seedTopics = await LocalMode.loadSeedTopics();
        final now = DateTime.now();
        final List<UserContent> localContent = seedTopics.map((t) {
          return UserContent(
            id: t['id'] as String,
            userId: LocalMode.guestUid,
            title: t['title'] as String,
            description: t['description'] as String? ?? '',
            type: ContentType.aiGenerated,
            language: currentLanguage,
            status: ContentStatus.ready,
            tags: (t['tags'] as List?)?.cast<String>() ??
                [t['category'] as String? ?? 'General'],
            metadata: t['metadata'] as Map<String, dynamic>?,
            createdAt: now,
            updatedAt: now,
          );
        }).toList();
        if (mounted) {
          setState(() {
            _myContent = localContent;
            _pendingInitialLoads = 0;
            _isLoading = false;
            _isTopReady = true;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _pendingInitialLoads = 0;
            _isLoading = false;
            _isTopReady = true;
          });
        }
      }
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;

    // Cancel existing subscriptions
    _myContentSub?.cancel();

    if (mounted) {
      setState(() {
        _isLoading = true;
        _pendingInitialLoads = 2;
      });
    }

    // Load fork tracking data via shared provider (no-op if already loaded).
    context.read<ForkTrackingProvider>().loadData();

    // Load user's own content
    if (uid != null) {
      _myContentSub = _contentService
          .getMyContent(userId: uid, language: currentLanguage, limit: 20)
          .listen(
            (content) {
              if (mounted) {
                setState(() {
                  _myContent = content
                      .where((c) => c.status == ContentStatus.ready)
                      .toList();
                  _pendingInitialLoads--;
                  if (_pendingInitialLoads <= 0) _isLoading = false;
                });
              }
            },
            onError: (_) {
              if (mounted) {
                setState(() {
                  _pendingInitialLoads--;
                  if (_pendingInitialLoads <= 0) _isLoading = false;
                });
              }
            },
          );
    } else {
      if (mounted) {
        setState(() {
          _pendingInitialLoads = 0;
          _isLoading = false;
        });
      }
    }

    // Load personalized recommendations from the hybrid scoring engine
    if (uid != null) {
      // Filter out content authored by users the current user has blocked.
      Set<String> blockedUids = const {};
      try {
        blockedUids = await BlockService().getBlockedUids(uid);
      } catch (_) {
        // Block list unavailable — fall back to unfiltered recommendations.
      }
      if (mounted) setState(() => _blockedUids = blockedUids);
      _contentService
          .getRecommendations(userId: uid, language: currentLanguage, limit: 10)
          .then((content) {
            if (mounted) {
              setState(() {
                _recommendedContent = BlockService.filterByBlocked(
                  content,
                  blockedUids,
                  (c) => c.userId,
                ).toList();
                _pendingInitialLoads--;
                if (_pendingInitialLoads <= 0) _isLoading = false;
              });
            }
          })
          .catchError((_) {
            if (mounted) {
              setState(() {
                _pendingInitialLoads--;
                if (_pendingInitialLoads <= 0) _isLoading = false;
              });
            }
          });
    }

    // Load stats — show the stored streak immediately; recompute in the
    // background so a missed day clears it without blocking the top section
    // (a recompute costs N+3 sequential reads for an N-day streak).
    _streak = await ScoreService.getStreak();
    _totalXp = await ScoreService.getTotalXP();
    if (mounted) {
      setState(() {
        _isTopReady = true;
      });
    }
    unawaited(ScoreService.refreshStreak().then((fresh) {
      if (mounted && fresh != _streak) {
        setState(() => _streak = fresh);
      }
    }));
  }

  /// Public content the user has NOT already forked, does NOT own, and whose
  /// authors are not blocked.
  List<UserContent> get _recommendedTopics {
    final forkTracking = context.read<ForkTrackingProvider>();
    return _recommendedContent
        .where((c) => !forkTracking.forkedLanguages.containsKey(c.id))
        .where((c) => !_blockedUids.contains(c.userId))
        .toList();
  }

  /// Get the pre-assigned languages for a content item (languages already
  /// added in a previous fork). Used to hide them from the AddToCollectionSheet.
  List<String> _getPreAssignedLanguages(UserContent content) {
    return context.read<ForkTrackingProvider>().getPreAssignedLanguages(content);
  }

  /// Get the user's existing fork ID for this content, or null if no fork exists.
  String? _getExistingForkId(UserContent content) {
    return context.read<ForkTrackingProvider>().getExistingForkId(content);
  }

  /// Filter out content with 'processing' or 'failed' status — these are
  /// incomplete and may lack the required fields for safe rendering.
  List<UserContent> get _readyContent =>
      _myContent.where((c) => c.status == ContentStatus.ready).toList();

  List<UserContent> get _continueWatching {
    final ready = _readyContent;
    // Only show section when user has at least 20 topics
    if (ready.length < 20) return [];
    return ready.where((c) => c.progress > 0 && c.progress < 1.0).toList()
      ..sort((a, b) => a.progress.compareTo(b.progress));
  }

  List<UserContent> get _recentContent =>
      _readyContent.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Filter a list of content by the active type filter.
  List<UserContent> _filterByType(List<UserContent> items) {
    if (_activeFilterType == 'all') return items;
    ContentType? targetType;
    switch (_activeFilterType) {
      case 'ai_generated':
        targetType = ContentType.aiGenerated;
        break;
      case 'youtube':
        targetType = ContentType.youtube;
        break;
      case 'document':
        // Docs includes document, text, and article types (same as Library page)
        return items
            .where(
              (c) =>
                  c.type == ContentType.document ||
                  c.type == ContentType.text ||
                  c.type == ContentType.article,
            )
            .toList();
      case 'pdf':
        targetType = ContentType.pdf;
        break;
    }
    if (targetType == null) return items;
    return items.where((c) => c.type == targetType).toList();
  }

  void _navigateToUserContent() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const UserContentPage()),
    );
  }

  void _navigateToStrangeWords() {
    final language = context.read<LanguageManager>().currentLanguage;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StrangeWordsPage(language: language)),
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

  // --- Recommended Content Actions ---

  Future<void> _onAddRecommendedContent(UserContent content) async {
    // Fork creation / language assignment / success toast all live in
    // TopicActionHelper — only the local state-map refresh is page-specific.
    // Updating _forkedLanguages immediately hides the card from recommendations.
    await TopicActionHelper.showTopicSheet(
      context: context,
      content: content,
      source: 'home_recommended',
      cachedPreAssignedLanguages: _getPreAssignedLanguages(content),
      cachedExistingForkId: _getExistingForkId(content),
      onForkUpdated: (assignedLanguages, forkId) {
        if (!mounted) return;
        context.read<ForkTrackingProvider>().updateFork(
          canonicalContentId: content.id,
          assignedLanguages: assignedLanguages.toSet(),
          forkId: forkId,
        );
        setState(() {});
      },
    );
  }

  /// Resolve the current user's uid, safely (null when Firebase Auth is
  /// unavailable, e.g. in widget tests).
  String? _currentUid() {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  /// Block the author of [content] after confirmation, then immediately hide
  /// their content from recommendations (and everywhere else on next load).
  Future<void> _onBlockUser(UserContent content) async {
    final uid = _currentUid();
    // System suggestions carry an empty userId — nothing to block.
    if (uid == null || content.userId.isEmpty || uid == content.userId) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Block user?'),
        content: Text(
          content.authorName.isEmpty
              ? 'You won\'t see this user\'s content anymore. They won\'t '
                    'be notified.'
              : 'You won\'t see ${content.authorName}\'s content anymore. They '
                    'won\'t be notified.',
          style: GoogleFonts.nunito(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Block',
              style: TextStyle(
                color: const Color(0xFFE57373),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await BlockService().blockUser(
        currentUserId: uid,
        blockedUid: content.userId,
        displayName: content.authorName,
      );
      if (!mounted) return;
      // Immediately hide this user's content from the visible feed — the
      // `_recommendedTopics` getter filters on `_blockedUids`.
      setState(() {
        _blockedUids = {..._blockedUids, content.userId};
      });
      UiUtils.showTopNotification(
        context,
        content.authorName.isEmpty
            ? 'User blocked'
            : '${content.authorName} blocked',
        type: NotificationType.success,
      );
    } catch (e) {
      if (mounted) {
        UiUtils.showTopNotification(
          context,
          'Failed to block user',
          type: NotificationType.error,
        );
      }
    }
  }

  /// Open the report sheet for the author of [content].
  Future<void> _onReportUser(UserContent content) async {
    // System suggestions carry an empty userId — nothing to report.
    if (content.userId.isEmpty) return;
    final submitted = await ReportUserSheet.show(
      context,
      reportedUid: content.userId,
      reportedDisplayName: content.authorName.isEmpty
          ? null
          : content.authorName,
    );
    if (submitted && mounted) {
      UiUtils.showTopNotification(
        context,
        'Report submitted. Thank you for keeping Badya safe!',
        type: NotificationType.success,
      );
    }
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
      return await storageService.uploadFile(image.path, 'content_thumbnails');
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
      description: result.description != content.description
          ? result.description
          : null,
      tags: !_listsEqual(result.tags, content.tags) ? result.tags : null,
      assignedLanguages:
          !_listsEqual(result.assignedLanguages, content.assignedLanguages)
          ? result.assignedLanguages
          : null,
      thumbnailUrl:
          result.thumbnailUrl != null && result.thumbnailUrl != currentThumbnail
          ? result.thumbnailUrl
          : null,
      removeThumbnail:
          result.thumbnailChanged &&
              result.thumbnailUrl == null &&
              currentThumbnail != null
          ? true
          : null,
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
    ContentService()
        .updateSegmentationPreference(
          contentId: contentId,
          segmentBy: segmentBy,
          segmentValue: segmentValue,
        )
        .then((_) {
          if (mounted) {
            UiUtils.showTopNotification(
              context,
              'Content re-segmented successfully',
              type: NotificationType.success,
            );
          }
        })
        .catchError((e) {
          if (mounted) {
            UiUtils.showTopNotification(
              context,
              'Failed to re-segment: $e',
              type: NotificationType.error,
            );
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final languageManager = context.watch<LanguageManager>();
    final level = LevelService.levelForXp(_totalXp);
    final recommended = _filterByType(_recommendedTopics);
    final continueWatching = _filterByType(_continueWatching);
    final recentContent = _filterByType(_recentContent);

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF1A1A1A)
          : const Color(0xFFFDF4DD),
      extendBody: true,
      body: BadyaRefreshIndicator(
        onRefresh: () => _loadData(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          slivers: [
            // --- Header ---
            CustomAppBar(
              showMenuButton: false,
              showLanguageButton: true,
              onLanguagePressed: _onLanguageTap,
              languageCode: languageCodes[languageManager.currentLanguage],
              actions: const [BalanceWidget()],
            ),

            // --- Top section (stats + nav cards) ---
            if (!_isTopReady)
              const SliverToBoxAdapter(
                child: HomePageSkeleton(showTopSection: true),
              )
            else ...[
              // --- Stats Banner ---
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildStatsBanner(context, isDark, level),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),

              // --- Navigation Cards ---
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildNavigationCards(isDark),
                ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 20)),

              // --- Content sections (skeleton while loading, real content when ready) ---
              if (_isLoading)
                const SliverToBoxAdapter(
                  child: HomePageSkeleton(showTopSection: false),
                )
              else ...[
                // --- Filter Chips ---
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: FilterChipRow(
                      filters: const [
                        FilterOption(
                          label: 'All',
                          type: 'all',
                          icon: Icons.apps_rounded,
                        ),
                        FilterOption(
                          label: 'AI',
                          type: 'ai_generated',
                          icon: Icons.auto_awesome_rounded,
                        ),
                        FilterOption(
                          label: 'Videos',
                          type: 'youtube',
                          icon: Icons.play_circle_rounded,
                        ),
                        FilterOption(
                          label: 'Docs',
                          type: 'document',
                          icon: Icons.description_rounded,
                        ),
                        FilterOption(
                          label: 'PDF',
                          type: 'pdf',
                          icon: Icons.picture_as_pdf_rounded,
                        ),
                      ],
                      activeFilter: _activeFilterType,
                      onFilterChanged: (type) =>
                          setState(() => _activeFilterType = type),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),

                // --- Content Sections ---
                // Recommended Topics (suggestions not yet added)
                if (recommended.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Recommended topics',
                            style: GoogleFonts.nunito(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          GestureDetector(
                            onTap: widget.onNavigateToLibrary,
                            child: Text(
                              'See all',
                              style: GoogleFonts.nunito(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF4ECDC4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 200,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: recommended.length.clamp(0, 10),
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final content = recommended[index];
                          return SizedBox(
                            width: 280,
                            child: _buildRecommendedCard(
                              context,
                              content,
                              isDark,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],

                // Continue Watching
                if (continueWatching.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Continue Watching',
                            style: GoogleFonts.nunito(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          GestureDetector(
                            onTap: _navigateToUserContent,
                            child: Text(
                              'See all',
                              style: GoogleFonts.nunito(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF4ECDC4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 200,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        itemCount: continueWatching.length.clamp(0, 7),
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final content = continueWatching[index];
                          return SizedBox(
                            width: 280,
                            child: _buildCompactCard(context, content, isDark),
                          );
                        },
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],

                // Recent Additions
                if (recentContent.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Recent Additions',
                            style: GoogleFonts.nunito(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          GestureDetector(
                            onTap: _navigateToUserContent,
                            child: Text(
                              'See all',
                              style: GoogleFonts.nunito(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF4ECDC4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  ...(recentContent
                      .take(10)
                      .map(
                        (content) => SliverToBoxAdapter(
                          child: LibraryContentCard(
                            content: content,                             onTap: () => ContentDetailPage.navigate(
                              context: context,
                              content: content,
                              showLoading: true,
                            ),
                            progress: content.progress,
                            onEdit: () => _onEditContent(content),
                            onDelete: () => _onDeleteContent(content),
                            onEditLanguages: () => _onEditLanguages(content),
                          ),
                        ),
                      )),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                ],

                // Empty state
                if (_readyContent.isEmpty && recommended.isEmpty) ...[
                  SliverFillRemaining(child: _buildEmptyState(context, isDark)),
                ],
                // Bottom spacer (only visible when content is showing)
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ],
           ],
         ),
       ),
    );
  }

  // --- Navigation Cards ---

  Widget _buildNavigationCards(bool isDark) {
    return Column(
      children: [
        // Top row: Create + My Content
        Row(
          children: [
            Expanded(
              child: _buildNavCard(
                onTap: _openImportDialog,
                gradientColors: [
                  const Color(0xFF1FA695),
                  const Color(0xFF169A8B),
                ],
                icon: Icons.add_rounded,
                label: 'Create',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildNavCard(
                onTap: _navigateToUserContent,
                gradientColors: [
                  const Color(0xFFE26B50),
                  const Color(0xFFD34C2D),
                ],
                icon: Icons.folder_rounded,
                label: 'My Content',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Bottom row: Your Cards (full width, SVG icon + inline label)
        GestureDetector(
          onTap: _navigateToStrangeWords,
          child: Container(
            height: 95,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF7C4DFF), Color(0xFF651FFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7C4DFF).withValues(alpha: 0.16),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                SvgPicture.asset(
                  'assets/images/flashcards.svg',
                  width: 32,
                  height: 32,
                  colorFilter: const ColorFilter.mode(
                    Colors.white,
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  'My Cards',
                  style: GoogleFonts.nunito(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavCard({
    required VoidCallback onTap,
    required List<Color> gradientColors,
    required IconData icon,
    required String label,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 95,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.18),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: gradientColors.last.withValues(alpha: 0.16),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                      width: 1,
                    ),
                  ),
                  child: Icon(icon, color: Colors.white, size: 18),
                ),
                const Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ],
            ),
            const Spacer(),
            Text(
              label,
              style: GoogleFonts.nunito(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Recommended Card ---

  Widget _buildRecommendedCard(
    BuildContext context,
    UserContent content,
    bool isDark,
  ) {
    final uid = _currentUid();
    // Other users' content gets the block/report menu; own content, system
    // suggestions (empty userId), and anonymous browsing get a plain card.
    final canModerate =
        uid != null && content.userId.isNotEmpty && uid != content.userId;

    return GestureDetector(
      onTap: () => _onAddRecommendedContent(content),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Accent bar
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: content.type.accentColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
            ),
            // Thumbnail area
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ContentThumbnail(content: content),
                  // Type badge (top-left)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _buildMiniBadge(content.type),
                  ),
                ],
              ),
            ),
            // Info
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title + 3-dot menu (block/report for other users)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          content.title,
                          style: GoogleFonts.nunito(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (canModerate)
                        PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: Icon(
                            Icons.more_horiz_rounded,
                            size: 18,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          onSelected: (value) {
                            switch (value) {
                              case 'block':
                                _onBlockUser(content);
                              case 'report':
                                _onReportUser(content);
                            }
                          },
                          itemBuilder: (context) {
                            return [
                              const PopupMenuItem(
                                value: 'block',
                                child: _MenuRow(
                                  icon: Icons.person_off_rounded,
                                  label: 'Block user',
                                  isDestructive: true,
                                ),
                              ),
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
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  if (content.authorName.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        content.authorName,
                        style: GoogleFonts.nunito(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF4ECDC4),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  Text(
                    content.description.isNotEmpty
                        ? content.description
                        : content.tags.take(2).join(' . '),
                    style: GoogleFonts.nunito(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white38 : Colors.black38,
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
    );
  }

  // --- Stats Banner ---

  Widget _buildStatsBanner(BuildContext context, bool isDark, int level) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF2D2D2D), const Color(0xFF1E1E1E)]
              : [Colors.white, const Color(0xFFFDF4DD)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStat(
            context,
            'XP',
            '$_totalXp',
            const Color(0xFFFF6B6B),
            isDark,
          ),
          _buildStat(
            context,
            'Streak',
            '$_streak🔥',
            const Color(0xFFFFD93D),
            isDark,
          ),
          _buildStat(
            context,
            'Level',
            '$level',
            const Color(0xFF9B59B6),
            isDark,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.1, end: 0);
  }

  Widget _buildStat(
    BuildContext context,
    String label,
    String value,
    Color color,
    bool isDark,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: GoogleFonts.nunito(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.nunito(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
      ],
    );
  }

  Widget _buildCompactCard(
    BuildContext context,
    UserContent content,
    bool isDark,
  ) {
    final progress = content.progress.clamp(0.0, 1.0);
    return GestureDetector(
      onTap: () =>           ContentDetailPage.navigate(
            context: context,
            content: content,
            showLoading: true,
          ),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Accent bar
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: content.type.accentColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
            ),
            // Thumbnail area
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ContentThumbnail(content: content),
                  // Type badge (top-left)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _buildMiniBadge(content.type),
                  ),
                ],
              ),
            ),
            // Info
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    content.title,
                    style: GoogleFonts.nunito(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: isDark
                          ? Colors.white.withValues(alpha: 0.10)
                          : Colors.black.withValues(alpha: 0.06),
                      valueColor: AlwaysStoppedAnimation(
                        content.type.accentColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(progress * 100).toInt()}%',
                    style: GoogleFonts.nunito(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
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

  /// Small frosted badge showing the content type label, used on cards.
  Widget _buildMiniBadge(ContentType type) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(type.icon, color: type.accentColor, size: 10),
              const SizedBox(width: 4),
              Text(
                type.displayName,
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

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    return const EmptyStateWidget(
      message: 'Start your learning journey!',
      subMessage: 'Create content or browse the Library for inspiration.',
    );
  }

  void _onLanguageTap() {
    final languageManager = context.read<LanguageManager>();
    final myLangs = languageManager.myLanguages;
    if (myLangs.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (modalContext) {
        final currentLanguage = languageManager.currentLanguage;
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(modalContext).dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Choose language',
                style: GoogleFonts.nunito(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(modalContext).textTheme.titleLarge?.color,
                ),
              ),
              const SizedBox(height: 12),
              ...myLangs.map(
                (lang) => ListTile(
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: lang == currentLanguage
                          ? const Color(0xFF4ECDC4).withValues(alpha: 0.1)
                          : Theme.of(
                              modalContext,
                            ).dividerColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: lang == currentLanguage
                            ? const Color(0xFF4ECDC4)
                            : Theme.of(modalContext).dividerColor,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: ClipOval(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CountryFlag.fromCountryCode(
                            languageCodes[lang] ?? 'US',
                          ),
                        ),
                      ),
                    ),
                  ),
                  title: Text(
                    lang,
                    style: GoogleFonts.nunito(fontWeight: FontWeight.w700),
                  ),
                  trailing: lang == currentLanguage
                      ? const Icon(
                          Icons.check_rounded,
                          color: Color(0xFF4ECDC4),
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(modalContext);
                    languageManager.updateCurrentLanguage(lang);
                  },
                ),
              ),
            ],
          ),
        );
      },
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
