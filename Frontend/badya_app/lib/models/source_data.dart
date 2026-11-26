import 'package:cloud_firestore/cloud_firestore.dart';

/// Stores the raw source content for a user_content item.
///
/// Located at `user_content/{contentId}/source/raw` as a single document.
/// This enables self-contained re-segmentation without relying on the
/// legacy `users/{uid}/imports/{importId}` collection.
class SourceData {
  /// Full raw text for text/DOC imports.
  final String? rawText;

  /// Full transcript JSON string for YouTube imports.
  final String? transcriptJson;

  /// Original source URL (YouTube video, article, etc.)
  final String? sourceUrl;

  /// Source type: 'youtube', 'text', 'pdf', 'txt', 'url', etc.
  final String? sourceType;

  /// Content length metadata
  final int? wordCount;
  final int? characterCount;

  /// Timestamps (populated when reading from Firestore).
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const SourceData({
    this.rawText,
    this.transcriptJson,
    this.sourceUrl,
    this.sourceType,
    this.wordCount,
    this.characterCount,
    this.createdAt,
    this.updatedAt,
  });

  /// Create from a Firestore document map.
  factory SourceData.fromMap(Map<String, dynamic> map) {
    return SourceData(
      rawText: map['raw_text'] as String?,
      transcriptJson: map['transcript_json'] as String?,
      sourceUrl: map['source_url'] as String?,
      sourceType: map['source_type'] as String?,
      wordCount: (map['word_count'] as num?)?.toInt(),
      characterCount: (map['character_count'] as num?)?.toInt(),
      createdAt: (map['created_at'] as Timestamp?)?.toDate(),
      updatedAt: (map['updated_at'] as Timestamp?)?.toDate(),
    );
  }

  /// Convert to Firestore document map.
  ///
  /// Note: [createdAt] and [updatedAt] are intentionally omitted here.
  /// They are written as `FieldValue.serverTimestamp()` at the call site
  /// so that Firestore sets accurate server-side timestamps.
  Map<String, dynamic> toFirestore() {
    final map = <String, dynamic>{};
    if (rawText != null) map['raw_text'] = rawText;
    if (transcriptJson != null) map['transcript_json'] = transcriptJson;
    if (sourceUrl != null) map['source_url'] = sourceUrl;
    if (sourceType != null) map['source_type'] = sourceType;
    if (wordCount != null) map['word_count'] = wordCount;
    if (characterCount != null) map['character_count'] = characterCount;
    return map;
  }
}
