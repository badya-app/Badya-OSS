import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:Badya/utils/logger.dart';
import 'package:Badya/config/content_types.dart';

/// TTL-based local storage cache for AI-generated content.
///
/// Cache entries expire after [defaultTTL] (7 days).
/// Only caches AI-generated content — imported/YouTube content is not cached.
class CacheService {
  static const String _cachePrefix = 'cache_';
  static const String _expiryPrefix = 'cache_expiry_';
  static const String _cacheKeysKey = 'cache_keys';
  static const Duration defaultTTL = Duration(days: 7);

  final SharedPreferences _prefs;

  CacheService(this._prefs);

  /// Check if caching is enabled for the given content type.
  /// Only AI-generated content is cached.
  static bool shouldCache(ContentType type) {
    return type == ContentType.aiGenerated;
  }

  /// Store a JSON-encodable value in the cache.
  Future<void> setCache({
    required String contentId,
    required Map<String, dynamic> data,
    Duration? ttl,
  }) async {
    try {
      final expiryTime = DateTime.now().add(ttl ?? defaultTTL);

      await _prefs.setString('$_cachePrefix$contentId', jsonEncode(data));
      await _prefs.setString(
        '$_expiryPrefix$contentId',
        expiryTime.toIso8601String(),
      );

      // Track this key
      final keys = List<String>.from(_prefs.getStringList(_cacheKeysKey) ?? []);
      if (!keys.contains(contentId)) {
        keys.add(contentId);
        await _prefs.setStringList(_cacheKeysKey, keys);
      }

      Logger.info('CacheService: Cached content $contentId');
    } catch (e) {
      Logger.error('CacheService: Error caching content $contentId', e);
    }
  }

  /// Retrieve cached data for a content ID.
  /// Returns null if not cached or expired.
  Future<Map<String, dynamic>?> getCache(String contentId) async {
    try {
      // Check expiry
      final expiryStr = _prefs.getString('$_expiryPrefix$contentId');
      if (expiryStr == null) return null;

      final expiryTime = DateTime.parse(expiryStr);
      if (DateTime.now().isAfter(expiryTime)) {
        // Expired — clean up
        await _removeCache(contentId);
        Logger.info('CacheService: Cache expired for $contentId');
        return null;
      }

      final dataStr = _prefs.getString('$_cachePrefix$contentId');
      if (dataStr == null) return null;

      final decoded = jsonDecode(dataStr) as Map<String, dynamic>;
      return decoded;
    } catch (e) {
      Logger.error('CacheService: Error reading cache for $contentId', e);
      return null;
    }
  }

  /// Check if a content ID has valid (non-expired) cache.
  Future<bool> hasValidCache(String contentId) async {
    final data = await getCache(contentId);
    return data != null;
  }

  /// Remove a specific cache entry.
  Future<void> _removeCache(String contentId) async {
    await _prefs.remove('$_cachePrefix$contentId');
    await _prefs.remove('$_expiryPrefix$contentId');

    final keys = List<String>.from(_prefs.getStringList(_cacheKeysKey) ?? []);
    keys.remove(contentId);
    await _prefs.setStringList(_cacheKeysKey, keys);
  }

  /// Clear all expired cache entries.
  /// Call this on app start.
  Future<int> clearExpired() async {
    final keys = List<String>.from(_prefs.getStringList(_cacheKeysKey) ?? []);
    int removedCount = 0;

    for (final key in keys) {
      final expiryStr = _prefs.getString('$_expiryPrefix$key');
      if (expiryStr == null) {
        await _removeCache(key);
        removedCount++;
        continue;
      }

      try {
        final expiryTime = DateTime.parse(expiryStr);
        if (DateTime.now().isAfter(expiryTime)) {
          await _removeCache(key);
          removedCount++;
        }
      } catch (_) {
        await _removeCache(key);
        removedCount++;
      }
    }

    if (removedCount > 0) {
      Logger.info('CacheService: Cleared $removedCount expired entries');
    }
    return removedCount;
  }

  /// Clear all cache entries (for testing or manual clearing).
  Future<void> clearAll() async {
    final keys = List<String>.from(_prefs.getStringList(_cacheKeysKey) ?? []);
    for (final key in keys) {
      await _prefs.remove('$_cachePrefix$key');
      await _prefs.remove('$_expiryPrefix$key');
    }
    await _prefs.remove(_cacheKeysKey);
    Logger.info('CacheService: Cleared all cache entries');
  }

  /// Get total number of cached items.
  int get cacheCount {
    final keys = _prefs.getStringList(_cacheKeysKey);
    return keys?.length ?? 0;
  }

  /// Get list of cached content IDs.
  List<String> get cachedIds {
    return List<String>.from(_prefs.getStringList(_cacheKeysKey) ?? []);
  }
}
