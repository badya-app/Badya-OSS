import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// Configuration for running Badya in offline/local guest mode without Firebase.
///
/// Enable via: `flutter run --dart-define=LOCAL_MODE=true`
class LocalMode {
  static const bool enabled = bool.fromEnvironment(
    'LOCAL_MODE',
    defaultValue: false,
  );

  static const String guestUid = 'local_guest_user';
  static const int defaultCoins = 150;

  /// Loads predefined system topics from bundled assets for local mode.
  static Future<List<Map<String, dynamic>>> loadSeedTopics() async {
    final raw = await rootBundle.loadString('assets/seed_topics.json');
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.cast<Map<String, dynamic>>();
  }
}
