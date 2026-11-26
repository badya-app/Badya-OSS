import 'package:media_kit/media_kit.dart';

class MediaService {
  static bool _initialized = false;

  static void ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    MediaKit.ensureInitialized();
  }
}
