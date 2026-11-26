import 'dart:convert';
import 'package:Badya/services/adk_service.dart';
import 'package:Badya/services/user_preferences_service.dart';
import 'package:Badya/utils/logger.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:translator/translator.dart';
import 'package:uuid/uuid.dart';

class LanguageService {
  static final LanguageService _instance = LanguageService._internal();
  factory LanguageService() => _instance;
  LanguageService._internal();

  final FlutterTts _flutterTts = FlutterTts();
  final GoogleTranslator _translator = GoogleTranslator();
  final AdkService _adkService = AdkService();
  final UserPreferencesService _userPrefsService = UserPreferencesService();
  final _uuid = const Uuid();

  static const Map<String, String> _languageCodes = {
    'English': 'en',
    'en': 'en',
    'French': 'fr',
    'fr': 'fr',
    'German': 'de',
    'de': 'de',
    'Italian': 'it',
    'it': 'it',
    'Japanese': 'ja',
    'ja': 'ja',
    'Chinese': 'zh',
    'zh': 'zh',
    'Russian': 'ru',
    'ru': 'ru',
    'Arabic': 'ar',
    'ar': 'ar',
    'Portuguese': 'pt',
    'pt': 'pt',
    'Spanish': 'es',
    'es': 'es',
  };

  Future<SessionCreationResult?> createSession({
    required String appName,
    String? userId,
    String? sessionId,
    Map<String, dynamic>? state,
    String? language,
  }) async {
    final uid = userId ?? 'user_${_uuid.v4()}';
    
    // Use effective state
    final effectiveState = state ?? {
      if (language != null) 'language': language,
    };

    // AdkService now handles 409 Conflict internally and returns SessionCreationResult
    return await _adkService.createSession(
      appName: appName,
      userId: uid,
      sessionId: sessionId,
      state: effectiveState,
    );
  }

  String? _globalDefinitionSessionId;
  String? _globalDefinitionUserId;

  Stream<String> define(
    String text, {
    String? sessionId,
    String? userId,
    String? targetLanguage,
    String? sourceLanguage,
  }) async* {
    if (sessionId != null) {
      _globalDefinitionSessionId = sessionId;
    }
    if (userId != null) {
      _globalDefinitionUserId = userId;
    }

    if (sessionId == null || userId == null) {
      if (_globalDefinitionSessionId == null) {
        // Only use random if absolutely necessary (e.g. from a standalone dialog)
        _globalDefinitionUserId ??= 'user_${_uuid.v4()}';
        try {
          final result = await createSession(
            appName: 'definition_agent',
            userId: _globalDefinitionUserId,
          );
          _globalDefinitionSessionId = result?.sessionId;
        } catch (e) {
          Logger.error('Failed to create global definition session', e);
        }
      }
      sessionId = _globalDefinitionSessionId;
      userId = _globalDefinitionUserId;
    }

    if (sessionId != null && userId != null) {
      // Track previously seen text to only yield incremental (new) content.
      // The ADK SSE stream often emits the full accumulated text in each event
      // (both streaming partials and a final event), which would cause the
      // panel's buffer to write the same text twice.
      var previousText = '';
      yield* _adkService.runAgentSseStream(
        appName: 'definition_agent',
        userId: userId,
        sessionId: sessionId,
        message: text,
      ).map((event) {
        final parts = event['content']?['parts'] as List?;
        if (parts != null && parts.isNotEmpty) {
          final currentText = parts[0]['text'] as String? ?? '';
          // Only yield the new portion not seen in the previous event
          if (currentText.startsWith(previousText)) {
            final newText = currentText.substring(previousText.length);
            previousText = currentText;
            return newText;
          }
          // Fallback: text changed unexpectedly, yield full text
          previousText = currentText;
          return currentText;
        }
        return '';
      }).handleError((e) {
        Logger.error('Error in definition agent stream', e);
        return 'Error loading definition from AI agent. Please try again.';
      });
      return;
    }

    final target = targetLanguage ?? 'Arabic';
    final cleanText = text.trim();

    try {
      // 1. Language Discovery & Translation to English
      final translationResult = await _translator.translate(cleanText, to: 'en');
      final detectedSourceCode = translationResult.sourceLanguage.code;
      final englishTranslation = translationResult.text;

      // 2. Formulate the display translation
      String nativeTranslation = translationResult.text;
      if (target != 'English') {
        final targetBase = target.split('(').first.trim();
        final targetCode = _languageCodes[targetBase] ?? 'ar';
        final nativeResult = await _translator.translate(cleanText, 
            from: detectedSourceCode, to: targetCode);
        nativeTranslation = nativeResult.text;
      }

      // 3. Prepare English word for Dictionary lookup
      final words = englishTranslation.trim().toLowerCase().split(' ');
      final articles = {'a', 'an', 'the'};
      String wordToLookup = words.firstWhere(
        (w) => !articles.contains(w.replaceAll(RegExp(r'[^\w]'), '')),
        orElse: () => words.first,
      ).replaceAll(RegExp(r'[^\w]'), '');

      // 4. Get Definition (Using Free Dictionary API)
      final url = Uri.parse(
          'https://api.dictionaryapi.dev/api/v2/entries/en/$wordToLookup');
      final response = await http.get(url);

      String definitionText = "No definition found.";

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (data.isNotEmpty) {
          final firstEntry = data[0];
          final meanings = firstEntry['meanings'] as List;
          if (meanings.isNotEmpty) {
            final firstMeaning = meanings[0];
            final definitions = firstMeaning['definitions'] as List;
            if (definitions.isNotEmpty) {
              definitionText =
                  definitions[0]['definition'] ?? "No definition available.";
            }
          }
        }
      }

      // 5. Translate Definition to Native Language
      final targetBase = target.split('(').first.trim();
      final targetCode = _languageCodes[targetBase] ?? 'ar';
      final defResult = await _translator.translate(definitionText, 
          from: 'en', to: targetCode);
      final translatedDefinition = defResult.text;

      // 6. Yield the final formatted result
      yield "**Translation:** $nativeTranslation\n\n"
          "**Definition:** $translatedDefinition";
    } catch (e) {
      Logger.error('Error in discovery definition', e);
      yield 'Error loading definition. Please check your internet connection.';
    }
  }

  Future<String> translate(
    String text, {
    String? sourceLang,
    String? targetLang,
  }) async {
    final target = targetLang ?? await _userPrefsService.getNativeLanguage();
    final targetBase = target.split('(').first.trim();
    final targetCode = _languageCodes[targetBase] ?? 'ar';

    try {
      final translation = await _translator.translate(text, to: targetCode);
      return translation.text;
    } catch (e) {
      Logger.error('Translation error', e);
      return 'Translation error: $e';
    }
  }

  Future<void> speak(String text, {String? learningLang}) async {
    final lang = learningLang ?? await _userPrefsService.getCurrentLanguage();
    final langBase = lang.split('(').first.trim();
    final code = _languageCodes[langBase] ?? 'en';

    try {
      await _flutterTts.setLanguage(code);
      await _flutterTts.setPitch(1.0);
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.speak(text);
    } catch (e) {
      Logger.error('TTS error', e);
    }
  }
}
