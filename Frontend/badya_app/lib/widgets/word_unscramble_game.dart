import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:Badya/services/app_review_prompt_service.dart';
import 'package:Badya/services/user_preferences_service.dart';
import 'package:Badya/utils/score_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A Word Unscramble mini-game shown while the user waits for video generation.
///
/// Items in [words] can be single words (unscrambled by letter) or sentences
/// (unscrambled by word). The game auto-detects which mode to use based on
/// whether the item contains spaces.
class WordUnscrambleGame extends StatefulWidget {
  /// Topic vocabulary list — can contain single words and/or sentences.
  final List<String> words;

  /// Whether the video has finished generating.
  final bool videoReady;

  /// Called when the user taps the "Video Ready" banner.
  final VoidCallback? onVideoReady;

  /// Called when the user taps the back button.
  final VoidCallback? onBack;

  /// Expected duration for generating video (defaults to 6 minutes).
  final Duration expectedDuration;

  /// Whether this game is run in standalone practice mode (e.g. from Strange Words)
  /// rather than during video generation.
  final bool isStandalone;

  /// Optional title for the header or empty state.
  final String? title;

  /// The learning-language context — used to persist earned XP to the
  /// user's per-language XP bucket and daily activity. When null, the
  /// user's current language is resolved from preferences.
  final String? language;

  /// Optional session and topic IDs to save and restore loading progress.
  final String? sessionId;
  final String? topicId;

  const WordUnscrambleGame({
    super.key,
    required this.words,
    this.videoReady = false,
    this.expectedDuration = const Duration(minutes: 6),
    this.onVideoReady,
    this.onBack,
    this.isStandalone = false,
    this.title,
    this.language,
    this.sessionId,
    this.topicId,
  });

  @override
  State<WordUnscrambleGame> createState() => _WordUnscrambleGameState();
}

class _WordUnscrambleGameState extends State<WordUnscrambleGame>
    with TickerProviderStateMixin {
  // ─── Game state ──────────────────────────────────────────────────────
  late List<String> _filteredWords;
  int _currentIndex = 0;
  int _xp = 0;
  bool _usedHintOrSkip = false;

  /// Indices of cards solved in this session (standalone mode only).
  final Set<int> _solvedIndices = {};

  /// Whether the completion celebration overlay is showing.
  bool _celebrating = false;

  /// Guards against popping the page more than once.
  bool _closed = false;

  /// The pieces (letters or words) that the user can pick from.
  List<_Piece> _availablePieces = [];

  /// Slot-based answer: each index maps to a placed piece (or null if empty).
  /// This enables Wordle-style per-position validation.
  List<_Piece?> _slots = [];

  /// Whether the current item is a sentence (word-level) or word (letter-level).
  bool _isSentenceMode = false;

  /// The correct answer pieces in order, for validation.
  List<String> _correctOrder = [];

  /// Per-slot validation state: true = correct position, false = wrong, null = not yet validated.
  List<bool?> _slotValidation = [];

  /// Tracks whether XP popup should be shown.
  bool _showXpPopup = false;
  int _lastXpEarned = 0;

  // ─── Feedback state ──────────────────────────────────────────────────
  bool _showCorrect = false;
  bool _showWrong = false;

  // ─── Motivational messages ────────────────────────────────────────────
  static const _motivationMessages = [
    '🎮 Play while waiting, or leave freely — we will notify you when it finishes!',
    '⚡ Waiting goes faster when your brain is working!',
    '🧠 Sharpen your mind while your video renders!',
    '🎯 Every word you solve earns XP!',
    '💪 You can stay and practice or leave — we will notify you when it is ready!',
    '🚀 Brain training in progress...',
  ];
  late String _currentMotivation;

  // ─── Animations & Audio ──────────────────────────────────────────────
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;
  late AnimationController _progressController;
  late AnimationController _successController;
  late AudioPlayer _audioPlayer;

  final _random = Random();

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();

    _filteredWords = widget.words
        .where((w) => w.trim().isNotEmpty)
        .toList();

    // Shuffle so the order isn't always the same
    _filteredWords.shuffle(_random);

    _currentMotivation =
        _motivationMessages[_random.nextInt(_motivationMessages.length)];

    _progressController = AnimationController(
      vsync: this,
      duration: widget.expectedDuration,
    )..animateTo(0.95);

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: 10), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 10, end: -10), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -10, end: 8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8, end: -5), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -5, end: 0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.easeInOut,
    ));

    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    if (_filteredWords.isNotEmpty) {
      _loadCurrentWord();
    }

    if (!widget.isStandalone) {
      _restoreLoadingGameState();
    }
  }

  String? get _storageKey {
    final id = widget.sessionId ?? widget.topicId;
    if (id == null || id.isEmpty) return null;
    return 'unscramble_loading_state_$id';
  }

  Future<void> _restoreLoadingGameState() async {
    final key = _storageKey;
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return;

      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (!mounted) return;

      setState(() {
        _xp = data['xp'] as int? ?? _xp;
        _currentIndex = data['currentIndex'] as int? ?? _currentIndex;
        final solved = (data['solvedIndices'] as List<dynamic>?)
            ?.map((e) => e as int)
            .toSet();
        if (solved != null) {
          _solvedIndices.addAll(solved);
        }
      });

      final startTimeMs = data['startTimeMs'] as int?;
      if (startTimeMs != null) {
        final elapsed = DateTime.now().millisecondsSinceEpoch - startTimeMs;
        final totalDurationMs = widget.expectedDuration.inMilliseconds;
        if (totalDurationMs > 0) {
          final progress = (elapsed / totalDurationMs).clamp(0.0, 0.95);
          _progressController.value = progress;
          _progressController.animateTo(
            0.95,
            duration: Duration(
              milliseconds: (totalDurationMs * (0.95 - progress)).toInt().clamp(0, totalDurationMs),
            ),
          );
        }
      }

      _loadCurrentWord();
    } catch (e) {
      // Ignore restore errors gracefully
    }
  }

  Future<void> _saveLoadingGameState() async {
    if (widget.isStandalone) return;
    final key = _storageKey;
    if (key == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingRaw = prefs.getString(key);
      int startTimeMs = DateTime.now().millisecondsSinceEpoch;
      if (existingRaw != null && existingRaw.isNotEmpty) {
        try {
          final existing = jsonDecode(existingRaw) as Map<String, dynamic>;
          startTimeMs = existing['startTimeMs'] as int? ?? startTimeMs;
        } catch (_) {}
      }

      final payload = jsonEncode({
        'xp': _xp,
        'currentIndex': _currentIndex,
        'solvedIndices': _solvedIndices.toList(),
        'startTimeMs': startTimeMs,
      });
      await prefs.setString(key, payload);
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant WordUnscrambleGame oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If video became ready, complete progress and trigger haptic
    if (widget.videoReady && !oldWidget.videoReady) {
      _progressController.animateTo(1.0, duration: const Duration(milliseconds: 400));
      HapticFeedback.mediumImpact();
    }
  }

  @override
  void dispose() {
    _progressController.dispose();
    _shakeController.dispose();
    _successController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  // ─── Game logic ────────────────────────────────────────────────────────

  void _loadCurrentWord() {
    if (_filteredWords.isEmpty) return;
    if (_currentIndex >= _filteredWords.length) _currentIndex = 0;

    // Standalone sessions walk the list linearly (skipping already solved
    // cards); video-generation mode cycles forever with modulo.
    final item = widget.isStandalone
        ? _filteredWords[_currentIndex].trim()
        : _filteredWords[_currentIndex % _filteredWords.length].trim();

    // Determine mode: sentence if it contains spaces AND more than 1 word
    final words = item.split(RegExp(r'\s+'));
    _isSentenceMode = words.length > 1;

    if (_isSentenceMode) {
      _correctOrder = words.toList();
      _availablePieces = List.generate(
        words.length,
        (i) => _Piece(id: i, text: words[i]),
      );
    } else {
      final letters = item.split('');
      _correctOrder = letters.toList();
      _availablePieces = List.generate(
        letters.length,
        (i) => _Piece(id: i, text: letters[i]),
      );
    }

    // Shuffle until the order is actually different from the correct one
    // (avoid presenting an already-solved puzzle)
    int attempts = 0;
    do {
      _availablePieces.shuffle(_random);
      attempts++;
    } while (
      _availablePieces.map((p) => p.text).toList().join() ==
          _correctOrder.join() &&
      attempts < 10 &&
      _correctOrder.length > 1
    );

    // Initialize empty slots matching the correct answer length
    _slots = List.filled(_correctOrder.length, null);
    _slotValidation = List.filled(_correctOrder.length, null);
    _showCorrect = false;
    _showWrong = false;
    _usedHintOrSkip = false;
    _showXpPopup = false;
  }

  void _onPieceTapped(_Piece piece) {
    if (_showCorrect) return; // Don't allow taps during success animation
    HapticFeedback.selectionClick();

    setState(() {
      // Find the first empty slot
      final emptyIndex = _slots.indexOf(null);
      if (emptyIndex == -1) return; // All slots filled

      _availablePieces.remove(piece);
      _slots[emptyIndex] = piece;
      // Do not reveal correctness while still typing; keep unvalidated
      _slotValidation[emptyIndex] = null;
    });

    // Check if all slots are filled - only now do we reveal feedback!
    if (!_slots.contains(null)) {
      _checkAnswer();
    }
  }

  void _onPlacedPieceTapped(int slotIndex) {
    if (_showCorrect) return;
    final piece = _slots[slotIndex];
    if (piece == null) return;

    HapticFeedback.selectionClick();
    setState(() {
      _slots[slotIndex] = null;
      _slotValidation[slotIndex] = null;
      _availablePieces.add(piece);
    });
  }

  void _checkAnswer() {
    final userAnswer = _slots.map((p) => p?.text ?? '').toList();
    final isCorrect = _listsEqual(userAnswer, _correctOrder);

    // Evaluate each slot's position now that the user submitted all bubbles
    setState(() {
      for (int i = 0; i < _slots.length; i++) {
        _slotValidation[i] = _slots[i]?.text == _correctOrder[i];
      }
    });

    if (isCorrect) {
      // Play celebration sound
      _audioPlayer.play(AssetSource('sounds/success.wav'));
      HapticFeedback.vibrate();
      final earned = _usedHintOrSkip ? 1 : 2;
      setState(() {
        _showCorrect = true;
        _xp += earned;
        _lastXpEarned = earned;
        _showXpPopup = true;
        _solvedIndices.add(_currentIndex % _filteredWords.length);
      });
      _successController.forward(from: 0);

      // Persist to the user's real XP (total, per-language, daily activity)
      // so the profile, level, and streak reflect the in-game badge.
      _awardPersistedXp(earned);
      _saveLoadingGameState();

      // Auto-advance after a short delay
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (!mounted) return;
        _advanceToNext();
      });
    } else {
      HapticFeedback.vibrate();
      setState(() => _showWrong = true);
      _shakeController.forward(from: 0).then((_) {
        if (mounted) setState(() => _showWrong = false);
      });
    }
  }

  bool _listsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Persists [xp] to the user's real XP so the profile, level, and daily
  /// streak update after each correct guess. Fire-and-forget: a slow or
  /// failed write must never block gameplay (failures are logged by
  /// [ScoreService.awardMiniGameXp]).
  void _awardPersistedXp(int xp) {
    if (xp <= 0) return;
    unawaited(_persistXp(xp));
  }

  Future<void> _persistXp(int xp) async {
    var language = widget.language;
    if (language == null || language.isEmpty) {
      language = await UserPreferencesService().getCurrentLanguage();
    }
    await ScoreService.awardMiniGameXp(language, xp);
  }

  void _advanceToNext() {
    setState(() {
      _currentMotivation =
          _motivationMessages[_random.nextInt(_motivationMessages.length)];
      if (widget.isStandalone) {
        // Move to the next unsolved card; when every card is solved the
        // session is complete and we celebrate below.
        final next = _nextUnsolvedIndex();
        if (next != null) _currentIndex = next;
      } else {
        _currentIndex++;
      }
      _loadCurrentWord();
      _saveLoadingGameState();
    });

    if (widget.isStandalone &&
        _filteredWords.isNotEmpty &&
        _solvedIndices.length >= _filteredWords.length) {
      _celebrateAndFinish();
    }
  }

  /// Next card index that hasn't been solved yet — searches forward from the
  /// current card, then wraps around. Returns null when none remain (i.e.
  /// every card has been solved), treating the current card as already
  /// visited so we never return the index we're standing on.
  int? _nextUnsolvedIndex() {
    for (int i = _currentIndex + 1; i < _filteredWords.length; i++) {
      if (!_solvedIndices.contains(i)) return i;
    }
    for (int i = 0; i < _currentIndex && i < _filteredWords.length; i++) {
      if (!_solvedIndices.contains(i)) return i;
    }
    return null;
  }

  void _skip() {
    HapticFeedback.lightImpact();
    setState(() {
      _usedHintOrSkip = true;
      _currentMotivation =
          _motivationMessages[_random.nextInt(_motivationMessages.length)];
      if (widget.isStandalone) {
        // Skipping doesn't solve a card — jump to the next unsolved one.
        // If only the current card remains unsolved, stay on it.
        final next = _nextUnsolvedIndex();
        if (next != null) _currentIndex = next;
      } else {
        _currentIndex++;
      }
      _loadCurrentWord();
      _saveLoadingGameState();
    });
  }

  // ─── Session completion ─────────────────────────────────────────────────

  /// Shows the completion celebration, then closes the page. Only used in
  /// standalone (Strange Words) mode — the video-generation mode loops until
  /// the video is ready.
  void _celebrateAndFinish() {
    if (_celebrating || _closed) return;
    HapticFeedback.vibrate();
    // Celebration fanfare (assets/sounds/ folder is bundled via pubspec).
    _audioPlayer.play(AssetSource('sounds/celebration.wav'));
    setState(() => _celebrating = true);
    Future.delayed(const Duration(milliseconds: 3000), () {
      unawaited(_closeSession());
    });
  }

  /// Closes the game page (or just hides the celebration when no back
  /// callback is available). Safe to call multiple times.
  Future<void> _closeSession() async {
    if (_closed || !mounted) return;
    if (widget.onBack == null) {
      setState(() => _celebrating = false);
      return;
    }
    _closed = true;
    await AppReviewPromptService.instance.maybeShow(context);
    if (!mounted) return;
    widget.onBack!();
  }

  void _shuffle() {
    HapticFeedback.lightImpact();
    setState(() {
      // Put all placed pieces back to available
      for (int i = 0; i < _slots.length; i++) {
        if (_slots[i] != null) {
          _availablePieces.add(_slots[i]!);
          _slots[i] = null;
          _slotValidation[i] = null;
        }
      }
      _availablePieces.shuffle(_random);
    });
  }

  // ─── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_filteredWords.isEmpty) {
      return _buildEmptyState(theme, isDark);
    }

    final totalWords = _filteredWords.length;
    // Standalone sessions show progress as cards-solved (they don't cycle);
    // video-generation mode cycles through the list with modulo.
    final displayIndex = widget.isStandalone
        ? (_solvedIndices.length + 1).clamp(1, totalWords)
        : (_currentIndex % totalWords) + 1;

    return PopScope(
      canPop: true,
      child: Column(
        children: [
          // ── Motivational message ──
          if (!widget.videoReady && !widget.isStandalone)
            _buildMotivationBanner(theme, isDark),

          // ── Video generation progress bar ──
          if (!widget.isStandalone)
            _buildVideoProgressBar(theme, isDark),

          // ── Video Ready banner ──
          if (widget.videoReady && !widget.isStandalone)
            _buildVideoReadyBanner(theme),

          // ── Game content ──
          Expanded(
            child: Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      const SizedBox(height: 8),

                      // ── Header: progress + XP ──
                      _buildHeader(theme, isDark, displayIndex, totalWords),

                      const SizedBox(height: 20),

                      // ── Mode label ──
                      _buildModeLabel(theme, isDark),

                      const SizedBox(height: 20),

                      // ── Answer area ──
                      AnimatedBuilder(
                        animation: _shakeAnimation,
                        builder: (context, child) {
                          return Transform.translate(
                            offset: Offset(_shakeAnimation.value, 0),
                            child: child,
                          );
                        },
                        child: _buildAnswerArea(theme, isDark),
                      ),

                      const SizedBox(height: 12),

                      // ── Correct / wrong feedback ──
                      if (_showCorrect) _buildCorrectFeedback(theme),

                      const SizedBox(height: 24),

                      // ── Available pieces ──
                      _buildAvailablePieces(theme, isDark),

                      const SizedBox(height: 44),

                      // ── Action buttons ──
                      _buildActionButtons(theme, isDark),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),

                // ── Floating XP popup ──
                if (_showXpPopup)
                  Positioned(
                    top: 8,
                    right: 20,
                    child: _buildXpPopup(theme),
                  ),

                // ── Session complete celebration ──
                if (_celebrating)
                  Positioned.fill(
                    child: _SessionCompleteOverlay(
                      totalCards: _filteredWords.length,
                      correctCards: _solvedIndices.length,
                      xp: _xp,
                      onDismiss: _closeSession,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Sub-widgets ───────────────────────────────────────────────────────

  Widget _buildEmptyState(ThemeData theme, bool isDark) {
    if (widget.isStandalone) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.extension_off_rounded,
                size: 64,
                color: theme.colorScheme.secondary.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 20),
              Text(
                'No Words Available',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: theme.textTheme.titleLarge?.color,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Add some words or select words to start playing Word Unscramble!',
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white54 : Colors.black45,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (widget.onBack != null)
                TextButton.icon(
                  onPressed: widget.onBack,
                  icon: Icon(
                    Icons.arrow_back_rounded,
                    size: 18,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                  label: Text(
                    'Go Back',
                    style: GoogleFonts.nunito(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.auto_fix_high_rounded,
              size: 64,
              color: theme.colorScheme.secondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 20),
            Text(
              'Generating Your Video Lesson',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: theme.textTheme.titleLarge?.color,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'This usually takes 1–2 minutes.\nFeel free to go back and come back later!',
              style: GoogleFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white54 : Colors.black45,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (widget.onBack != null)
              TextButton.icon(
                onPressed: widget.onBack,
                icon: Icon(
                  Icons.arrow_back_rounded,
                  size: 18,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
                label: Text(
                  'Back to Lessons',
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoProgressBar(ThemeData theme, bool isDark) {
    if (widget.videoReady) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _progressController,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _progressController.value.clamp(0.0, 1.0),
                  minHeight: 6,
                  backgroundColor: (isDark ? Colors.white : Colors.black)
                      .withValues(alpha: 0.08),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    theme.colorScheme.secondary,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _progressController.value >= 0.94
                    ? 'Almost ready, finalizing your video...'
                    : 'Generating video lesson...',
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVideoReadyBanner(ThemeData theme) {
    return GestureDetector(
      onTap: widget.onVideoReady,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.primary,
              theme.colorScheme.secondary,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Text('🎬', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Video Ready! Tap to watch',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const Icon(
              Icons.play_circle_filled_rounded,
              color: Colors.white,
              size: 28,
            ),
          ],
        ),
      ),
    )
        .animate(onPlay: (c) => c.repeat(reverse: true))
        .shimmer(duration: 2000.ms, color: Colors.white24);
  }

  Widget _buildHeader(
    ThemeData theme,
    bool isDark,
    int displayIndex,
    int totalWords,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Progress
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'Word $displayIndex of $totalWords',
            style: GoogleFonts.nunito(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
        ),
        // XP badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('⭐', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 4),
              Text(
                '$_xp XP',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.amber.shade700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModeLabel(ThemeData theme, bool isDark) {
    return Text(
      _isSentenceMode
          ? 'Arrange the words to form the correct sentence'
          : 'Arrange the letters to form the correct word',
      style: GoogleFonts.nunito(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.white54 : Colors.black45,
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildAnswerArea(ThemeData theme, bool isDark) {
    final borderColor = _showCorrect
        ? Colors.green
        : _showWrong
            ? theme.colorScheme.error
            : (isDark ? Colors.white : Colors.black).withValues(alpha: 0.12);
    final bgColor = _showCorrect
        ? Colors.green.withValues(alpha: 0.06)
        : _showWrong
            ? theme.colorScheme.error.withValues(alpha: 0.06)
            : (isDark ? Colors.white : Colors.black).withValues(alpha: 0.03);

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 80),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Wrap(
        spacing: _isSentenceMode ? 8 : 6,
        runSpacing: _isSentenceMode ? 8 : 6,
        alignment: WrapAlignment.center,
        children: List.generate(_slots.length, (index) {
          final piece = _slots[index];
          final validation = _slotValidation[index];

          return _buildSlot(
            index: index,
            piece: piece,
            validation: validation,
            theme: theme,
            isDark: isDark,
          );
        }),
      ),
    );
  }

  /// Builds a single answer slot — empty (dash) or filled with Wordle-style
  /// position validation coloring.
  Widget _buildSlot({
    required int index,
    required _Piece? piece,
    required bool? validation,
    required ThemeData theme,
    required bool isDark,
  }) {
    final isWord = _isSentenceMode;
    final isEmpty = piece == null;

    // ── Slot colors based on validation state ──
    Color slotBg;
    Color slotBorder;
    Color textColor;

    if (isEmpty) {
      // Empty slot — subtle dashed-style appearance
      slotBg = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.04);
      slotBorder = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.15);
      textColor = isDark ? Colors.white24 : Colors.black26;
    } else if (validation == true) {
      // Correct position (revealed on check) — green accent
      slotBg = Colors.green.withValues(alpha: 0.15);
      slotBorder = Colors.green.withValues(alpha: 0.5);
      textColor = Colors.green.shade700;
    } else if (validation == false) {
      // Wrong position (revealed on check) — subtle error tint
      slotBg = theme.colorScheme.error.withValues(alpha: 0.12);
      slotBorder = theme.colorScheme.error.withValues(alpha: 0.4);
      textColor = theme.colorScheme.error;
    } else {
      // Placed bubble before submission — clean active primary state
      slotBg = theme.colorScheme.primary.withValues(alpha: 0.1);
      slotBorder = theme.colorScheme.primary.withValues(alpha: 0.3);
      textColor = theme.colorScheme.primary;
    }

    return GestureDetector(
      onTap: isEmpty ? null : () => _onPlacedPieceTapped(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        padding: isWord
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
            : const EdgeInsets.all(0),
        constraints: isWord
            ? const BoxConstraints(minWidth: 44, minHeight: 44)
            : const BoxConstraints(minWidth: 44, minHeight: 44),
        decoration: BoxDecoration(
          color: slotBg,
          borderRadius: BorderRadius.circular(isWord ? 12 : 10),
          border: Border.all(
            color: slotBorder,
            width: validation == true ? 1.8 : 1.2,
          ),
          boxShadow: validation == true
              ? [
                  BoxShadow(
                    color: Colors.green.withValues(alpha: 0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: isWord
            ? Center(
                child: Text(
                  isEmpty ? '—' : piece.text,
                  style: GoogleFonts.nunito(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
              )
            : SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Text(
                    isEmpty ? '–' : piece.text,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: isEmpty ? 18 : 20,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildCorrectFeedback(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.check_circle_rounded, color: Colors.green.shade600, size: 22),
        const SizedBox(width: 6),
        Text(
          'Correct!',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Colors.green.shade600,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '+$_lastXpEarned XP ⭐',
          style: GoogleFonts.nunito(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.amber.shade700,
          ),
        ),
      ],
    )
        .animate()
        .fadeIn(duration: 300.ms)
        .scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1));
  }

  Widget _buildAvailablePieces(ThemeData theme, bool isDark) {
    if (_availablePieces.isEmpty && !_showCorrect) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: _isSentenceMode ? 10 : 8,
      runSpacing: _isSentenceMode ? 10 : 8,
      alignment: WrapAlignment.center,
      children: _availablePieces.map((piece) {
        return _buildBubble(
          piece: piece,
          onTap: () => _onPieceTapped(piece),
          isPlaced: false,
          theme: theme,
          isDark: isDark,
        );
      }).toList(),
    );
  }

  Widget _buildBubble({
    required _Piece piece,
    required VoidCallback onTap,
    required bool isPlaced,
    required ThemeData theme,
    required bool isDark,
  }) {
    final isWord = _isSentenceMode;

    final bgColor = isPlaced
        ? theme.colorScheme.primary.withValues(alpha: 0.12)
        : (isDark ? Colors.white : Colors.black).withValues(alpha: 0.07);
    final borderColor = isPlaced
        ? theme.colorScheme.primary.withValues(alpha: 0.3)
        : (isDark ? Colors.white : Colors.black).withValues(alpha: 0.12);
    final textColor = isPlaced
        ? theme.colorScheme.primary
        : (isDark ? Colors.white : Colors.black87);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(isWord ? 12 : 10),
        child: Container(
          padding: isWord
              ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
              : const EdgeInsets.all(0),
          constraints: isWord
              ? null
              : const BoxConstraints(minWidth: 44, minHeight: 44),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(isWord ? 12 : 10),
            border: Border.all(color: borderColor, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: (isDark ? Colors.black : Colors.black12).withValues(alpha: 0.08),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: isWord
              ? Text(
                  piece.text,
                  style: GoogleFonts.nunito(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                )
              : SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: Text(
                      piece.text,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(ThemeData theme, bool isDark) {
    // Wrap instead of Row: on narrow screens (e.g. 320px) the four
    // TextButtons overflowed the Row; Wrap lays them out on multiple
    // centered lines instead of overflowing.
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        // Skip button
        TextButton.icon(
          onPressed: _skip,
          icon: Icon(
            Icons.skip_next_rounded,
            size: 18,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
          label: Text(
            'Skip',
            style: GoogleFonts.nunito(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ),
        // Shuffle button
        TextButton.icon(
          onPressed: _shuffle,
          icon: Icon(
            Icons.shuffle_rounded,
            size: 18,
            color: theme.colorScheme.secondary.withValues(alpha: 0.7),
          ),
          label: Text(
            'Shuffle',
            style: GoogleFonts.nunito(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.secondary.withValues(alpha: 0.7),
            ),
          ),
        ),
        // Done — finish the session and celebrate (standalone mode only)
        if (widget.isStandalone)
          TextButton.icon(
            onPressed: _celebrating ? null : _celebrateAndFinish,
            icon: Icon(
              Icons.flag_rounded,
              size: 18,
              color: _celebrating
                  ? (isDark ? Colors.white24 : Colors.black26)
                  : Colors.amber.shade600,
            ),
            label: Text(
              'Done',
              style: GoogleFonts.nunito(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _celebrating
                    ? (isDark ? Colors.white24 : Colors.black26)
                    : Colors.amber.shade600,
              ),
            ),
          ),
      ],
    );
  }

  // ─── Motivational banner ────────────────────────────────────────────────

  Widget _buildMotivationBanner(ThemeData theme, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: theme.colorScheme.secondary.withValues(alpha: 0.08),
      child: Text(
        _currentMotivation,
        style: GoogleFonts.nunito(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.secondary,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  // ─── Floating XP popup ──────────────────────────────────────────────────

  Widget _buildXpPopup(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.shade300, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('⭐', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 4),
          Text(
            '+$_lastXpEarned XP',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Colors.amber.shade800,
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 200.ms)
        .slideY(begin: -0.3, end: 0, duration: 300.ms, curve: Curves.easeOut)
        .then(delay: 600.ms)
        .fadeOut(duration: 300.ms)
        .slideY(begin: 0, end: -0.5, duration: 300.ms)
        .callback(callback: (_) {
      if (mounted) setState(() => _showXpPopup = false);
    });
  }
}

/// Full-screen celebration shown when the user finishes all cards in a
/// standalone (Strange Words) session. Tapping anywhere or waiting a few
/// seconds closes the page.
class _SessionCompleteOverlay extends StatelessWidget {
  /// Total cards in the session.
  final int totalCards;

  /// Cards the user actually solved correctly (may be less than
  /// [totalCards] when the session was ended early via Done).
  final int correctCards;

  final int xp;
  final VoidCallback onDismiss;

  const _SessionCompleteOverlay({
    required this.totalCards,
    required this.correctCards,
    required this.xp,
    required this.onDismiss,
  });

  static const _confettiColors = [
    Color(0xFFFF6B6B),
    Color(0xFF4ECDC4),
    Color(0xFFFFD93D),
    Color(0xFF9B51E0),
    Color(0xFF27AE60),
    Color(0xFF3498DB),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onDismiss,
      behavior: HitTestBehavior.opaque,
      child: Container(
        color: Colors.black.withValues(alpha: 0.65),
        child: Stack(
          children: [
            // Falling confetti pieces
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final rand = Random(7); // deterministic layout
                  return Stack(
                    children: [
                      for (int i = 0; i < 30; i++)
                        _buildConfetti(
                          i,
                          rand,
                          constraints.maxWidth,
                          constraints.maxHeight,
                        ),
                    ],
                  );
                },
              ),
            ),
            // Center celebration card
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 32,
                ),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1B4B) : Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🎉', style: TextStyle(fontSize: 56))
                        .animate()
                        .scale(
                          begin: const Offset(0.4, 0.4),
                          end: const Offset(1, 1),
                          duration: 500.ms,
                          curve: Curves.elasticOut,
                        ),
                    const SizedBox(height: 12),
                    Text(
                      'All Done!',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF1A1C1E),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      correctCards >= totalCards
                          ? 'You guessed all $totalCards card${totalCards == 1 ? '' : 's'} right!'
                          : 'You guessed $correctCards of $totalCards cards right!',
                      style: GoogleFonts.nunito(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.amber.shade300,
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('⭐', style: TextStyle(fontSize: 18)),
                          const SizedBox(width: 6),
                          Text(
                            '+$xp XP',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.amber.shade700,
                            ),
                          ),
                        ],
                      ),
                    )
                        .animate()
                        .fadeIn(delay: 300.ms)
                        .slideY(begin: 0.3, end: 0),
                    const SizedBox(height: 20),
                    Text(
                      'Closing… tap to continue',
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  ],
                ),
              )
                  .animate()
                  .fadeIn(duration: 300.ms)
                  .scale(
                    begin: const Offset(0.8, 0.8),
                    end: const Offset(1, 1),
                    duration: 400.ms,
                    curve: Curves.easeOutBack,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfetti(int index, Random random, double width, double height) {
    final color = _confettiColors[index % _confettiColors.length];
    final left = random.nextDouble() * width;
    final size = 6.0 + random.nextDouble() * 8;
    final durationMs = 1800 + random.nextInt(1600);
    final delayMs = random.nextInt(800);

    return Positioned(
      left: left,
      top: 0,
      child: Container(
        width: size,
        height: size * 1.6,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      )
          .animate(onPlay: (controller) => controller.repeat())
          .moveY(
            begin: -30,
            end: height + 30,
            duration: durationMs.ms,
            delay: delayMs.ms,
            curve: Curves.linear,
          )
          .rotate(
            begin: 0,
            end: 4,
            duration: durationMs.ms,
            delay: delayMs.ms,
          )
          .fadeIn(delay: delayMs.ms, duration: 150.ms),
    );
  }
}

/// A single piece (letter or word) in the unscramble game.
class _Piece {
  final int id;
  final String text;

  const _Piece({required this.id, required this.text});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _Piece && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
