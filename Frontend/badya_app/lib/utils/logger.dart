import 'package:flutter/foundation.dart';

class Logger {
  static void log(String message) {
    if (kDebugMode) {
      debugPrint('[LOG] $message');
    }
  }

  static void info(String message) {
    if (kDebugMode) {
      debugPrint('[INFO] $message');
    }
  }

  static void error(String message, [Object? error, StackTrace? stack]) {
    if (kDebugMode) {
      debugPrint('[ERROR] $message');
      if (error != null) debugPrint('Error detail: $error');
      if (stack != null) debugPrint('Stack trace: $stack');
    }
    // TODO: In production, send to Firebase Crashlytics or similar
  }

  static void warn(String message) {
    if (kDebugMode) {
      debugPrint('[WARNING] $message');
    }
  }
}
