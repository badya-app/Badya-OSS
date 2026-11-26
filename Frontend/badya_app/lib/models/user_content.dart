import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:Badya/config/content_types.dart';

/// Unified model for all content in the app.
/// Replaces old custom_topics, imports, and subjects models.
/// Stored in the `user_content` Firestore collection.
class UserContent {
  final String id;
  final ContentType type;
  final String title;
  final String description;
  final List<String> tags;
  final String language;
  final List<String> assignedLanguages;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Ownership & visibility
  final String userId;
  final String authorName;
  final String? authorPhotoUrl;
  final bool isPublic;
  final ContentSource source;
  /// Points to the source-of-truth content when this is a forked copy.
  /// `null` for canonical/original content that owns its source data.
  /// Set to the original `user_content` ID for forked copies.
  final String? canonicalContentId;
  final OriginType originType;

  // Canonical / source-of-truth
  /// Whether this is the original/canonical copy of the content.
  /// `true` for first-party imports (created by this user or system).
  /// `false` for forked copies (referencing someone else's canonical content).
  final bool isCanonical;

  // Progress
  final double progress;
  final ContentStatus status;
  final DateTime? lastOpenedAt;

  // Type-specific metadata (stored as Map in Firestore)
  final Map<String, dynamic>? metadata;

  // AI generation extras
  final String? aiPrompt;
  final int? wordCount;
  final int? lessonCount;

  // Segmentation preferences
  final String? segmentBy;
  final int? segmentValue;

  const UserContent({
    required this.id,
    required this.type,
    required this.title,
    this.description = '',
    this.tags = const [],
    this.language = 'English',
    this.assignedLanguages = const [],
    required this.createdAt,
    required this.updatedAt,
    required this.userId,
    this.authorName = '',
    this.authorPhotoUrl,
    this.isPublic = false,
    this.source = ContentSource.manual,
    this.canonicalContentId,
    this.originType = OriginType.userCreated,
    this.isCanonical = false,
    this.progress = 0.0,
    this.status = ContentStatus.ready,
    this.lastOpenedAt,
    this.metadata,
    this.aiPrompt,
    this.wordCount,
    this.lessonCount,
    this.segmentBy,
    this.segmentValue,
  });

  /// Create from a Firestore document snapshot.
  factory UserContent.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserContent(
      id: doc.id,
      type: ContentTypeExtension.fromString(data['type'] as String? ?? 'text'),
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      tags: data['tags'] != null
          ? List<String>.from(data['tags'] as List)
          : [],
      language: data['language'] as String? ?? 'English',
      assignedLanguages: data['assigned_languages'] != null
          ? List<String>.from(data['assigned_languages'] as List)
          : [],
      createdAt: _parseDate(data['created_at']),
      updatedAt: _parseDate(data['updated_at']),
      userId: data['user_id'] as String? ?? '',
      authorName: data['author_name'] as String? ?? '',
      authorPhotoUrl: data['author_photo_url'] as String?,
      isPublic: data['is_public'] as bool? ?? false,
      source: ContentSourceExtension.fromString(
        data['source'] as String? ?? 'manual',
      ),
      canonicalContentId: data['canonical_content_id'] as String?,
      originType: OriginTypeExtension.fromString(
        data['origin_type'] as String? ?? 'user_created',
      ),
      isCanonical: data['is_canonical'] as bool? ?? false,
      progress: (data['progress'] as num?)?.toDouble() ?? 0.0,
      status: ContentStatusExtension.fromString(
        data['status'] as String? ?? 'ready',
      ),
      lastOpenedAt: data['last_opened_at'] != null
          ? _parseDate(data['last_opened_at'])
          : null,
      metadata: data['metadata'] as Map<String, dynamic>?,
      aiPrompt: data['ai_prompt'] as String?,
      wordCount: (data['word_count'] as num?)?.toInt(),
      lessonCount: (data['lesson_count'] as num?)?.toInt(),
      segmentBy: data['segment_by'] as String?,
      segmentValue: (data['segment_value'] as num?)?.toInt(),
    );
  }

  /// Safely parse a date field from either a Firestore [Timestamp] or an ISO 8601 [String].
  static DateTime _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }

  /// Create from a raw Map (e.g. from a JSON API response or Firestore query with extra fields).
  factory UserContent.fromMap(Map<String, dynamic> data, String id) {
    return UserContent(
      id: id,
      type: ContentTypeExtension.fromString(data['type'] as String? ?? 'text'),
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      tags: data['tags'] != null
          ? List<String>.from(data['tags'] as List)
          : [],
      language: data['language'] as String? ?? 'English',
      assignedLanguages: data['assigned_languages'] != null
          ? List<String>.from(data['assigned_languages'] as List)
          : [],
      createdAt: _parseDate(data['created_at']),
      updatedAt: _parseDate(data['updated_at']),
      userId: data['user_id'] as String? ?? '',
      authorName: data['author_name'] as String? ?? '',
      authorPhotoUrl: data['author_photo_url'] as String?,
      isPublic: data['is_public'] as bool? ?? false,
      source: ContentSourceExtension.fromString(
        data['source'] as String? ?? 'manual',
      ),
      canonicalContentId: data['canonical_content_id'] as String?,
      originType: OriginTypeExtension.fromString(
        data['origin_type'] as String? ?? 'user_created',
      ),
      isCanonical: data['is_canonical'] as bool? ?? false,
      progress: (data['progress'] as num?)?.toDouble() ?? 0.0,
      status: ContentStatusExtension.fromString(
        data['status'] as String? ?? 'ready',
      ),
      lastOpenedAt: data['last_opened_at'] != null
          ? _parseDate(data['last_opened_at'])
          : null,
      metadata: data['metadata'] as Map<String, dynamic>?,
      aiPrompt: data['ai_prompt'] as String?,
      wordCount: (data['word_count'] as num?)?.toInt(),
      lessonCount: (data['lesson_count'] as num?)?.toInt(),
      segmentBy: data['segment_by'] as String?,
      segmentValue: (data['segment_value'] as num?)?.toInt(),
    );
  }

  /// Convert to Firestore document map.
  Map<String, dynamic> toFirestore() {
    final map = <String, dynamic>{
      'type': type.value,
      'title': title,
      'description': description,
      'tags': tags,
      'language': language,
      'assigned_languages': assignedLanguages,
      'created_at': Timestamp.fromDate(createdAt),
      'updated_at': Timestamp.fromDate(updatedAt),
      'user_id': userId,
      'author_name': authorName,
      'author_photo_url': authorPhotoUrl,
      'is_public': isPublic,
      'source': source.value,
      'origin_type': originType.value,
      'is_canonical': isCanonical,
      'progress': progress,
      'status': status.value,
    };

    if (canonicalContentId != null) map['canonical_content_id'] = canonicalContentId;
    if (lastOpenedAt != null) {
      map['last_opened_at'] = Timestamp.fromDate(lastOpenedAt!);
    }
    if (metadata != null) map['metadata'] = metadata;
    if (aiPrompt != null) map['ai_prompt'] = aiPrompt;
    if (wordCount != null) map['word_count'] = wordCount;
    if (lessonCount != null) map['lesson_count'] = lessonCount;
    if (segmentBy != null) map['segment_by'] = segmentBy;
    if (segmentValue != null) map['segment_value'] = segmentValue;

    return map;
  }

  /// Create a copy with updated fields.
  UserContent copyWith({
    String? id,
    ContentType? type,
    String? title,
    String? description,
    List<String>? tags,
    String? language,
    List<String>? assignedLanguages,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? userId,
    String? authorName,
    String? authorPhotoUrl,
    bool? isPublic,
    ContentSource? source,
    String? canonicalContentId,
    OriginType? originType,
    bool? isCanonical,
    double? progress,
    ContentStatus? status,
    DateTime? lastOpenedAt,
    Map<String, dynamic>? metadata,
    String? aiPrompt,
    int? wordCount,
    int? lessonCount,
    String? segmentBy,
    int? segmentValue,
  }) {
    return UserContent(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      description: description ?? this.description,
      tags: tags ?? this.tags,
      language: language ?? this.language,
      assignedLanguages: assignedLanguages ?? this.assignedLanguages,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      userId: userId ?? this.userId,
      authorName: authorName ?? this.authorName,
      authorPhotoUrl: authorPhotoUrl ?? this.authorPhotoUrl,
      isPublic: isPublic ?? this.isPublic,
      source: source ?? this.source,
      canonicalContentId: canonicalContentId ?? this.canonicalContentId,
      originType: originType ?? this.originType,
      isCanonical: isCanonical ?? this.isCanonical,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      metadata: metadata ?? this.metadata,
      aiPrompt: aiPrompt ?? this.aiPrompt,
      wordCount: wordCount ?? this.wordCount,
      lessonCount: lessonCount ?? this.lessonCount,
      segmentBy: segmentBy ?? this.segmentBy,
      segmentValue: segmentValue ?? this.segmentValue,
    );
  }
}
