import 'package:flutter/material.dart';

/// Content types for the unified user_content collection.
/// Maps to the `type` field in Firestore.
enum ContentType {
  aiGenerated,
  youtube,
  pdf,
  text,
  article,
  document,
}

/// Extension on ContentType for serialization, display, and styling.
extension ContentTypeExtension on ContentType {
  /// Firestore string value
  String get value {
    switch (this) {
      case ContentType.aiGenerated:
        return 'ai_generated';
      case ContentType.youtube:
        return 'youtube';
      case ContentType.pdf:
        return 'pdf';
      case ContentType.text:
        return 'text';
      case ContentType.article:
        return 'article';
      case ContentType.document:
        return 'document';
    }
  }

  /// Human-readable display name
  String get displayName {
    switch (this) {
      case ContentType.aiGenerated:
        return 'AI';
      case ContentType.youtube:
        return 'Video';
      case ContentType.pdf:
        return 'PDF';
      case ContentType.text:
        return 'Text';
      case ContentType.article:
        return 'Article';
      case ContentType.document:
        return 'Document';
    }
  }

  /// Material icon for the content type
  IconData get icon {
    switch (this) {
      case ContentType.aiGenerated:
        return Icons.auto_awesome_rounded;
      case ContentType.youtube:
        return Icons.play_circle_rounded;
      case ContentType.pdf:
        return Icons.picture_as_pdf_rounded;
      case ContentType.text:
        return Icons.sticky_note_2_rounded;
      case ContentType.article:
        return Icons.article_rounded;
      case ContentType.document:
        return Icons.description_rounded;
    }
  }

  /// Accent color for the content type card
  Color get accentColor {
    switch (this) {
      case ContentType.aiGenerated:
        return const Color(0xFF9B59B6); // Purple
      case ContentType.youtube:
        return const Color(0xFFE74C3C); // Red
      case ContentType.pdf:
        return const Color(0xFF2ECC71); // Green
      case ContentType.text:
        return const Color(0xFF2ECC71); // Green
      case ContentType.article:
        return const Color(0xFF3498DB); // Blue
      case ContentType.document:
        return const Color(0xFF2ECC71); // Green
    }
  }

  /// Default thumbnail asset path
  String get defaultThumbnail {
    switch (this) {
      case ContentType.aiGenerated:
        return 'assets/thumbnails/aithumbnail.png';
      case ContentType.youtube:
        return 'assets/thumbnails/videothumbnail.png';
      case ContentType.pdf:
      case ContentType.text:
      case ContentType.document:
      case ContentType.article:
        return 'assets/thumbnails/bookthumbnail.png';
    }
  }

  /// Parse from Firestore string value
  static ContentType fromString(String value) {
    switch (value) {
      case 'ai_generated':
        return ContentType.aiGenerated;
      case 'youtube':
        return ContentType.youtube;
      case 'pdf':
        return ContentType.pdf;
      case 'text':
        return ContentType.text;
      case 'article':
        return ContentType.article;
      case 'document':
        return ContentType.document;
      default:
        return ContentType.text; // Fallback
    }
  }
}

/// Source type for user_content: where the content came from.
enum ContentSource {
  aiGenerated,
  import,
  manual,
  suggestion,
}

/// Extension on ContentSource for serialization.
extension ContentSourceExtension on ContentSource {
  String get value {
    switch (this) {
      case ContentSource.aiGenerated:
        return 'ai_generated';
      case ContentSource.import:
        return 'import';
      case ContentSource.manual:
        return 'manual';
      case ContentSource.suggestion:
        return 'suggestion';
    }
  }

  static ContentSource fromString(String value) {
    switch (value) {
      case 'ai_generated':
        return ContentSource.aiGenerated;
      case 'import':
        return ContentSource.import;
      case 'manual':
        return ContentSource.manual;
      case 'suggestion':
        return ContentSource.suggestion;
      default:
        return ContentSource.manual;
    }
  }
}

/// Origin type indicating how the content was acquired.
enum OriginType {
  userCreated,
  forked,
  builtin,
}

/// Extension on OriginType for serialization.
extension OriginTypeExtension on OriginType {
  String get value {
    switch (this) {
      case OriginType.userCreated:
        return 'user_created';
      case OriginType.forked:
        return 'forked';
      case OriginType.builtin:
        return 'builtin';
    }
  }

  /// Icon for the origin indicator
  IconData get icon {
    switch (this) {
      case OriginType.userCreated:
        return Icons.edit_rounded;
      case OriginType.forked:
        return Icons.call_split_rounded;
      case OriginType.builtin:
        return Icons.auto_awesome_rounded;
    }
  }

  static OriginType fromString(String value) {
    switch (value) {
      case 'user_created':
        return OriginType.userCreated;
      case 'forked':
        return OriginType.forked;
      case 'builtin':
        return OriginType.builtin;
      default:
        return OriginType.userCreated;
    }
  }
}

/// Status of a content item.
enum ContentStatus {
  ready,
  processing,
  failed,
}

/// Extension on ContentStatus for serialization.
extension ContentStatusExtension on ContentStatus {
  String get value {
    switch (this) {
      case ContentStatus.ready:
        return 'ready';
      case ContentStatus.processing:
        return 'processing';
      case ContentStatus.failed:
        return 'failed';
    }
  }

  static ContentStatus fromString(String value) {
    switch (value) {
      case 'ready':
        return ContentStatus.ready;
      case 'processing':
        return ContentStatus.processing;
      case 'failed':
        return ContentStatus.failed;
      default:
        return ContentStatus.ready;
    }
  }
}

// ─── Metadata Variant Classes ──────────────────────────────────────────

/// Metadata for YouTube video imports.
class YouTubeMetadata {
  final String sourceUrl;
  final String? thumbnailUrl;
  final int? durationSeconds;
  final String? transcriptQuality; // "manual" | "auto" | "none"
  const YouTubeMetadata({
    required this.sourceUrl,
    this.thumbnailUrl,
    this.durationSeconds,
    this.transcriptQuality,
  });

  factory YouTubeMetadata.fromMap(Map<String, dynamic> map) {
    return YouTubeMetadata(
      sourceUrl: map['source_url'] as String? ?? '',
      thumbnailUrl: map['thumbnail_url'] as String?,
      durationSeconds: map['duration_seconds'] as int?,
      transcriptQuality: map['transcript_quality'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'source_url': sourceUrl,
      if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (transcriptQuality != null) 'transcript_quality': transcriptQuality,
    };
  }
}

/// Metadata for document (PDF, TXT) imports.
class DocumentMetadata {
  final String? filePath;
  final String? fileName;
  final int? fileSizeBytes;
  final String? pageCount;
  final String? extractedTextPreview;

  const DocumentMetadata({
    this.filePath,
    this.fileName,
    this.fileSizeBytes,
    this.pageCount,
    this.extractedTextPreview,
  });

  factory DocumentMetadata.fromMap(Map<String, dynamic> map) {
    return DocumentMetadata(
      filePath: map['file_path'] as String?,
      fileName: map['file_name'] as String?,
      fileSizeBytes: map['file_size_bytes'] as int?,
      pageCount: map['page_count'] as String?,
      extractedTextPreview: map['extracted_text_preview'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (filePath != null) 'file_path': filePath,
      if (fileName != null) 'file_name': fileName,
      if (fileSizeBytes != null) 'file_size_bytes': fileSizeBytes,
      if (pageCount != null) 'page_count': pageCount,
      if (extractedTextPreview != null)
        'extracted_text_preview': extractedTextPreview,
    };
  }
}

/// Metadata for AI-generated content.
class AiGeneratedMetadata {
  final String prompt;
  final int wordCount;
  final int lessonCount;
  final String? modelUsed;

  const AiGeneratedMetadata({
    required this.prompt,
    required this.wordCount,
    required this.lessonCount,
    this.modelUsed,
  });

  factory AiGeneratedMetadata.fromMap(Map<String, dynamic> map) {
    return AiGeneratedMetadata(
      prompt: map['prompt'] as String? ?? '',
      wordCount: (map['word_count'] as num?)?.toInt() ?? 0,
      lessonCount: (map['lesson_count'] as num?)?.toInt() ?? 0,
      modelUsed: map['model_used'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'prompt': prompt,
      'word_count': wordCount,
      'lesson_count': lessonCount,
      if (modelUsed != null) 'model_used': modelUsed,
    };
  }
}

/// Metadata for text/plain content.
class TextMetadata {
  final String rawText;
  final int characterCount;

  const TextMetadata({
    required this.rawText,
    required this.characterCount,
  });

  factory TextMetadata.fromMap(Map<String, dynamic> map) {
    return TextMetadata(
      rawText: map['raw_text'] as String? ?? '',
      characterCount: (map['character_count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'raw_text': rawText,
      'character_count': characterCount,
    };
  }
}

/// Metadata for web article imports.
class ArticleMetadata {
  final String sourceUrl;
  final String? siteName;
  final String? extractedContent;
  final String? author;

  const ArticleMetadata({
    required this.sourceUrl,
    this.siteName,
    this.extractedContent,
    this.author,
  });

  factory ArticleMetadata.fromMap(Map<String, dynamic> map) {
    return ArticleMetadata(
      sourceUrl: map['source_url'] as String? ?? '',
      siteName: map['site_name'] as String?,
      extractedContent: map['extracted_content'] as String?,
      author: map['author'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'source_url': sourceUrl,
      if (siteName != null) 'site_name': siteName,
      if (extractedContent != null) 'extracted_content': extractedContent,
      if (author != null) 'author': author,
    };
  }
}

