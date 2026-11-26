import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a single notification message in the global pool.
class NotificationMessage {
  final String id;
  final String text;
  final String category; // 'streak', 'engagement', 'achievement', 'vocabulary'
  final String topic;    // 'motivation', 'alert', 'fun', 'educational', 'competitive'
  final int? minStreak;
  final int? maxStreak;
  final double priority; // 0.0 to 1.0 (weight in selection pool)
  final DateTime? createdAt;
  final DateTime? updatedAt;

  NotificationMessage({
    required this.id,
    required this.text,
    required this.category,
    required this.topic,
    this.minStreak,
    this.maxStreak,
    this.priority = 1.0,
    this.createdAt,
    this.updatedAt,
  });

  factory NotificationMessage.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
    SnapshotOptions? options,
  ) {
    final data = snapshot.data();
    return NotificationMessage(
      id: snapshot.id,
      text: data?['text'] ?? '',
      category: data?['category'] ?? 'engagement',
      topic: data?['topic'] ?? 'motivation',
      minStreak: data?['minStreak'],
      maxStreak: data?['maxStreak'],
      priority: (data?['priority'] as num?)?.toDouble() ?? 1.0,
      createdAt: (data?['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data?['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'text': text,
      'category': category,
      'topic': topic,
      if (minStreak != null) 'minStreak': minStreak,
      if (maxStreak != null) 'maxStreak': maxStreak,
      'priority': priority,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
