import 'dart:math' as math;

import 'package:Badya/models/word_review_state.dart';
import 'package:Badya/services/adk_service.dart';
import 'package:Badya/services/lesson_session_service.dart';
import 'package:Badya/services/vocab_review_service.dart';
import 'package:Badya/services/content_service.dart';
import 'package:Badya/utils/logger.dart';
import 'package:Badya/utils/ui_utils.dart';
import 'package:Badya/voice_chat_page.dart';
import 'package:Badya/widgets/custom_dialog.dart';
import 'package:Badya/widgets/add_words_dialog.dart';
import 'package:Badya/widgets/edit_word_dialog.dart';
import 'package:Badya/config/local_mode.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

/// Filter mode for the topic words list.
enum _TopicWordFilter { all, due, newWords, mastered }

/// Sort mode for the topic words list.
enum _TopicWordSort { priority, alphabetical, dateAdded, nextReview }

class TopicWordsPage extends StatefulWidget {
  final String topicId;
  final String subjectTitle;
  final String description;
  final String currentLanguage;

  const TopicWordsPage({
    super.key,
    required this.topicId,
    required this.subjectTitle,
    required this.description,
    required this.currentLanguage,
  });

  @override
  State<TopicWordsPage> createState() => _TopicWordsPageState();
}

class _TopicWordsPageState extends State<TopicWordsPage> {
  final TextEditingController _searchController = TextEditingController();
  final VocabReviewService _vocabService = VocabReviewService();
  String _searchQuery = '';

  /// All words with their SRS state.
  List<WordReviewState> _words = [];

  bool _isLoading = true;

  /// Whether AI word generation is currently in progress.
  bool _isGenerating = false;

  /// Whether the initial entry animation has completed.
  /// Items scrolled into view after this flag is set won't animate.
  bool _initialAnimationDone = false;

  // ─── Selection mode state ────────────────────────────────────────────
  bool _isSelectionMode = false;
  final Set<int> _selectedIndices = {};

  // ─── Filter & sort ───────────────────────────────────────────────────
  _TopicWordFilter _activeFilter = _TopicWordFilter.all;
  _TopicWordSort _currentSort = _TopicWordSort.priority;

  /// Cached scope ID for the topic.
  late final String _topicScopeId;

  @override
  void initState() {
    super.initState();
    _topicScopeId = VocabReviewService.topicScopeId(
      widget.topicId,
      widget.currentLanguage,
    );
    _searchController.addListener(_onSearchTextChanged);
    _refreshWords();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialAnimationDone = true;
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchTextChanged);
    super.dispose();
    _searchController.dispose();
  }

  void _onSearchTextChanged() {
    _searchQuery = _searchController.text;
    if (mounted) setState(() {});
  }

  // ─── Data loading ────────────────────────────────────────────────────

  Future<void> _refreshWords() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    // Load all words with their SRS state from VocabReviewService
    final words = await _vocabService.getAllWords(
      scope: VocabReviewService.scopeTopic,
      scopeId: _topicScopeId,
    );

    if (mounted) {
      setState(() {
        _words = words;
        _isLoading = false;
      });
    }
  }

  // ─── Fuzzy search helpers ───────────────────────────────────────────

  /// Computes the Levenshtein edit distance between two strings.
  int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final matrix = List.generate(
      a.length + 1,
      (i) => List.filled(b.length + 1, 0),
    );
    for (int i = 0; i <= a.length; i++) {
      matrix[i][0] = i;
    }
    for (int j = 0; j <= b.length; j++) {
      matrix[0][j] = j;
    }

    for (int i = 1; i <= a.length; i++) {
      for (int j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1, // deletion
          matrix[i][j - 1] + 1, // insertion
          matrix[i - 1][j - 1] + cost, // substitution
        ].reduce((a, b) => a < b ? a : b);
      }
    }
    return matrix[a.length][b.length];
  }

  /// Returns a fuzzy match score for a word against the search query.
  /// Higher score = better match. Returns 0 if below threshold.
  double _fuzzyScore(String word, String query) {
    final w = word.toLowerCase();
    final q = query.toLowerCase();

    if (w == q) return 100.0; // exact match
    if (w.startsWith(q)) return 90.0; // prefix match
    if (w.contains(q)) return 80.0; // substring match

    // Levenshtein-based fuzzy match
    final distance = _levenshtein(w, q);
    final maxLen = math.max(w.length, q.length);
    if (maxLen == 0) return 0.0;
    final similarity = 1.0 - (distance / maxLen);

    if (distance <= 2 || similarity >= 0.5) {
      return similarity * 60.0; // score between 0–60 for fuzzy matches
    }

    return 0.0;
  }

  // ─── Filter & sort helpers ───────────────────────────────────────────

  List<WordReviewState> get _filteredWords {
    var result = List<WordReviewState>.from(_words);

    // Apply fuzzy search
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery;
      final scored = result.map((w) {
        final score = _fuzzyScore(w.word, query);
        return MapEntry(w, score);
      }).toList();

      // Filter out non-matches, then sort by relevance (highest score first)
      final matched = scored.where((e) => e.value > 0).toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      result = matched.map((e) => e.key).toList();
    }

    // Apply filter
    switch (_activeFilter) {
      case _TopicWordFilter.due:
        result = result.where((w) => w.isNew || w.isDue).toList();
        break;
      case _TopicWordFilter.newWords:
        result = result.where((w) => w.isNew).toList();
        break;
      case _TopicWordFilter.mastered:
        result = result.where((w) => w.isMastered).toList();
        break;
      case _TopicWordFilter.all:
        break;
    }

    // Apply sort
    switch (_currentSort) {
      case _TopicWordSort.priority:
        result.sort((a, b) {
          int priority(WordReviewState w) {
            if (w.lastRating == 0) return 10;
            if (w.isDue) return 15;
            if (w.isNew) return 20;
            if (w.isSoon) return 30;
            return 100;
          }

          final pa = priority(a);
          final pb = priority(b);
          if (pa != pb) return pa.compareTo(pb);
          return a.word.compareTo(b.word);
        });
        break;
      case _TopicWordSort.alphabetical:
        result.sort((a, b) => a.word.compareTo(b.word));
        break;
      case _TopicWordSort.dateAdded:
        result.sort((a, b) {
          if (a.addedAt == null && b.addedAt == null) return 0;
          if (a.addedAt == null) return 1;
          if (b.addedAt == null) return -1;
          return b.addedAt!.compareTo(a.addedAt!); // newest first
        });
        break;
      case _TopicWordSort.nextReview:
        result.sort((a, b) {
          if (a.nextReviewAt == null && b.nextReviewAt == null) return 0;
          if (a.nextReviewAt == null) return -1;
          if (b.nextReviewAt == null) return 1;
          return a.nextReviewAt!.compareTo(b.nextReviewAt!);
        });
        break;
    }

    return result;
  }

  bool get _isSearching => _searchQuery.isNotEmpty;

  // ─── Status badge ────────────────────────────────────────────────────

  String _statusBadge(WordReviewState s) {
    if (s.isMastered) return '✅ Mastered';
    if (s.isNew) return '⏱ New';
    if (s.isDue) return '🔴 Due now';
    if (s.isSoon) return '🟠 Soon';
    return '🗓 In ${s.interval.toInt()} days';
  }

  Color _statusColor(WordReviewState s) {
    if (s.isMastered) return const Color(0xFF27AE60);
    if (s.isNew) return const Color(0xFF3498DB);
    if (s.isDue) return const Color(0xFFE74C3C);
    if (s.isSoon) return const Color(0xFFF39C12);
    return const Color(0xFF95A5A6);
  }

  // ─── Navigation ──────────────────────────────────────────────────────

  Future<void> _reviewSelected() async {
    final selected = _selectedIndices
        .map((i) => _filteredWords[i].word)
        .toList();
    if (selected.isEmpty) return;
    _exitSelectionMode();
    if (!mounted) return;
    _navigateToWordSmith(selected);
  }

  Future<void> _navigateToWordSmith(List<String> words) async {
    final uid = LocalMode.enabled
        ? LocalMode.guestUid
        : (FirebaseAuth.instance.currentUser?.uid ?? 'default_user');
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VoiceChatPage(
          subjectTitle: widget.subjectTitle,
          storySubject: widget.subjectTitle,
          description: 'Practice vocabulary for ${widget.subjectTitle}',
          agentName: 'Word Smith',
          appName: 'word_smith_agent',
          topicId: widget.topicId,
          userId: uid,
          wordsList: words,
          currentLanguage: widget.currentLanguage,
          lessonType: LessonTypes.wordSmith,
        ),
      ),
    );
    await _refreshWords();
  }

  // ─── Word mutations ──────────────────────────────────────────────────

  Future<void> _markSelectedAsLearned() async {
    final selected = _selectedIndices
        .map((i) => _filteredWords[i].word)
        .toList();
    await _vocabService.markWordsAsLearnedInTopic(
      words: selected,
      topicId: widget.topicId,
      language: widget.currentLanguage,
    );
    _exitSelectionMode();
    _refreshWords();
  }

  Future<void> _resetSelectedProgress() async {
    final selected = _selectedIndices
        .map((i) => _filteredWords[i].word)
        .toList();
    await _vocabService.resetProgressForWordsInTopic(
      words: selected,
      topicId: widget.topicId,
      language: widget.currentLanguage,
    );
    _exitSelectionMode();
    _refreshWords();
  }

  Future<void> _deleteSelected() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => CustomDialog(
        title: 'Delete Selected?',
        content: Text(
          'Are you sure you want to delete ${_selectedIndices.length} items?',
        ),
        saveButtonText: 'Delete',
        saveButtonColor: Colors.red,
        onCancel: () => Navigator.pop(ctx),
        onSave: () {
          Navigator.pop(ctx, true);
        },
      ),
    );
    if (confirmed != true) return;

    final selected = _selectedIndices
        .map((i) => _filteredWords[i].word)
        .toList();
    await _vocabService.deleteWordsFromTopic(
      words: selected,
      topicId: widget.topicId,
      language: widget.currentLanguage,
    );
    _exitSelectionMode();
    _refreshWords();
  }

  Future<void> _deleteAllWords() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => CustomDialog(
        title: 'Clear All Words?',
        content: const Text(
          'Are you sure you want to clear the entire list? This cannot be undone.',
        ),
        saveButtonText: 'Clear All',
        saveButtonColor: Colors.red,
        onCancel: () => Navigator.pop(ctx),
        onSave: () {
          Navigator.pop(ctx, true);
        },
      ),
    );
    if (confirmed != true) return;

    await _vocabService.deleteWordsFromTopic(
      words: _words.map((w) => w.word).toList(),
      topicId: widget.topicId,
      language: widget.currentLanguage,
    );
    _exitSelectionMode();
    _refreshWords();
  }

  Future<void> _editWord(WordReviewState word) async {
    final newWord = await showDialog<String>(
      context: context,
      builder: (_) => EditWordDialog(
        originalWord: word.word,
        existingWords: _words.map((w) => w.word).toSet(),
      ),
    );

    if (newWord == null || !mounted) return;
    await _vocabService.editWordInTopic(
      oldWord: word.word,
      newWord: newWord,
      topicId: widget.topicId,
      language: widget.currentLanguage,
    );
    _refreshWords();
  }

  // ─── Selection helpers ───────────────────────────────────────────────

  void _toggleSelection(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
        if (_selectedIndices.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIndices.add(index);
        _isSelectionMode = true;
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedIndices.clear();
      for (int i = 0; i < _filteredWords.length; i++) {
        _selectedIndices.add(i);
      }
      _isSelectionMode = true;
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectedIndices.clear();
      _isSelectionMode = false;
    });
  }

  // ─── AI word generation ────────────────────────────────────────────

  /// Generate (or regenerate) the topic word list using the AI
  /// word_generator_agent. Silently handled — errors won't block the UI.
  Future<void> _generateWordsWithAI() async {
    if (_isGenerating) return;
    setState(() => _isGenerating = true);

    try {
      final uid = LocalMode.enabled
          ? LocalMode.guestUid
          : FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      // Fetch content to get the difficulty setting
      String difficulty = 'intermediate';
      try {
        // Fetch metadata from ContentService
        final content = await ContentService().getContent(widget.topicId);
        if (content != null) {
          difficulty = content.metadata?['difficulty'] as String? ?? 'intermediate';
        }
      } catch (e) {
        Logger.warn('Failed to fetch content metadata for difficulty: $e');
      }

      await AdkService().generateAndCacheWords(
        topicId: widget.topicId,
        subject: widget.subjectTitle,
        description: widget.description,
        language: widget.currentLanguage,
        difficulty: difficulty,
        userId: uid,
      );

      await _refreshWords();
    } catch (e) {
      if (mounted) {
        UiUtils.showErrorSnackbar(context, 'Word generation failed: $e');
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  // ─── Add words dialog ────────────────────────────────────────────────

  Future<void> _showAddWordsDialog() async {
    final rawText = await showDialog<String>(
      context: context,
      builder: (_) => const AddWordsDialog(),
    );

    if (rawText == null || !mounted || rawText.trim().isEmpty) return;

    final newItems = rawText
        .trim()
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    // Deduplicate
    final existingLower = _words.map((w) => w.word.toLowerCase()).toSet();
    final uniqueNew = newItems
        .where((w) => !existingLower.contains(w.toLowerCase()))
        .toList();

    if (uniqueNew.isNotEmpty) {
      await _vocabService.addWordsToTopic(
        topicId: widget.topicId,
        language: widget.currentLanguage,
        words: uniqueNew,
      );
      _refreshWords();
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filteredWords;
    final bool noSearchResults = _isSearching && filtered.isEmpty;
    final bool isEmpty = _words.isEmpty && !_isLoading;

    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isSelectionMode) _exitSelectionMode();
      },
      child: Scaffold(
        appBar: AppBar(
          title: _isSelectionMode
              ? Text(
                  '${_selectedIndices.length} selected',
                  style: GoogleFonts.nunito(fontWeight: FontWeight.w800),
                )
              : Text(
                  widget.subjectTitle,
                  style: GoogleFonts.nunito(fontWeight: FontWeight.w800),
                ),
          actions: [
            if (_isSelectionMode) ...[
              IconButton(
                icon: const Icon(Icons.select_all_rounded),
                tooltip: 'Select All',
                onPressed: _selectAll,
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: _exitSelectionMode,
              ),
            ] else
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'generate_ai') {
                    _generateWordsWithAI();
                  } else if (value == 'delete_all') {
                    _deleteAllWords();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'generate_ai',
                    child: Row(
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          color: Color(0xFF9B59B6),
                        ),
                        SizedBox(width: 8),
                        Text('Regenerate with AI'),
                      ],
                    ),
                  ),
                  if (_words.isNotEmpty)
                    const PopupMenuItem(
                      value: 'delete_all',
                      child: Row(
                        children: [
                          Icon(Icons.delete_forever_rounded, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Clear All List'),
                        ],
                      ),
                    ),
                ],
                icon: const Icon(Icons.more_vert_rounded),
              ),
          ],
        ),
        body: _isGenerating
            ? _buildGeneratingState(context)
            : _isLoading
            ? const Center(child: CircularProgressIndicator())
            : isEmpty
            ? _buildEmptyState(context)
            : Column(
                children: [
                  // Search bar
                  _buildSearchBar(context, isDark),

                  // Filter chips + sort
                  _buildFilterAndSortRow(context, isDark),

                  // Word list
                  Expanded(
                    child: noSearchResults
                        ? _buildNoResults(context)
                        : _buildWordList(context, filtered, isDark),
                  ),
                ],
              ),
        // ── Bottom Navigation Bar ──
        bottomNavigationBar: _isSelectionMode
            ? _buildSelectionBottomBar(context)
            : null,

        floatingActionButton: !_isSelectionMode
            ? FloatingActionButton(
                onPressed: _showAddWordsDialog,
                backgroundColor: const Color(0xFFFF6B6B),
                child: const Icon(Icons.add_rounded, color: Colors.white),
              )
            : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      ),
    );
  }

  // ─── Search bar ──────────────────────────────────────────────────────

  Widget _buildSearchBar(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _searchController,
        style: GoogleFonts.nunito(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search words...',
          hintStyle: GoogleFonts.nunito(
            fontSize: 14,
            color: Theme.of(
              context,
            ).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: Theme.of(context).iconTheme.color,
          ),
          suffixIcon: _isSearching
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  onPressed: () => _searchController.clear(),
                )
              : null,
          filled: true,
          fillColor: Theme.of(context).dividerColor.withValues(alpha: 0.08),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  // ─── Filter chips + Sort dropdown ────────────────────────────────────

  Widget _buildFilterAndSortRow(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          // Filter chips
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip('All', _TopicWordFilter.all),
                  const SizedBox(width: 6),
                  _buildFilterChip('Due', _TopicWordFilter.due),
                  const SizedBox(width: 6),
                  _buildFilterChip('New', _TopicWordFilter.newWords),
                  const SizedBox(width: 6),
                  _buildFilterChip('Mastered', _TopicWordFilter.mastered),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Sort icon button in circle
          Tooltip(
            message: 'Sort by…',
            child: PopupMenuButton<_TopicWordSort>(
              onSelected: (value) => setState(() => _currentSort = value),
              offset: const Offset(0, 40),
              color: isDark ? const Color(0xFF1E1B4B) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _TopicWordSort.priority,
                  child: _buildSortMenuItem(
                    'Priority',
                    Icons.trending_up_rounded,
                    _currentSort == _TopicWordSort.priority,
                  ),
                ),
                PopupMenuItem(
                  value: _TopicWordSort.alphabetical,
                  child: _buildSortMenuItem(
                    'A–Z',
                    Icons.sort_by_alpha_rounded,
                    _currentSort == _TopicWordSort.alphabetical,
                  ),
                ),
                PopupMenuItem(
                  value: _TopicWordSort.dateAdded,
                  child: _buildSortMenuItem(
                    'Date added',
                    Icons.calendar_today_rounded,
                    _currentSort == _TopicWordSort.dateAdded,
                  ),
                ),
                PopupMenuItem(
                  value: _TopicWordSort.nextReview,
                  child: _buildSortMenuItem(
                    'Next review',
                    Icons.schedule_rounded,
                    _currentSort == _TopicWordSort.nextReview,
                  ),
                ),
              ],
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.grey.shade100,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.15)
                        : Colors.grey.shade300,
                  ),
                ),
                child: const Icon(Icons.sort_rounded, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortMenuItem(String label, IconData icon, bool isActive) {
    return Row(
      children: [
        Icon(icon, size: 18, color: isActive ? const Color(0xFF4ECDC4) : null),
        const SizedBox(width: 10),
        Text(
          label,
          style: GoogleFonts.nunito(
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
            color: isActive ? const Color(0xFF4ECDC4) : null,
          ),
        ),
        if (isActive) ...[
          const Spacer(),
          const Icon(Icons.check_rounded, size: 16, color: Color(0xFF4ECDC4)),
        ],
      ],
    );
  }

  Widget _buildFilterChip(String label, _TopicWordFilter filter) {
    final isActive = _activeFilter == filter;
    return GestureDetector(
      onTap: () => setState(() => _activeFilter = filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF4ECDC4).withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? const Color(0xFF4ECDC4)
                : Theme.of(context).dividerColor.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.nunito(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
            color: isActive
                ? const Color(0xFF4ECDC4)
                : Theme.of(context).textTheme.bodyMedium?.color,
          ),
        ),
      ),
    );
  }

  // ─── Word list ───────────────────────────────────────────────────────

  Widget _buildWordList(
    BuildContext context,
    List<WordReviewState> filtered,
    bool isDark,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final wordState = filtered[index];
        final isSelected = _selectedIndices.contains(index);

        final item = Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GestureDetector(
            onLongPress: _isSelectionMode
                ? null
                : () => _toggleSelection(index),
            onTap: _isSelectionMode ? () => _toggleSelection(index) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF4ECDC4).withValues(alpha: 0.1)
                    : isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Theme.of(context).cardTheme.color,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF4ECDC4)
                      : isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                child: Row(
                  children: [
                    // Selection checkbox
                    if (_isSelectionMode)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Icon(
                          isSelected
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: const Color(0xFF4ECDC4),
                          size: 22,
                        ),
                      ),

                    // Word info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            wordState.word,
                            style: GoogleFonts.nunito(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(
                                context,
                              ).textTheme.bodyLarge?.color,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // SRS status badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _statusColor(
                                wordState,
                              ).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _statusBadge(wordState),
                              style: GoogleFonts.nunito(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _statusColor(wordState),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Trailing actions
                    if (!_isSelectionMode) ...[
                      // Edit button
                      IconButton(
                        icon: const Icon(Icons.edit_rounded, size: 20),
                        color: Theme.of(
                          context,
                        ).iconTheme.color?.withValues(alpha: 0.6),
                        onPressed: () => _editWord(wordState),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 36,
                          minHeight: 36,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
        if (!_initialAnimationDone) {
          return item.animate().fadeIn(delay: (20 * index).ms).slideX();
        }
        return item;
      },
    );
  }

  // ─── Selection bottom bar ────────────────────────────────────────────

  Widget _buildSelectionBottomBar(BuildContext context) {
    final selectedCount = _selectedIndices.length;
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Review Selected
            _buildActionChip(
              icon: Icons.play_arrow_rounded,
              label: 'Review ($selectedCount)',
              color: const Color(0xFF4ECDC4),
              onTap: _reviewSelected,
            ),
            const SizedBox(width: 8),
            // Mark Learned
            _buildActionChip(
              icon: Icons.check_rounded,
              label: 'Learned',
              color: const Color(0xFF27AE60),
              onTap: _markSelectedAsLearned,
            ),
            const SizedBox(width: 8),
            // Reset Progress
            _buildActionChip(
              icon: Icons.refresh_rounded,
              label: 'Reset',
              color: const Color(0xFFF39C12),
              onTap: _resetSelectedProgress,
            ),
            const SizedBox(width: 8),
            // Delete
            _buildActionChip(
              icon: Icons.delete_rounded,
              label: 'Delete',
              color: Colors.red,
              onTap: _deleteSelected,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                style: GoogleFonts.nunito(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Empty states ────────────────────────────────────────────────────

  Widget _buildEmptyState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFF9B59B6).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                size: 32,
                color: Color(0xFF9B59B6),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No words yet',
              style: GoogleFonts.nunito(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Generate vocabulary with AI or tap + to add words manually.',
              style: GoogleFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _generateWordsWithAI,
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text(
                'Generate with AI',
                style: GoogleFonts.nunito(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF9B59B6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneratingState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF9B59B6).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Padding(
                padding: EdgeInsets.all(18),
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Color(0xFF9B59B6),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Generating vocabulary...',
              style: GoogleFonts.nunito(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This may take a moment.',
              style: GoogleFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResults(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No words match "$_searchQuery".',
              style: GoogleFonts.nunito(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Theme.of(
                  context,
                ).textTheme.bodyMedium?.color?.withValues(alpha: 0.8),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
