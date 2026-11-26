import 'package:Badya/models/word_review_state.dart';
import 'package:Badya/services/lesson_session_service.dart';
import 'package:Badya/services/vocab_review_service.dart';
import 'package:Badya/utils/weighted_selection.dart';
import 'package:Badya/voice_chat_page.dart';
import 'package:Badya/models/transaction_model.dart';
import 'package:Badya/services/coin_service.dart';
import 'package:Badya/widgets/add_words_dialog.dart';
import 'package:Badya/widgets/edit_word_dialog.dart';
import 'package:Badya/widgets/custom_dialog.dart';
import 'package:Badya/widgets/empty_state_widget.dart';
import 'package:Badya/widgets/insufficient_balance_dialog.dart';
import 'package:Badya/widgets/word_unscramble_game.dart';
import 'package:Badya/wallet_page.dart';
import 'package:Badya/config/local_mode.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Filter mode for the strange words list.
enum _WordFilter { all, due, newWords, mastered }

/// Sort mode for the strange words list.
enum _WordSort { priority, alphabetical, dateAdded, nextReview }

class StrangeWordsPage extends StatefulWidget {
  final String language;

  const StrangeWordsPage({super.key, required this.language});

  @override
  State<StrangeWordsPage> createState() => _StrangeWordsPageState();
}

class _StrangeWordsPageState extends State<StrangeWordsPage> {
  final TextEditingController _searchController = TextEditingController();
  final VocabReviewService _vocabService = VocabReviewService();
  String _searchQuery = '';

  /// All words with their SRS state.
  List<WordReviewState> _words = [];

  /// Due count for the button badge.
  int _dueCount = 0;

  /// Whether the initial entry animation has completed.
  /// Items scrolled into view after this flag is set won't animate.
  bool _initialAnimationDone = false;

  bool _isLoading = true;

  /// Guards against duplicate taps while session creation / payment is in flight.
  bool _isStartingLesson = false;

  // ─── Selection mode state ────────────────────────────────────────────
  bool _isSelectionMode = false;
  final Set<int> _selectedIndices = {};

  // ─── Filter & sort ───────────────────────────────────────────────────
  _WordFilter _activeFilter = _WordFilter.all;
  _WordSort _currentSort = _WordSort.priority;

  // ─── Session limits (separate for game & voice review) ───────────────

  /// SharedPreferences keys for the per-path card limits.
  static const _gameLimitKey = 'strange_words_game_limit';
  static const _voiceLimitKey = 'strange_words_voice_limit';

  /// Legacy combined key from earlier builds — kept as a fallback so a
  /// previously saved value migrates to both paths.
  static const _legacySessionLimitKey = 'strange_words_session_limit';

  /// Maximum cards per "Play Game" session (default 20).
  int _gameLimit = 20;

  /// Maximum cards per "Voice Review" session (default 10).
  int _voiceLimit = 10;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchTextChanged);
    _refreshWords();
    _loadSessionLimits();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialAnimationDone = true;
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchTextChanged);
    // Dispose controller AFTER super.dispose() so any pending update
    // callbacks during disposal can still safely access it.
    super.dispose();
    _searchController.dispose();
  }

  void _onSearchTextChanged() {
    _searchQuery = _searchController.text;
    if (mounted) setState(() {});
  }

  // ─── Session limit settings ──────────────────────────────────────────

  Future<void> _loadSessionLimits() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final legacy = prefs.getInt(_legacySessionLimitKey);
      setState(() {
        _gameLimit = prefs.getInt(_gameLimitKey) ?? legacy ?? 20;
        _voiceLimit = prefs.getInt(_voiceLimitKey) ?? legacy ?? 10;
      });
    } catch (e) {
      // Keep the defaults when preferences are unavailable.
    }
  }

  Future<void> _showSessionLimitDialog() async {
    final gameController = TextEditingController(text: '$_gameLimit');
    final voiceController = TextEditingController(text: '$_voiceLimit');
    final formKey = GlobalKey<FormState>();

    String? validate(String? value) {
      final n = int.tryParse(value ?? '') ?? 0;
      if (n < 1 || n > 500) return 'Enter a number between 1 and 500';
      return null;
    }

    final limits = await showDialog<({int game, int voice})>(
      context: context,
      builder: (ctx) => CustomDialog(
        title: 'Settings',
        content: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Maximum number of cards per session, picked at random from ',
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                  color: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.color?.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 16),
              _buildNumberStepper(
                label: 'Game',
                helper: '',
                controller: gameController,
                validator: validate,
              ),
              _buildNumberStepper(
                label: 'Voice review',
                helper: '',
                controller: voiceController,
                validator: validate,
              ),
            ],
          ),
        ),
        saveButtonText: 'Save',
        onCancel: () => Navigator.pop(ctx),
        onSave: () {
          if (formKey.currentState?.validate() ?? false) {
            Navigator.pop(ctx, (
              game: int.parse(gameController.text),
              voice: int.parse(voiceController.text),
            ));
          }
        },
      ),
    );

    if (limits == null || !mounted) return;
    setState(() {
      _gameLimit = limits.game;
      _voiceLimit = limits.voice;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_gameLimitKey, limits.game);
      await prefs.setInt(_voiceLimitKey, limits.voice);
    } catch (e) {
      // Persisting is best-effort; the in-memory values already apply.
    }
  }

  /// Numeric input with up/down arrows to increase or decrease the value.
  Widget _buildNumberStepper({
    required String label,
    required String helper,
    required TextEditingController controller,
    required String? Function(String?) validator,
  }) {
    void bump(int delta) {
      final current = int.tryParse(controller.text) ?? 0;
      var next = current + delta;
      if (next < 1) next = 1;
      if (next > 500) next = 500;
      controller.text = '$next';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              autovalidateMode: AutovalidateMode.onUserInteraction,
              style: GoogleFonts.nunito(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
              validator: validator,
              decoration: InputDecoration(
                labelText: label,
                labelStyle: GoogleFonts.nunito(fontWeight: FontWeight.w600),
                helperText: helper,
                helperStyle: GoogleFonts.nunito(fontSize: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Up / down arrows to increase or decrease the value.
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 40,
                height: 30,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  iconSize: 28,
                  tooltip: 'Increase',
                  icon: const Icon(Icons.keyboard_arrow_up_rounded),
                  onPressed: () => bump(1),
                ),
              ),
              SizedBox(
                width: 40,
                height: 30,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  iconSize: 28,
                  tooltip: 'Decrease',
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  onPressed: () => bump(-1),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// SRS weight for weighted-random session selection — harder words are
  /// picked more often: Forgotten 6×, New 4×, Due 3×, Soon 2×, Fresh 1×,
  /// Mastered 0.5×.
  double _srsWeight(WordReviewState w) {
    if (w.lastRating == 0) return 6; // Forgot — hardest
    if (w.isNew) return 4; // Never reviewed
    if (w.isDue) return 3; // Overdue
    if (w.isSoon) return 2; // Due within 24h
    if (w.isMastered) return 0.5; // Long interval — easiest
    return 1; // Reviewed, not due yet
  }

  /// Randomly caps [words] to [limit] cards, weighting the selection by SRS
  /// difficulty so difficult words are picked more often than easy ones
  /// (Efraimidis–Spirakis sampling without replacement).
  List<String> _capToSessionLimit(List<WordReviewState> words, int limit) {
    if (words.length <= limit) return words.map((w) => w.word).toList();
    final picked = weightedSample(words, _srsWeight, limit);
    return picked.map((w) => w.word).toList();
  }

  // ─── Data loading ────────────────────────────────────────────────────

  Future<void> _refreshWords() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    // Load all words with their SRS state from VocabReviewService
    final results = await Future.wait([
      _vocabService.getAllWords(
        scope: VocabReviewService.scopeStrangeWords,
        scopeId: widget.language,
      ),
      _vocabService.getDueCount(widget.language),
    ]);

    final words = results[0] as List<WordReviewState>;
    final dueCount = results[1] as int;

    if (mounted) {
      setState(() {
        _words = words;
        _dueCount = dueCount;
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
    final maxLen = w.length > q.length ? w.length : q.length;
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
      case _WordFilter.due:
        result = result.where((w) => w.isNew || w.isDue).toList();
        break;
      case _WordFilter.newWords:
        result = result.where((w) => w.isNew).toList();
        break;
      case _WordFilter.mastered:
        result = result.where((w) => w.isMastered).toList();
        break;
      case _WordFilter.all:
        break;
    }

    // Apply sort
    switch (_currentSort) {
      case _WordSort.priority:
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
      case _WordSort.alphabetical:
        result.sort((a, b) => a.word.compareTo(b.word));
        break;
      case _WordSort.dateAdded:
        result.sort((a, b) {
          if (a.addedAt == null && b.addedAt == null) return 0;
          if (a.addedAt == null) return 1;
          if (b.addedAt == null) return -1;
          return b.addedAt!.compareTo(a.addedAt!); // newest first
        });
        break;
      case _WordSort.nextReview:
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

  Future<void> _reviewDueWords() async {
    // Pull a large pool of due words, then SRS-weight the random pick down
    // to the voice limit — forgotten words surface far more often than
    // fresh ones.
    final dueWords = await _vocabService.getDueStrangeWords(
      widget.language,
      maxCards: 1000,
    );
    if (!mounted || dueWords.isEmpty) return;
    final words = _capToSessionLimit(dueWords, _voiceLimit);
    if (words.isEmpty) return;
    _navigateToWordSmith(words);
  }

  Future<void> _reviewSelected() async {
    final selected = _selectedIndices
        .map((i) => _filteredWords[i].word)
        .toList();
    if (selected.isEmpty) return;
    _exitSelectionMode();
    if (!mounted) return;
    _navigateToWordSmith(selected);
  }

  void _playUnscrambleGame({List<String>? words}) {
    // Explicitly selected words are used as-is; starting a session from the
    // "Play Game" button SRS-weights a random pick down to the game limit.
    final wordsToPlay = (words != null && words.isNotEmpty)
        ? words
        : _capToSessionLimit(_words, _gameLimit);
    if (wordsToPlay.isEmpty) return;

    if (_isSelectionMode) {
      _exitSelectionMode();
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          appBar: AppBar(
            title: Text(
              'Word Unscramble',
              style: GoogleFonts.nunito(fontWeight: FontWeight.w800),
            ),
          ),
          body: SafeArea(
            child: WordUnscrambleGame(
              words: wordsToPlay,
              isStandalone: true,
              language: widget.language,
              onBack: () => Navigator.pop(ctx),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _navigateToWordSmith(List<String> words) async {
    if (_isStartingLesson) return;
    _isStartingLesson = true;

    try {
      final uid = LocalMode.enabled
          ? LocalMode.guestUid
          : FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      // Check coin balance before starting Word Smith practice (ContentType.wordSmith)
      final coinService = CoinService();
      final accessResult = await coinService.canAccessContent(
        ContentType.wordSmith,
      );

      if (!accessResult.canAccess) {
        if (mounted) {
          showInsufficientBalanceDialog(
            context: context,
            contentType: ContentType.wordSmith,
            contentTitle: 'Strange Words Practice',
            currentBalance: accessResult.currentBalance ?? 0,
            actualCost: accessResult.cost,
            onBuyCoins: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WalletPage()),
              );
            },
            onViewStore: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WalletPage()),
              );
            },
          );
        }
        return;
      }

      // Spend the coins
      final spendResult = await coinService.spendForContent(
        ContentType.wordSmith,
        'strange_words_${widget.language}',
      );
      if (!spendResult.success) return;

      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VoiceChatPage(
            subjectTitle: '',
            description: 'Practice your difficult words in ${widget.language}',
            agentName: 'Word Smith',
            appName: 'word_smith_agent',
            topicId: 'strange_words_${widget.language}',
            userId: uid,
            wordsList: words,
            currentLanguage: widget.language,
            lessonType: LessonTypes.wordSmith,
          ),
        ),
      );
      await _refreshWords();
    } finally {
      _isStartingLesson = false;
    }
  }

  // ─── Word mutations ──────────────────────────────────────────────────

  Future<void> _markSelectedAsLearned() async {
    final selected = _selectedIndices
        .map((i) => _filteredWords[i].word)
        .toList();
    await _vocabService.markWordsAsLearned(selected, widget.language);
    _exitSelectionMode();
    _refreshWords();
  }

  Future<void> _resetSelectedProgress() async {
    final selected = _selectedIndices
        .map((i) => _filteredWords[i].word)
        .toList();
    await _vocabService.resetProgressForWords(selected, widget.language);
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
    await _vocabService.deleteWords(selected, widget.language);
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
    await _vocabService.editWord(
      oldWord: word.word,
      newWord: newWord,
      language: widget.language,
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
      await _vocabService.addWords(words: uniqueNew, language: widget.language);
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
                  'Strange Words',
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
            ] else ...[
              IconButton(
                icon: const Icon(Icons.tune_rounded),
                tooltip: 'Session settings',
                onPressed: _showSessionLimitDialog,
              ),
            ],
          ],
        ),
        body: _isLoading
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
            : (_words.isNotEmpty ? _buildReviewButton(context, isDark) : null),

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
          hintText: 'Search strange words...',
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
                  _buildFilterChip('All', _WordFilter.all),
                  const SizedBox(width: 6),
                  _buildFilterChip('Due', _WordFilter.due),
                  const SizedBox(width: 6),
                  _buildFilterChip('New', _WordFilter.newWords),
                  const SizedBox(width: 6),
                  _buildFilterChip('Mastered', _WordFilter.mastered),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Sort icon button in circle
          Tooltip(
            message: 'Sort by…',
            child: PopupMenuButton<_WordSort>(
              onSelected: (value) => setState(() => _currentSort = value),
              offset: const Offset(0, 40),
              color: isDark ? const Color(0xFF1E1B4B) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _WordSort.priority,
                  child: _buildSortMenuItem(
                    'Priority',
                    Icons.trending_up_rounded,
                    _currentSort == _WordSort.priority,
                  ),
                ),
                PopupMenuItem(
                  value: _WordSort.alphabetical,
                  child: _buildSortMenuItem(
                    'A–Z',
                    Icons.sort_by_alpha_rounded,
                    _currentSort == _WordSort.alphabetical,
                  ),
                ),
                PopupMenuItem(
                  value: _WordSort.dateAdded,
                  child: _buildSortMenuItem(
                    'Date added',
                    Icons.calendar_today_rounded,
                    _currentSort == _WordSort.dateAdded,
                  ),
                ),
                PopupMenuItem(
                  value: _WordSort.nextReview,
                  child: _buildSortMenuItem(
                    'Next review',
                    Icons.schedule_rounded,
                    _currentSort == _WordSort.nextReview,
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

  Widget _buildFilterChip(String label, _WordFilter filter) {
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

  // ─── Review button ───────────────────────────────────────────────────

  Widget _buildReviewButton(BuildContext context, bool isDark) {
    final canReview = _dueCount > 0;
    final coinCost = ContentType.wordSmith.costFor();
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // ── Play Game Free ──
            Expanded(
              flex: 5,
              child: OutlinedButton.icon(
                onPressed: _words.isNotEmpty ? () => _playUnscrambleGame() : null,
                icon: const Icon(Icons.extension_rounded, size: 20),
                label: Text(
                  'Unscramble\n(Free)',
                  style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4ECDC4),
                  side: const BorderSide(color: Color(0xFF4ECDC4), width: 1.8),
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // ── Voice Review (with coins) ──
            Expanded(
              flex: 6,
              child: ElevatedButton(
                onPressed: canReview ? _reviewDueWords : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: canReview
                      ? const Color(0xFF4ECDC4)
                      : Colors.grey.shade400,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  disabledForegroundColor: Colors.white70,
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      canReview
                          ? Icons.mic_rounded
                          : Icons.check_circle_rounded,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        canReview ? 'Voice\nReview' : 'Caught up! ✅',
                        style: GoogleFonts.nunito(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          stops: const [0.0, 0.5, 1.0],
                          colors: [
                            isDark
                                ? const Color(0xFF2A2A28)
                                : const Color(0xFFF8F6F3),
                            isDark
                                ? const Color(0xFF222220)
                                : const Color(0xFFF3EFE9),
                            isDark
                                ? const Color(0xFF2A2A28)
                                : const Color(0xFFF8F6F3),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFFFFD93D).withValues(alpha: 0.25)
                              : const Color(0x1A2D3436),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            const IconData(0xe800, fontFamily: 'MyFlutterApp'),
                            size: 16,
                            color: isDark
                                ? const Color(0xFFFFD93D)
                                : const Color(0xFFF5A623),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '$coinCost',
                            style: GoogleFonts.nunito(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: isDark
                                  ? const Color(0xFFFFD93D)
                                  : const Color(0xFF2A2A28),
                            ),
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
    );
  }

  // ─── Selection bottom bar ────────────────────────────────────────────

  Widget _buildSelectionBottomBar(BuildContext context) {
    final selectedCount = _selectedIndices.length;
    final selectedWords = _selectedIndices
        .map((i) => _filteredWords[i].word)
        .toList();

    return Container(
      padding: EdgeInsets.fromLTRB(
        8,
        8,
        8,
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
            // Play Selected (Free)
            _buildActionChip(
              icon: Icons.extension_rounded,
              label: 'Game ($selectedCount)',
              color: const Color(0xFF9B51E0),
              onTap: () => _playUnscrambleGame(words: selectedWords),
            ),
            const SizedBox(width: 6),
            // Voice Review Selected
            _buildActionChip(
              icon: Icons.mic_rounded,
              label: 'Voice ($selectedCount)',
              color: const Color(0xFF4ECDC4),
              onTap: _reviewSelected,
            ),
            const SizedBox(width: 6),
            // Mark Learned
            _buildActionChip(
              icon: Icons.check_rounded,
              label: 'Learned',
              color: const Color(0xFF27AE60),
              onTap: _markSelectedAsLearned,
            ),
            const SizedBox(width: 6),
            // Reset Progress
            _buildActionChip(
              icon: Icons.refresh_rounded,
              label: 'Reset',
              color: const Color(0xFFF39C12),
              onTap: _resetSelectedProgress,
            ),
            const SizedBox(width: 6),
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
    return const EmptyStateWidget(
      message: 'No strange words yet',
      subMessage: 'Tap + to add words from your lessons or type them in.',
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
