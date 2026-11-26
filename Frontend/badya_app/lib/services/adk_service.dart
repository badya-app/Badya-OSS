import 'dart:async';
import 'dart:convert';
import 'package:Badya/config/api_config.dart';
import 'package:Badya/utils/logger.dart';
import 'package:Badya/services/firebase_storage_service.dart';
import 'package:Badya/services/vocab_review_service.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';

/// Thrown when the backend returns HTTP 429 (rate limit exceeded).
class RateLimitException implements Exception {
  final String message;
  const RateLimitException(this.message);

  @override
  String toString() => message;
}

class SessionCreationResult {
  final String sessionId;
  final bool isResumed;

  SessionCreationResult({required this.sessionId, required this.isResumed});
}

class AdkTurn {
  final String author;
  final dynamic content;
  final Map<String, dynamic> metadata;

  AdkTurn({
    required this.author,
    required this.content,
    required this.metadata,
  });

  factory AdkTurn.fromJson(Map<String, dynamic> json) {
    return AdkTurn(
      author: json['author'] ?? 'unknown',
      content: json['content'],
      metadata: json['metadata'] ?? {},
    );
  }

  /// Convenience: returns the first text part from the content, or null.
  String? get contentText {
    if (content == null) return null;
    final parts = content['parts'];
    if (parts is List && parts.isNotEmpty) {
      return parts[0]['text'] as String?;
    }
    return null;
  }
}

class AdkSessionData {
  final String sessionId;
  final Map<String, dynamic> state;
  final List<AdkTurn> history;

  AdkSessionData({
    required this.sessionId,
    required this.state,
    required this.history,
  });

  factory AdkSessionData.fromJson(Map<String, dynamic> json) {
    final history = (json['events'] as List? ?? [])
        .map((e) => AdkTurn.fromJson(e))
        .toList();
    return AdkSessionData(
      sessionId: json['session_id'] ?? '',
      state: json['state'] ?? {},
      history: history,
    );
  }
}

class AdkService {
  static final AdkService _instance = AdkService._internal();
  factory AdkService() => _instance;
  AdkService._internal();

  final _uuid = const Uuid();

  String get baseUrl => ApiConfig.getBaseUrl();

  String getArtifactUrl({
    required String appName,
    required String userId,
    required String sessionId,
    required String artifactName,
    int version = 0,
  }) {
    return '$baseUrl/apps/$appName/users/$userId/sessions/$sessionId/artifacts/$artifactName?version=$version';
  }

  /// Normalizes a string to be a valid ADK session ID (max 63 chars, lowercase, hyphens).
  String normalizeId(String id) {
    // Check if the ID is already fully normalized (starts with [a-z], lowercase alphanumeric, single hyphens, ends with 8-char hex hash, <= 63 chars)
    final alreadyNormalizedRegExp = RegExp(
      r'^[a-z][a-z0-9]*(-[a-z0-9]+)*-[0-9a-f]{8}$',
    );
    if (id.length <= 63 && alreadyNormalizedRegExp.hasMatch(id)) {
      return id;
    }

    // Generate a short deterministic hash of the original ID using MD5 to guarantee uniqueness
    final bytes = utf8.encode(id);
    final hash = md5.convert(bytes).toString().substring(0, 8);

    // Lowercase and replace any sequence of non-alphanumeric characters with a single hyphen
    String normalized = id.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');

    // Strip leading hyphens
    while (normalized.startsWith('-') && normalized.length > 1) {
      normalized = normalized.substring(1);
    }

    // Strip trailing hyphens
    while (normalized.endsWith('-') && normalized.length > 1) {
      normalized = normalized.substring(0, normalized.length - 1);
    }

    // Fallback if empty or just a hyphen
    if (normalized.isEmpty || normalized == '-') {
      normalized = 'session-$hash';
    } else {
      normalized = '$normalized-$hash';
    }

    // Ensure it starts with a letter (if not, prepend 's-')
    if (!RegExp(r'^[a-z]').hasMatch(normalized)) {
      normalized = 's-$normalized';
    }

    // Enforce max length of 63 characters
    if (normalized.length > 63) {
      // Keep the 8-character hash at the end. We need space for "-$hash" which is 9 characters.
      final prefixLimit = 63 - 9;
      if (normalized.length > prefixLimit) {
        normalized = '${normalized.substring(0, prefixLimit)}-$hash';
      }
      // Compress any consecutive hyphens and clean up trailing hyphens
      normalized = normalized.replaceAll(RegExp(r'-+'), '-');
      while (normalized.endsWith('-') && normalized.length > 1) {
        normalized = normalized.substring(0, normalized.length - 1);
      }
    }

    return normalized;
  }

  // --- Core Session Management ---

  Future<SessionCreationResult?> createSession({
    required String appName,
    required String userId,
    String? sessionId,
    Map<String, dynamic>? state,
  }) async {
    final effectiveSessionId = normalizeId(
      sessionId ?? 'session-${_uuid.v4()}',
    );
    final url = Uri.parse('$baseUrl/apps/$appName/users/$userId/sessions');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'session_id': effectiveSessionId,
          'state': state ?? {},
          'events': [],
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return SessionCreationResult(
          sessionId: effectiveSessionId,
          isResumed: false,
        );
      }

      // Handle "Session already exists" case gracefully
      if (response.statusCode == 409 ||
          response.body.contains('already exists')) {
        Logger.info(
          'AdkService: Session $effectiveSessionId already exists, reusing.',
        );
        return SessionCreationResult(
          sessionId: effectiveSessionId,
          isResumed: true,
        );
      }

      Logger.error(
        'Failed to create session: ${response.statusCode} - ${response.body}',
      );
      return null;
    } catch (e) {
      Logger.error('Error creating session', e);
      rethrow;
    }
  }

  Future<AdkSessionData?> fetchSession({
    required String appName,
    required String userId,
    required String sessionId,
  }) async {
    final url = Uri.parse(
      '$baseUrl/apps/$appName/users/$userId/sessions/$sessionId',
    );
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        return AdkSessionData.fromJson(jsonDecode(response.body));
      }
      Logger.error('Failed to fetch session: ${response.statusCode}');
      return null;
    } catch (e) {
      Logger.error('Error fetching session', e);
      return null;
    }
  }

  Future<bool> deleteSession({
    required String appName,
    required String userId,
    required String sessionId,
  }) async {
    final url = Uri.parse(
      '$baseUrl/apps/$appName/users/$userId/sessions/$sessionId',
    );
    try {
      final response = await http.delete(url);
      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      Logger.error('Error deleting session', e);
      return false;
    }
  }

  /// Returns true when the given session still exists on the ADK backend.
  Future<bool> sessionExists({
    required String appName,
    required String userId,
    required String sessionId,
  }) async {
    final data = await fetchSession(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
    );
    return data != null;
  }

  // --- Core Agent Execution ---

  /// Standard non-streaming run
  Future<Map<String, dynamic>?> runAgent({
    required String appName,
    required String userId,
    required String sessionId,
    required String message,
    Map<String, dynamic>? stateDelta,
  }) async {
    final url = Uri.parse('$baseUrl/run');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'app_name': appName,
          'user_id': userId,
          'session_id': sessionId,
          'new_message': {
            'parts': [
              {'text': message},
            ],
          },
          'streaming': false,
          'state_delta': stateDelta ?? {},
        }),
      );

      if (response.statusCode == 200) {
        final List<dynamic> events = jsonDecode(response.body);
        if (events.isNotEmpty) {
          return events.last as Map<String, dynamic>;
        }
      }
      return null;
    } catch (e) {
      Logger.error('Error running agent', e);
      rethrow;
    }
  }

  /// Runs the scenario_writer_agent to generate a role-play scenario.
  /// Returns the scenario text, or null on failure.
  Future<String?> runScenarioWriter({
    required String userId,
    required String topicSubject,
    required List<String> wordsList,
    required String language,
    required String languageLevel,
    required String difficulty,
    String? description,
  }) async {
    const appName = 'scenario_writer_agent';
    final result = await createSession(
      appName: appName,
      userId: userId,
      state: {
        'story_subject': topicSubject,
        'words_list': wordsList.join(', '),
        'language': language,
        'language_level': languageLevel,
        'difficulty': difficulty,
        if (description != null) 'description': description,
      },
    );

    if (result == null) return null;
    final sessionId = result.sessionId;

    try {
      final lastEvent = await runAgent(
        appName: appName,
        userId: userId,
        sessionId: sessionId,
        message: 'Generate the scenario now.',
      );

      if (lastEvent != null) {
        // 1. Check actions.stateDelta for the output_key value
        final scenario = lastEvent['actions']?['stateDelta']?['scenario'];
        if (scenario is String && scenario.isNotEmpty) {
          return scenario;
        }

        // 2. Fallback: extract from content.parts[0].text
        final content = lastEvent['content'];
        if (content != null &&
            content['parts'] != null &&
            (content['parts'] as List).isNotEmpty) {
          final text = content['parts'][0]['text'] as String?;
          if (text != null && text.isNotEmpty) {
            return text;
          }
        }
      }
      return null;
    } finally {
      // Cleanup the temporary scenario session
      await deleteSession(
        appName: appName,
        userId: userId,
        sessionId: sessionId,
      );
    }
  }

  /// Streaming run with SSE - returns a stream of events
  Stream<Map<String, dynamic>> runAgentSseStream({
    required String appName,
    required String userId,
    required String sessionId,
    required String message,
    Map<String, dynamic>? stateDelta,
  }) async* {
    final url = Uri.parse('$baseUrl/run_sse');
    final client = http.Client();
    try {
      final request = http.Request('POST', url);
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({
        'app_name': appName,
        'user_id': userId,
        'session_id': sessionId,
        'new_message': {
          'parts': [
            {'text': message},
          ],
        },
        'streaming': true,
        'state_delta': stateDelta ?? {},
      });

      final response = await client.send(request);

      if (response.statusCode == 200) {
        final stream = response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter());

        await for (var line in stream) {
          if (line.startsWith('data: ')) {
            final jsonStr = line.substring(6);
            if (jsonStr.trim().isNotEmpty && jsonStr != '[DONE]') {
              try {
                final event = jsonDecode(jsonStr) as Map<String, dynamic>;
                yield event;
              } catch (e) {
                Logger.error('Error parsing SSE event', e);
              }
            }
          }
        }
      } else {
        yield {
          'partial': true,
          'content': {
            'parts': [
              {'text': 'Error: Server returned status ${response.statusCode}'},
            ],
          },
        };
      }
    } catch (e) {
      Logger.error('Error running agent SSE', e);
      yield {
        'partial': true,
        'content': {
          'parts': [
            {
              'text':
                  'Connection Error: Please check if the server is running and accessible at $baseUrl',
            },
          ],
        },
      };
      rethrow;
    } finally {
      client.close();
    }
  }

  // --- Higher-Level Specialized Process (DRY) ---

  /// Orchestrates the full flow of generating words for a topic and caching them.
  Future<void> generateAndCacheWords({
    required String topicId,
    required String subject,
    required String description,
    required String language,
    String difficulty = 'intermediate',
    String? userId,
  }) async {
    userId ??= FirebaseAuth.instance.currentUser?.uid ?? 'user_123';

    // Early exit if words already exist in Firestore
    final vocabService = VocabReviewService();
    final scopeId = VocabReviewService.topicScopeId(topicId, language);
    final existing = await vocabService.getAllWords(
      scope: VocabReviewService.scopeTopic,
      scopeId: scopeId,
      userId: userId,
    );
    if (existing.isNotEmpty) return;

    const appName = 'word_generator_agent';
    final result = await createSession(
      appName: appName,
      userId: userId,
      state: {
        'story_subject': subject,
        'description': description,
        'language': language,
        'difficulty': difficulty,
      },
    );

    if (result == null) return;
    final sessionId = result.sessionId;

    try {
      final lastEvent = await runAgent(
        appName: appName,
        userId: userId,
        sessionId: sessionId,
        message: 'Generate words now.',
      );

      if (lastEvent != null) {
        List<String>? newWords;

        // 1. Check stateDelta for structured content
        if (lastEvent['actions']?['stateDelta']?['generated_content'] != null) {
          final content =
              lastEvent['actions']['stateDelta']['generated_content'];
          if (content is List) {
            newWords = content.map((e) => e.toString()).toList();
          } else if (content is Map && content['content'] is List) {
            newWords = (content['content'] as List)
                .map((e) => e.toString())
                .toList();
          }
        }

        // 2. Fallback: Check 'say' action
        if (newWords == null && lastEvent['actions']?['say']?['text'] != null) {
          try {
            final decoded = jsonDecode(lastEvent['actions']['say']['text']);
            if (decoded is List) {
              newWords = decoded.map((e) => e.toString()).toList();
            }
          } catch (e) {
            Logger.warn('Failed to decode "say" action text: $e');
          }
        }

        if (newWords != null && newWords.isNotEmpty) {
          await vocabService.addWordsToTopic(
            topicId: topicId,
            language: language,
            words: newWords,
            userId: userId,
          );
        }
      }
    } finally {
      // Always cleanup session
      await deleteSession(
        appName: appName,
        userId: userId,
        sessionId: sessionId,
      );
    }
  }

  /// Sends a conversation transcript to the analysis agent.
  Future<Map<String, dynamic>?> runAnalyzeAgent({
    required String topicId,
    required List<Map<String, String>> transcript,
    required String language,
    String? userId,
    List<String>? wordsList,
    Map<String, dynamic>? previousAnalysis,
    String? lessonType, // "full" or "word_smith"
  }) async {
    userId ??= FirebaseAuth.instance.currentUser?.uid ?? 'user_123';
    const appName = 'analyze_agent';
    final result = await createSession(
      appName: appName,
      userId: userId,
      state: {
        'topicId': topicId,
        'transcript': transcript,
        'language': language,
        if (wordsList != null) 'words_list': wordsList,
        if (previousAnalysis != null) 'previous_analysis': previousAnalysis,
        'lesson_type': lessonType ?? 'full',
      },
    );

    if (result == null) return null;
    final sessionId = result.sessionId;

    try {
      final lastEvent = await runAgent(
        appName: appName,
        userId: userId,
        sessionId: sessionId,
        message: 'Analyze this conversation.',
      );

      // Extract the structured analysis result
      // Assuming agent returns it in 'content' -> 'parts' -> [0] -> 'text' (as JSON string)
      // OR if using structured output schema, it might be in 'structured_output' or similar depending on ADK.
      // But typically for Gemini agents with output schema, it might come back as parsed JSON in a specific field
      // or as a text that is valid JSON.
      // Let's assume it's in the text response for now as that's standard for `runAgent` parsing above unless `output_key` is handled.
      // Wait, `agent.py` uses `output_key="analysis_result"`.
      // The ADK server response for `/run` usually returns the state delta or the standard response format.
      // If `output_key` is set, the result should be in the state or returned explicitly.
      // A common pattern is that the tool/LLM response is in the message content.

      if (lastEvent != null) {
        // Check for functionResponse-like structure if it was a tool, but here it's an Agent level output schema.
        // Usually `run` returns the last event.
        // If `output_schema` is used, the model output is enforced JSON.
        // We should check `content` text.

        final content = lastEvent['content'];
        if (content != null &&
            content['parts'] != null &&
            (content['parts'] as List).isNotEmpty) {
          final text = content['parts'][0]['text'];
          if (text != null) {
            try {
              // Clean up markdown code blocks if present
              String cleanJson = text.trim();
              if (cleanJson.startsWith('```json')) {
                cleanJson = cleanJson.substring(7);
                if (cleanJson.endsWith('```')) {
                  cleanJson = cleanJson.substring(0, cleanJson.length - 3);
                }
              } else if (cleanJson.startsWith('```')) {
                // sometimes just ```
                cleanJson = cleanJson.substring(3);
                if (cleanJson.endsWith('```')) {
                  cleanJson = cleanJson.substring(0, cleanJson.length - 3);
                }
              }
              return jsonDecode(cleanJson) as Map<String, dynamic>;
            } catch (e) {
              Logger.error('Failed to parse analysis JSON', e);
            }
          }
        }

        if (lastEvent['analysis_result'] != null) {
          return lastEvent['analysis_result'] as Map<String, dynamic>;
        }
      }
      return null;
    } finally {
      await deleteSession(
        appName: appName,
        userId: userId,
        sessionId: sessionId,
      );
    }
  }

  /// Generates an image using AI.
  ///
  /// Throws [RateLimitException] if the backend returns 429 (too many requests).
  Future<String?> generateImage({
    required String prompt,
    int width = 1024,
    int height = 1024,
    String? userId,
  }) async {
    final url = Uri.parse('$baseUrl/generate-image');
    Logger.info('AdkService: Generating image at $url');
    Logger.info('AdkService: Prompt: $prompt');

    // Resolve user ID — fall back to current Firebase user
    final effectiveUserId = userId ?? FirebaseAuth.instance.currentUser?.uid;

    // Get Firebase auth token for the Authorization header
    String? idToken;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        idToken = await user.getIdToken();
      }
    } catch (e) {
      Logger.warn('AdkService: Failed to get ID token: $e');
    }

    try {
      final request = http.MultipartRequest('POST', url);

      // Add auth header if available
      if (idToken != null) {
        request.headers['Authorization'] = 'Bearer $idToken';
      }

      // Add form fields
      request.fields['prompt'] = prompt;
      request.fields['width'] = width.toString();
      request.fields['height'] = height.toString();
      request.fields['user_id'] = effectiveUserId ?? '';

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 45),
      );
      final response = await http.Response.fromStream(streamedResponse);

      Logger.info('AdkService: Response status: ${response.statusCode}');

      if (response.statusCode == 429) {
        // Parse structured error from backend
        String message = 'Too many requests. Please try again later.';
        try {
          final body = jsonDecode(response.body);
          final detail = body['detail'];
          if (detail is Map) {
            message = detail['message'] ?? message;
          } else if (detail is String) {
            message = detail;
          }
        } catch (e) {
          Logger.warn('Failed to parse rate-limit error detail: $e');
        }
        throw RateLimitException(message);
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final base64String = data['image_data'] as String;
        final filename = data['filename'] as String;

        // Decode base64 to bytes
        final Uint8List imageBytes = base64Decode(base64String);

        // Save the image directly to Firebase Storage
        try {
          Logger.info('AdkService: Uploading image to Firebase Storage...');
          final storageService = FirebaseStorageService();
          final firebaseImageUrl = await storageService.uploadBytes(
            imageBytes,
            filename,
            'ai_thumbnails',
          );

          if (firebaseImageUrl != null) {
            Logger.info(
              'AdkService: Successfully uploaded to Firebase: $firebaseImageUrl',
            );
            return firebaseImageUrl;
          }
        } catch (e) {
          Logger.error('AdkService: Firebase upload failed', e);
        }
        return null;
      } else {
        Logger.error('Image generation failed: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      if (e is RateLimitException) rethrow;
      Logger.error('AdkService: Exception in generateImage', e);
      return null;
    }
  }

  Future<String?> generateThumbnailPrompt({
    required String title,
    required String description,
  }) async {
    final userId = FirebaseAuth.instance.currentUser?.uid ?? 'default_user';
    String? createdSessionId;

    try {
      Logger.info('AdkService: Creating session for thumbnail_agent...');
      final result = await createSession(
        appName: 'thumbnail_agent',
        userId: userId,
        state: {'title': title, 'description': description},
      );

      if (result == null) {
        Logger.error(
          'AdkService: Failed to create session for thumbnail_agent',
        );
        return null;
      }
      final createdSessionId = result.sessionId;

      Logger.info('AdkService: Running thumbnail_agent...');
      final lastEvent = await runAgent(
        appName: 'thumbnail_agent',
        userId: userId,
        sessionId: createdSessionId,
        message: 'Title: $title, Description: $description',
      );

      if (lastEvent != null) {
        // Try content.parts first (standard ADK event format)
        final content = lastEvent['content'] as Map<String, dynamic>?;
        if (content != null) {
          final parts = content['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            final prompt = parts[0]['text'] as String?;
            if (prompt != null && prompt.isNotEmpty) {
              Logger.info('AdkService: Generated prompt: $prompt');
              return prompt;
            }
          }
        }
        // Fallback: check actions.say.text for alternative response format
        final actions = lastEvent['actions'] as Map<String, dynamic>?;
        if (actions != null) {
          final say = actions['say'] as Map<String, dynamic>?;
          if (say != null) {
            final text = say['text'] as String?;
            if (text != null && text.isNotEmpty) {
              Logger.info(
                'AdkService: Generated prompt from actions.say: $text',
              );
              return text;
            }
          }
        }
      }
      Logger.warn('AdkService: thumbnail_agent returned no text');
    } catch (e) {
      Logger.error('AdkService: Error in generateThumbnailPrompt', e);
    } finally {
      if (createdSessionId != null) {
        Logger.info('AdkService: Deleting session $createdSessionId');
        await deleteSession(
          appName: 'thumbnail_agent',
          userId: userId,
          sessionId: createdSessionId,
        );
      }
    }
    return null;
  }
}
