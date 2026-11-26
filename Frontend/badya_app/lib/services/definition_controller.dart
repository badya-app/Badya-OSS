import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:Badya/services/adk_service.dart';
import 'package:Badya/services/lesson_session_service.dart';
import 'package:Badya/services/user_preferences_service.dart';
import 'package:Badya/utils/language_service.dart';
import 'package:Badya/utils/logger.dart';
import 'package:Badya/widgets/custom_selection_toolbar.dart';
import 'package:Badya/widgets/definition_history_panel.dart';

/// Manages the definition agent session, word lookups, streaming definitions,
/// and word definition history across content pages (stories, videos, imported content).
class DefinitionController extends ChangeNotifier {
  static const String definitionAppName = 'definition_agent';

  String? _sessionId;
  String? get sessionId => _sessionId;

  final List<Map<String, String>> _history = [];
  List<Map<String, String>> get history => List.unmodifiable(_history);

  Stream<String>? _stream;
  Stream<String>? get stream => _stream;

  String? _currentWord;
  String? get currentWord => _currentWord;

  bool _showPanel = false;
  bool get showPanel => _showPanel;

  String? _cacheKey;
  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) {
      super.notifyListeners();
    }
  }

  /// Initialize the definition session and load any cached history.
  Future<void> initialize({
    required String userId,
    required String language,
    String? topicId,
    String? lessonType,
    String? existingSessionId,
    String? cacheKey,
  }) async {
    _cacheKey = cacheKey;

    if (cacheKey != null) {
      await _loadCachedHistory(cacheKey);
    }

    String? targetSessionId = existingSessionId;
    if ((targetSessionId == null || targetSessionId.isEmpty) &&
        topicId != null &&
        lessonType != null) {
      final sessionSnapshot = LessonSessionService().getSession(
        topicId: topicId,
        lessonType: lessonType,
      );
      targetSessionId = sessionSnapshot.definitionSessionId;
    }

    if (targetSessionId != null && targetSessionId.isNotEmpty) {
      _sessionId = targetSessionId;
      await _createSession(
        userId: userId,
        sessionId: targetSessionId,
        language: language,
      );
    }
  }

  Future<void> _createSession({
    required String userId,
    required String sessionId,
    required String language,
  }) async {
    try {
      final userPrefs = UserPreferencesService();
      final dialects = await userPrefs.getLearningDialects();
      final dialect = dialects[language] ?? '';
      final learningLanguage =
          dialect.isEmpty ? language : '$language ($dialect)';

      final result = await LanguageService().createSession(
        appName: definitionAppName,
        userId: userId,
        sessionId: sessionId,
        state: {'language': learningLanguage},
      );

      if (result != null) {
        _sessionId = result.sessionId;
        notifyListeners();

        // Restore history from ADK session if resumed and local history is empty
        if (result.isResumed && _history.isEmpty) {
          final sessionData = await AdkService().fetchSession(
            appName: definitionAppName,
            userId: userId,
            sessionId: result.sessionId,
          );
          if (sessionData != null) {
            for (var i = 0; i < sessionData.history.length; i++) {
              final turn = sessionData.history[i];
              if (turn.author == 'user') {
                String? word = turn.contentText;
                if (word == null || word.isEmpty) {
                  final parts = turn.content?['parts'] as List?;
                  if (parts != null && parts.isNotEmpty) {
                    word = parts[0]['text'] as String?;
                  }
                }
                if (word != null &&
                    word.isNotEmpty &&
                    i + 1 < sessionData.history.length) {
                  final nextTurn = sessionData.history[i + 1];
                  if (nextTurn.author == 'definition_agent' ||
                      nextTurn.author == 'agent') {
                    String? def = nextTurn.contentText;
                    if (def == null || def.isEmpty) {
                      final resParts = nextTurn.content?['parts'] as List?;
                      if (resParts != null && resParts.isNotEmpty) {
                        def = resParts[0]['text'] as String?;
                      }
                    }
                    if (def != null && def.isNotEmpty) {
                      _history.add({'word': word, 'definition': def});
                    }
                  }
                }
              }
            }
            if (_history.isNotEmpty) {
              notifyListeners();
              if (_cacheKey != null) {
                saveHistory();
              }
            }
          }
        }
      }
    } catch (e) {
      Logger.error('Failed to create definition session', e);
    }
  }

  /// Request definition for a word / phrase.
  void define({
    required String text,
    required String userId,
    required String sourceLanguage,
    String? targetLanguage,
    VoidCallback? onOpenDrawer,
  }) {
    final stream = LanguageService().define(
      text,
      sessionId: _sessionId,
      userId: userId,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    );

    _currentWord = text;
    _stream = stream;
    _showPanel = true;
    notifyListeners();

    if (onOpenDrawer != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onOpenDrawer();
      });
    }
  }

  /// Handles CustomSelectionToolbar action for selection text
  void handleToolbarAction(
    BuildContext context,
    String action,
    String text, {
    required String userId,
    required String language,
    String? nativeLanguage,
    VoidCallback? onOpenDrawer,
  }) {
    CustomSelectionToolbar.handleAction(
      context,
      action,
      text,
      learningLanguage: language,
      nativeLanguage: nativeLanguage,
      onDefinition: () {
        define(
          text: text,
          userId: userId,
          sourceLanguage: language,
          targetLanguage: nativeLanguage,
          onOpenDrawer: onOpenDrawer,
        );
      },
    );
  }

  /// Open drawer explicitly
  void openPanel(VoidCallback onOpenDrawer) {
    _showPanel = true;
    notifyListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onOpenDrawer();
    });
  }

  /// Called when the drawer closes to prevent stream re-renders
  void onDrawerClosed() {
    _stream = null;
    notifyListeners();
  }

  void deleteHistoryItem(int index) {
    if (index >= 0 && index < _history.length) {
      _history.removeAt(index);
      notifyListeners();
      saveHistory();
    }
  }

  /// Loads cached definition history from SharedPreferences
  Future<void> _loadCachedHistory(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(key);
      if (data != null) {
        final decoded = jsonDecode(data);
        if (decoded is List) {
          _history.clear();
          _history.addAll(
            decoded.map((e) => Map<String, String>.from(e as Map)),
          );
          notifyListeners();
        }
      }
    } catch (e) {
      Logger.warn('Failed to load cached definition history for key $key: $e');
    }
  }

  /// Saves definition history to SharedPreferences
  Future<void> saveHistory([String? key]) async {
    final targetKey = key ?? _cacheKey;
    if (targetKey == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(targetKey, jsonEncode(_history));
    } catch (e) {
      Logger.warn('Failed to save definition history for key $targetKey: $e');
    }
  }

  /// Build a standard DefinitionHistoryPanel
  Widget? buildEndDrawer({VoidCallback? onClose}) {
    if (!_showPanel) return null;
    return DefinitionHistoryPanel(
      definitionStream: _stream,
      history: _history,
      initialWord: _currentWord,
      onClose: onClose,
      onDelete: deleteHistoryItem,
    );
  }
}
