import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:Badya/config/api_config.dart';
import 'package:Badya/config/content_types.dart';
import 'package:Badya/models/user_content.dart';
import 'package:Badya/config/local_mode.dart';
import 'package:Badya/services/block_service.dart';
import 'package:Badya/services/content_service.dart';
import 'package:Badya/services/fork_tracking_provider.dart';
import 'package:Badya/services/language_manager.dart';
import 'package:Badya/widgets/library_content_card_tall.dart';
import 'package:Badya/widgets/library_page_skeleton.dart';
import 'package:Badya/widgets/report_user_sheet.dart';
import 'package:Badya/widgets/filter_chip_row.dart';
import 'package:Badya/widgets/balance_widget.dart';
import 'package:Badya/widgets/custom_app_bar.dart';
import 'package:Badya/widgets/empty_state_widget.dart';
import 'package:Badya/widgets/smooth_refresh.dart';
import 'package:Badya/utils/constants.dart';
import 'package:Badya/utils/topic_action_helper.dart';
import 'package:Badya/utils/ui_utils.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:country_flags/country_flags.dart';

/// The unified Library page — content discovery hub.
/// Shows public content by default, with filter chips to toggle views.
/// Tapping unowned content shows the "Add to Collection" dialog.
/// Already-added content navigates directly to the detail page.
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final ContentService _contentService = ContentService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Filters
  String _activeFilterType =
      'all'; // 'all', 'ai_generated', 'youtube', 'document', 'pdf'
  String _searchQuery = '';

  // Pagination
  DocumentSnapshot? _lastAiDoc;
  DocumentSnapshot? _lastNonAiDoc;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  // Data
  List<UserContent> _allContent = [];
  List<UserContent> _cachedFilteredContent = [];

  bool _isLoading = true;
  // Semantic Search State
  Timer? _debounceTimer;
  Timer? _autoPaginateDebounceTimer;
  int _querySequenceNumber = 0;
  List<double>? _queryEmbedding;

  /// Tracks whether we've already notified the user about semantic search being
  /// degraded to keyword-only, to avoid spamming on repeated failures.
  bool _semanticDegradeNotified = false;

  /// Results from the server-side /recommendations/search endpoint.
  /// When non-null and `_searchQuery` is non-empty, these replace
  /// `_allContent` for display. Items are already scored and sorted
  /// by the backend.
  List<UserContent>? _searchResults;

  /// Whether a server-side search is currently in-flight.
  bool _isServerSearching = false;

  /// Timer for debouncing the server search call.
  Timer? _searchTimer;

  /// Timestamp of the last scroll-triggered pagination.
  /// Used to throttle rapid-fire scroll events and prevent infinite
  /// request loops when filters result in 0 visible items.
  DateTime? _lastPaginateTime;

  /// Uids of users the current user has blocked — their content is filtered
  /// out of the library feed and search results.
  Set<String> _blockedUids = const {};

  String? _lastLanguage;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
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
    _debounceTimer?.cancel();
    _autoPaginateDebounceTimer?.cancel();
    _searchTimer?.cancel();
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData(String language) async {
    if (mounted) setState(() => _isLoading = true);

    if (LocalMode.enabled) {
      final seedTopics = await LocalMode.loadSeedTopics();
      final now = DateTime.now();
      final List<UserContent> localContent = seedTopics.map((t) {
        return UserContent(
          id: t['id'] as String,
          userId: LocalMode.guestUid,
          title: t['title'] as String,
          description: t['description'] as String? ?? '',
          type: ContentType.aiGenerated,
          language: language,
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
          _allContent = localContent;
          _cachedFilteredContent = localContent;
          _hasMore = false;
          _isLoading = false;
        });
      }
      return;
    }

    // Reset pagination state, search state & cached filtered content
    _lastAiDoc = null;
    _lastNonAiDoc = null;
    _hasMore = true;
    _isLoadingMore = false;
    _allContent = [];
    _cachedFilteredContent = [];
    _searchResults = null;
    _isServerSearching = false;
    _searchTimer?.cancel();

    // Load fork tracking data via shared provider (no-op if already loaded).
    await context.read<ForkTrackingProvider>().loadData();

    // Load the current user's block list so blocked users' content is hidden.
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final blocked = uid == null
          ? const <String>{}
          : await BlockService().getBlockedUids(uid);
      if (mounted) setState(() => _blockedUids = blocked);
    } catch (_) {
      // Block list unavailable — fall back to unfiltered feed.
    }

    // Load first page of public content with cursor-based pagination
    await _loadPage(language, isInitial: true);
  }

  /// Check whether the given content has already been added in the current language.
  /// Content added only in other languages is shown as unadded (with "Add" button).
  bool _isContentAddedInCurrentLanguage(UserContent content, String language) {
    final forkTracking = context.read<ForkTrackingProvider>();
    final forkedLangs = forkTracking.forkedLanguages[content.id];
    if (forkedLangs == null) return false;
    return forkedLangs.contains(language);
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

  /// Whether the content should be hidden from the library because the user
  /// has already added it in the currently selected language.
  bool _isContentHiddenByLanguage(UserContent content, String language) {
    return _isContentAddedInCurrentLanguage(content, language);
  }

  // --- Filtering Logic ---

  /// Compute the filtered content list based on current filters and search.
  /// Returns the list without side effects (no setState).
  List<UserContent> _computeFilteredContent() {
    // When server search results are available, use them directly.
    // Items are already filtered by type, scored, and sorted by the backend.
    if (_searchQuery.isNotEmpty && _searchResults != null) {
      final currentLanguage = context.read<LanguageManager>().currentLanguage;
      return _searchResults!
          .where((c) => !_isContentHiddenByLanguage(c, currentLanguage))
          .where((c) => !_blockedUids.contains(c.userId))
          .toList();
    }

    // Otherwise fall back to local-only filtering of already-loaded pages.
    Iterable<UserContent> items = _allContent;
    final currentLanguage = context.read<LanguageManager>().currentLanguage;

    // Hide content the user already added in the current language
    items = items.where((c) => !_isContentHiddenByLanguage(c, currentLanguage));

    // Hide content authored by users the current user has blocked
    items = items.where((c) => !_blockedUids.contains(c.userId));

    // Type filter (only for local items; server results are already filtered)
    if (_activeFilterType == 'ai_generated') {
      items = items.where((c) => c.type == ContentType.aiGenerated);
    } else if (_activeFilterType == 'youtube') {
      items = items.where((c) => c.type == ContentType.youtube);
    } else if (_activeFilterType == 'document') {
      items = items.where(
        (c) =>
            c.type == ContentType.document ||
            c.type == ContentType.text ||
            c.type == ContentType.article,
      );
    } else if (_activeFilterType == 'pdf') {
      items = items.where((c) => c.type == ContentType.pdf);
    }

    var list = items.toList();

    // Search filter (Hybrid Semantic & Keyword) — local fallback only
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();

      final scoredItems = list.map((item) {
        double textMatchScore = 0.0;
        if (item.title.toLowerCase().contains(query)) {
          textMatchScore = 1.0;
        } else if (item.tags.any((t) => t.toLowerCase().contains(query))) {
          textMatchScore = 0.7;
        } else if (item.authorName.toLowerCase().contains(query)) {
          textMatchScore = 0.5;
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
        final hasTextMatch =
            item.title.toLowerCase().contains(query) ||
            item.authorName.toLowerCase().contains(query) ||
            item.description.toLowerCase().contains(query) ||
            item.tags.any((t) => t.toLowerCase().contains(query));

        if (hasTextMatch) return true;

        final embedding = item.metadata?['embedding'] as List<dynamic>?;
        if (_queryEmbedding != null && embedding != null) {
          final sim = _cosineSimilarity(_queryEmbedding!, embedding);
          return sim >= 0.65;
        }
        return false;
      }).toList();

      filteredScored.sort((a, b) => b.value.compareTo(a.value));
      list = filteredScored.map((entry) => entry.key).toList();
    } else {
      // Sort by recency only — Library is a discovery feed
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }

    return list;
  }

  /// Recompute the filtered content, update the cached state variable,
  /// and auto-paginate if results are too few for the current filter.
  void _recomputeFilteredContent() {
    final filtered = _computeFilteredContent();
    if (!mounted) return;
    setState(() {
      _cachedFilteredContent = filtered;
    });

    // Don't auto-paginate when showing server search results — the server
    // already exhaustively searched the database for matching content.
    if (_searchQuery.isNotEmpty && _searchResults != null) return;

    // Auto-paginate (debounced 200ms): batch-fetch multiple pages when filtered
    // results are sparse (e.g., a narrow filter like "PDF").  The debounce prevents
    // redundant fetches when the user rapidly toggles filters; each tap cancels
    // the pending timer so only the final selection triggers a batch.
    _autoPaginateDebounceTimer?.cancel();
    if (filtered.length < 10 && _hasMore && !_isLoadingMore && !_isLoading) {
      _autoPaginateDebounceTimer = Timer(
        const Duration(milliseconds: 200),
        () => _ensureMinimumResults(
          context.read<LanguageManager>().currentLanguage,
        ),
      );
    }
  }

  /// Fetch pages in a tight loop until we have at least 10 filtered results
  /// or exhaust the server.  This avoids the round-trip delay through widget
  /// rebuilds between successive page fetches that the sequential
  /// `_loadPage` → `_recomputeFilteredContent` → `_loadPage` chain incurs.
  Future<void> _ensureMinimumResults(String language) async {
    if (_isLoadingMore || _isLoading || !_hasMore) return;

    _isLoadingMore = true;
    if (mounted) setState(() {});

    try {
      const int maxBatchPages = 4;

      for (int i = 0; i < maxBatchPages && _hasMore && mounted; i++) {
        final result = await _contentService.getPublicFeedPage(
          language: language,
          limit: 50,
          afterAiDoc: _lastAiDoc,
          afterNonAiDoc: _lastNonAiDoc,
          typeFilter: _serverTypeFilter,
        );

        if (!mounted) return;

        final uid = FirebaseAuth.instance.currentUser?.uid;
        final pageItems = result.items
            .where((c) => c.status == ContentStatus.ready)
            .where((c) => uid == null || c.userId != uid)
            .toList();

        // Update cursors immediately so the next loop iteration fetches the
        // next page rather than re-fetching the current one.
        // Only update each cursor when the query actually ran (non-null result).
        _allContent.addAll(pageItems);
        if (result.lastAiDoc != null) _lastAiDoc = result.lastAiDoc;
        if (result.lastNonAiDoc != null) _lastNonAiDoc = result.lastNonAiDoc;
        _hasMore = result.hasMore;

        // Check whether we already have enough filtered content to stop.
        final filtered = _computeFilteredContent();
        if (filtered.length >= 10 || !_hasMore) break;
      }
    } catch (e) {
      // Silently fail — whatever we've already loaded will be shown.
    }

    _isLoadingMore = false;
    // Manually update the cached filtered list instead of calling
    // _recomputeFilteredContent() — that method's auto-pagination guard
    // would see !_isLoadingMore and trigger a fresh _ensureMinimumResults
    // call, creating an unbounded cascade loop.
    if (mounted) {
      final finalFiltered = _computeFilteredContent();
      setState(() { _cachedFilteredContent = finalFiltered; });
    }
  }

  // --- Actions ---

  void _onCardTap(UserContent content) {
    // Log the click for CTR / engagement metrics
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _contentService.logRecommendationClick(
        userId: uid,
        contentId: content.id,
        source: 'library',
      );
    }

    // All visible library content is not yet added in the current language,
    // so always show the add-to-collection dialog
    _onAddContent(content);
  }

  Future<void> _onAddContent(UserContent content) async {
    // Fork creation / language assignment / success toast all live in
    // TopicActionHelper — only the local state-map refresh is page-specific.
    await TopicActionHelper.showTopicSheet(
      context: context,
      content: content,
      source: 'library',
      // _onCardTap already logged the recommendation click.
      logRecommendationClick: false,
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

  /// Block the author of [content] after confirmation, then immediately hide
  /// their content from the visible feed.
  Future<void> _onBlockUser(UserContent content) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
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
      // Immediately hide this user's content from the feed (and re-run the
      // local filter) — no refresh needed.
      setState(() {
        _blockedUids = {..._blockedUids, content.userId};
      });
      _recomputeFilteredContent();
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

  void _onLanguageTap() {
    final languageManager = context.read<LanguageManager>();
    _showLanguagePicker(languageManager);
  }

  void _showLanguagePicker(LanguageManager languageManager) {
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
                style: GoogleFonts.playfairDisplay(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
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
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600,
                    ),
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

  /// Convert the active filter string to a set of ContentType values
  /// that the backend can use to fetch only matching items.
  /// Returns `null` for "all" (no server-side filter).
  Set<ContentType>? get _serverTypeFilter {
    switch (_activeFilterType) {
      case 'all':
        return null;
      case 'ai_generated':
        return {ContentType.aiGenerated};
      case 'youtube':
        return {ContentType.youtube};
      case 'document':
        return {ContentType.document, ContentType.text, ContentType.article};
      case 'pdf':
        return {ContentType.pdf};
      default:
        return null;
    }
  }

  // ─── Pagination ──────────────────────────────────────────────────

  /// Load a page of public content with cursor-based pagination.
  Future<void> _loadPage(String language, {bool isInitial = false}) async {
    if (_isLoadingMore && !isInitial) return;
    if (!_hasMore && !isInitial) return;

    if (mounted) {
      setState(() {
        if (isInitial) {
          _isLoading = true;
        } else {
          _isLoadingMore = true;
        }
      });
    }

    try {
      final result = await _contentService.getPublicFeedPage(
        language: language,
        limit: 50,
        afterAiDoc: _lastAiDoc,
        afterNonAiDoc: _lastNonAiDoc,
        typeFilter: _serverTypeFilter,
      );

      if (mounted) {
        setState(() {
          final uid = FirebaseAuth.instance.currentUser?.uid;
          final filtered = result.items
              .where((c) => c.status == ContentStatus.ready)
              .where((c) => uid == null || c.userId != uid)
              .toList();

          if (isInitial) {
            _allContent = filtered;
          } else {
            _allContent.addAll(filtered);
          }

          if (result.lastAiDoc != null) _lastAiDoc = result.lastAiDoc;
          if (result.lastNonAiDoc != null) _lastNonAiDoc = result.lastNonAiDoc;
          _hasMore = result.hasMore;
          _isLoading = false;
          _isLoadingMore = false;
        });
        _recomputeFilteredContent();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  /// Called when the user scrolls near the bottom.
  void _onScroll() {
    if (!_hasMore || _isLoadingMore || _isLoading) {
      return;
    }

    // 🛡️ GUARD: If the scroll view is empty (fits in viewport with no
    // overflow), there is nothing to paginate. Prevents an infinite
    // request loop when filters produce 0 visible items — without this
    // check, `maxScrollExtent` is ~0, the threshold comparison passes
    // (`0 <= 0 - 300` is false), and `_loadPage` fires repeatedly.
    if (_scrollController.position.maxScrollExtent <= 0) {
      return;
    }

    // 🛡️ GUARD: At least 1 second cooldown between scroll-triggered
    // paginations. Prevents rapid refires when the scroll view is
    // extremely short (e.g., 1 visible item, threshold ~1 pixel).
    if (_lastPaginateTime != null &&
        DateTime.now().difference(_lastPaginateTime!) <
            const Duration(seconds: 1)) {
      return;
    }

    if (_scrollController.position.pixels <=
        _scrollController.position.maxScrollExtent - 300) {
      return;
    }

    _lastPaginateTime = DateTime.now();
    _loadPage(context.read<LanguageManager>().currentLanguage);
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _cachedFilteredContent;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      extendBody: true,
      body: BadyaRefreshIndicator(
        onRefresh: () =>
            _loadData(context.read<LanguageManager>().currentLanguage),
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics(),
          ),
          slivers: [
            // --- Header ---
            CustomAppBar(
              showMenuButton: false,
              showLanguageButton: true,
              onLanguagePressed: _onLanguageTap,
              languageCode:
                  languageCodes[context
                      .watch<LanguageManager>()
                      .currentLanguage],
              actions: [const BalanceWidget()],
            ),

            // --- Search Bar ---
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                child: _buildSearchBar(isDark),
              ).animate().fadeIn(duration: 200.ms),
            ),

            // --- Filter Chips (no "Mine") ---
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
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
                  onFilterChanged: (type) {
                    if (_searchQuery.isNotEmpty) {
                      setState(() {
                        _activeFilterType = type;
                        _searchResults = null;
                      });
                      _recomputeFilteredContent();
                      // Re-trigger server search with the new filter
                      final capturedSequence = ++_querySequenceNumber;
                      _searchTimer?.cancel();
                      _searchTimer = Timer(
                        const Duration(milliseconds: 150),
                        () => _performServerSearch(
                          _searchQuery,
                          capturedSequence,
                        ),
                      );
                    } else {
                      // No active search — reset cursors & content, then
                      // reload from the database with the new filter type.
                      // This prevents cursor pollution (using cursors from
                      // a previous filter's query) and ensures the feed
                      // accurately reflects the selected filter.
                      setState(() {
                        _activeFilterType = type;
                        _lastAiDoc = null;
                        _lastNonAiDoc = null;
                        _hasMore = true;
                        _allContent = [];
                        _cachedFilteredContent = [];
                      });
                      _loadPage(
                        context.read<LanguageManager>().currentLanguage,
                        isInitial: true,
                      );
                    }
                  },
                ),
              ),
            ),

            // --- Searching indicator (server search in progress) ---
            if (_isServerSearching && !_isLoading)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Searching across the library…',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // --- Content Cards / Empty States ---
            if (_isLoading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: LibraryPageSkeleton(),
              )
            else if (filtered.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildEmptyState(context, isDark),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.only(bottom: 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final content = filtered[index];
                    // All visible content is not added in the current language,
                    // so always show as unadded with the "Add" button and
                    // no edit/delete options.

                    // Only real users (non-empty userId) get the block/report
                    // menu — system suggestions have userId == ''.
                    final canModerate = content.userId.isNotEmpty;
                    return LibraryContentCardTall(
                          content: content,
                          onTap: () => _onCardTap(content),
                          onDelete: null,
                          onEdit: null,
                          onBlockUser: canModerate
                              ? () => _onBlockUser(content)
                              : null,
                          onReportUser: canModerate
                              ? () => _onReportUser(content)
                              : null,
                        )
                        .animate()
                        .fadeIn(duration: 300.ms, delay: (index * 50).ms)
                        .slideY(begin: 0.1, end: 0);
                  }, childCount: filtered.length),
                ),
              ),

            // --- Loading Indicator (infinite scroll) ---
            if (_isLoadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
         ),
       ),
    );
  }

  // --- Sub-widgets ---

  Widget _buildSearchBar(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF222220) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0x22FFFFFF) : const Color(0x1A2D3436),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2D3436).withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: const Color(0xFF4ECDC4), size: 20),
          const SizedBox(width: 30),
          Expanded(
            child: TextField(
              controller: _searchController,
              autofocus: false,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Semantic search library...',
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
    _semanticDegradeNotified = false;
    _debounceTimer?.cancel();
    _searchTimer?.cancel();

    final trimmed = query.trim();

    // Increment sequence number first to invalidate any in-flight response
    // before we recompute the filtered content.
    ++_querySequenceNumber;

    setState(() {
      _searchQuery = trimmed;
      // Always clear stale results — they will be replaced by the new query's
      // server response or fall back to the local cache.
      _searchResults = null;
      _isServerSearching = trimmed.isNotEmpty;
      if (trimmed.isEmpty) {
        _queryEmbedding = null;
        _isServerSearching = false;
      }
    });
    _recomputeFilteredContent();

    // Empty query — no semantic embedding or server search needed.
    if (trimmed.isEmpty) return;

    final capturedSequence = _querySequenceNumber;

    // Start server search with a short debounce to batch rapid typing.
    // The server returns hybrid-scored results immediately (no 500ms wait).
    _searchTimer = Timer(const Duration(milliseconds: 150), () {
      _performServerSearch(trimmed, capturedSequence);
    });

    // Also fetch embedding for local semantic fallback (debounced 500ms).
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;
      final embedding = await _fetchQueryEmbedding(trimmed);
      if (!mounted) return;
      // Only apply the embedding if this is still the latest query.
      // Prevents stale embeddings from overwriting newer ones when
      // the user types quickly (race condition).
      if (_querySequenceNumber == capturedSequence) {
        setState(() {
          _queryEmbedding = embedding;
        });
        _recomputeFilteredContent();
      }
    });
  }

  /// Search across the entire library via the backend server.
  ///
  /// The server performs hybrid (semantic + keyword) scoring on all matching
  /// public content and returns items sorted by relevance.  If the server is
  /// unreachable, the results silently degrade to the local-only fallback.
  ///
  /// [sequence] is the captured `_querySequenceNumber` — stale responses are
  /// discarded to prevent race conditions from rapid query changes.
  Future<void> _performServerSearch(String query, int sequence) async {
    if (!mounted) return;
    setState(() => _isServerSearching = true);

    try {
      final result = await _contentService.searchPublicFeed(
        query: query,
        language: context.read<LanguageManager>().currentLanguage,
        limit: 50,
        typeFilter: _serverTypeFilter,
      );

      if (!mounted || _querySequenceNumber != sequence) return;

      setState(() {
        _searchResults =
            result.items.isNotEmpty ? result.items : <UserContent>[];
        _isServerSearching = false;
      });
      _recomputeFilteredContent();
    } catch (e) {
      if (!mounted || _querySequenceNumber != sequence) return;
      setState(() => _isServerSearching = false);
      // Silently fall through — the local `_allContent` cache will be shown
      // via `_computeFilteredContent()` since `_searchResults` is still null.
    }
  }

  Future<List<double>?> _fetchQueryEmbedding(String query) async {
    try {
      final url = Uri.parse('${ApiConfig.getBaseUrl()}/recommendations/embed');
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'title': query,
              'description': '',
              'tags': <String>[],
            }),
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        final list = result['embedding'] as List<dynamic>;
        return list.map((v) => (v as num).toDouble()).toList();
      }
    } catch (e) {
      if (!_semanticDegradeNotified && mounted) {
        _semanticDegradeNotified = true;
        UiUtils.showTopNotification(
          context,
          'Semantic search unavailable — results are keyword-only',
          type: NotificationType.info,
          icon: Icons.search_off_rounded,
        );
      }
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

  Widget _buildEmptyState(BuildContext context, bool isDark) {
    String message;
    String? subMessage;

    if (_searchQuery.isNotEmpty) {
      message = 'No results found';
      subMessage = 'Try adjusting your filter or search terms.';
    } else {
      message = 'No public content yet';
      subMessage = 'Be the first to share content with the community!';
    }

    return EmptyStateWidget(
      key: ValueKey(
        'empty_state_${_activeFilterType}_${_searchQuery.hashCode}',
      ),
      message: message,
      subMessage: subMessage,
    );
  }
}
