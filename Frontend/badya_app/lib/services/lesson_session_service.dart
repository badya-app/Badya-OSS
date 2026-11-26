import 'package:Badya/services/adk_service.dart';
import 'package:Badya/utils/logger.dart';

/// Manages session identification using deterministic IDs.
/// Sessions are no longer saved in Firestore as they are persisted by ADK backend.
class LessonSessionService {
  final AdkService _adk = AdkService();

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Generates the deterministic session IDs for a specific lesson context.
  /// No longer async as it doesn't need to read from a database.
  LessonSessionSnapshot getSession({
    required String topicId,
    required String lessonType,
  }) {
    // Unique but reproducible IDs per topic and lesson type
    final base = '${topicId}_$lessonType';
    
    return LessonSessionSnapshot(
      sessionId: _adk.normalizeId('main_$base'),
      storySessionId: _adk.normalizeId('story_$base'),
      correctorSessionId: _adk.normalizeId('corr_$base'),
      definitionSessionId: _adk.normalizeId('def_$base'),
      createdAt: DateTime.now(),
    );
  }

  /// Verification helper to check if a session still exists on the backend.
  Future<bool> verifySession({
    required String appName,
    required String userId,
    required String sessionId,
  }) async {
    return _adk.sessionExists(
      appName: appName,
      userId: userId,
      sessionId: sessionId,
    );
  }

  /// Cleanup: Deletes sessions from the ADK backend.
  Future<void> clearSession({
    required String appName,
    required String userId,
    required String sessionId,
  }) async {
    try {
      await _adk.deleteSession(
        appName: appName,
        userId: userId,
        sessionId: sessionId,
      );
      Logger.info('LessonSessionService: cleared session $sessionId for $appName');
    } catch (e) {
      Logger.error('LessonSessionService: error clearing session', e);
    }
  }
}

// ---------------------------------------------------------------------------
// Data transfer object
// ---------------------------------------------------------------------------

/// All the IDs and contextual data needed to re-attach to an in-progress
/// lesson without creating a brand-new session.
class LessonSessionSnapshot {
  /// The primary ADK session ID (e.g. for the chat / voice agent).
  final String sessionId;

  /// Optional secondary session IDs (e.g. story, corrector, definition).
  final String? storySessionId;
  final String? correctorSessionId;
  final String? definitionSessionId;

  /// The timestamp when this session was first created.
  final DateTime createdAt;

  const LessonSessionSnapshot({
    required this.sessionId,
    this.storySessionId,
    this.correctorSessionId,
    this.definitionSessionId,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        if (storySessionId != null) 'story_session_id': storySessionId,
        if (correctorSessionId != null) 'corrector_session_id': correctorSessionId,
        if (definitionSessionId != null) 'definition_session_id': definitionSessionId,
        'created_at': createdAt.toIso8601String(),
      };

  factory LessonSessionSnapshot.fromJson(Map<String, dynamic> json) =>
      LessonSessionSnapshot(
        sessionId: json['session_id'] as String,
        storySessionId: json['story_session_id'] as String?,
        correctorSessionId: json['corrector_session_id'] as String?,
        definitionSessionId: json['definition_session_id'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

// ---------------------------------------------------------------------------
// Lesson type constants  (single source of truth)
// ---------------------------------------------------------------------------

/// Canonical lesson-type keys used as the `lessonType` parameter.
class LessonTypes {
  LessonTypes._();
  static const String storyWeaver = 'story_weaver';
  static const String echoChamber = 'echo_chamber';
  static const String wordSmith = 'word_smith';
  static const String roleMaster = 'role_master';
  static const String importedVideo = 'imported_video';
  static const String importedText = 'imported_text';
}
