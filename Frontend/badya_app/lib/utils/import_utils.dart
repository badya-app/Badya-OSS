class ImportUtils {
  static bool isVideoImport(Map<String, dynamic> item) {
    final Map<String, dynamic> metadata = Map<String, dynamic>.from(
      item['metadata'] ?? {},
    );
    final String sourceType =
        (metadata['source_type'] ?? (item['source_type'] ?? ''))
            .toString()
            .toLowerCase();
    return sourceType == 'youtube' || metadata['duration'] != null;
  }

  static bool isTextImport(Map<String, dynamic> item) {
    final Map<String, dynamic> metadata = Map<String, dynamic>.from(
      item['metadata'] ?? {},
    );
    final String type = (metadata['type'] ?? '').toString().toLowerCase();
    final String sourceType =
        (metadata['source_type'] ?? (item['source_type'] ?? ''))
            .toString()
            .toLowerCase();
    return type == 'text' || sourceType == 'text';
  }

  static String displayType(Map<String, dynamic> item) {
    if (isVideoImport(item)) return 'VIDEO';
    if (isTextImport(item)) return 'TEXT';
    return 'FILE';
  }

  static String displayDescription(Map<String, dynamic> item) {
    if (item['status'] == 'ready') {
      final double? progress = (item['overall_progress'] as num?)?.toDouble();
      if (progress != null && progress >= 0.99) return 'Completed';
      if (progress != null && progress > 0) {
        return '${(progress * 100).toInt()}% watched';
      }
      return 'Ready to learn';
    } else if (item['status'] == 'failed') {
      return 'Failed';
    }
    return 'Processing...';
  }
}
