import 'dart:async';
import 'dart:convert';
import 'package:Badya/config/local_mode.dart';
import 'package:Badya/utils/logger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage user preferences with multi-layer caching (In-memory -> SharedPreferences -> Firestore)
class UserPreferencesService {
  final FirebaseFirestore? _firestore;
  final FirebaseAuth? _auth;
  final String? _explicitUid;

  // In-memory cache for the current session
  static final Map<String, dynamic> _memoryCache = {};

  UserPreferencesService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    String? userId,
  }) : _firestore = LocalMode.enabled
           ? firestore
           : (firestore ?? FirebaseFirestore.instance),
       _auth = LocalMode.enabled ? auth : (auth ?? FirebaseAuth.instance),
       _explicitUid = userId;

  String? get _uid =>
      _explicitUid ??
      (LocalMode.enabled ? LocalMode.guestUid : _auth?.currentUser?.uid);

  // --- Helper Methods for Caching ---

  /// Wraps a Firestore write with a timeout so an offline device can never
  /// hang the calling UI indefinitely. On timeout the write is abandoned and
  /// the error is logged — the local cache already reflects the desired state.
  Future<void> _firestoreWrite(Future<void> Function() write) async {
    if (LocalMode.enabled) return;
    try {
      await write().timeout(const Duration(seconds: 10));
    } catch (e) {
      Logger.error('Error saving to Firestore', e);
    }
  }

  String _getCacheKey(String key) => '${_uid}_$key';

  Future<void> _setLocal(String key, dynamic value) async {
    if (_uid == null) return;
    final cacheKey = _getCacheKey(key);
    _memoryCache[cacheKey] = value;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (value is String) {
        await prefs.setString(cacheKey, value);
      } else if (value is List<String>) {
        await prefs.setStringList(cacheKey, value);
      } else if (value is Map) {
        await prefs.setString(cacheKey, jsonEncode(value));
      }
    } catch (e) {
      Logger.error('Error saving to local cache', e);
    }
  }

  Future<dynamic> _getLocal(String key) async {
    if (_uid == null) return null;
    final cacheKey = _getCacheKey(key);

    // 1. Check Memory
    if (_memoryCache.containsKey(cacheKey)) {
      return _memoryCache[cacheKey];
    }

    // 2. Check SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.get(cacheKey);
      if (value != null) {
        _memoryCache[cacheKey] = value;
        return value;
      }
    } catch (e) {
      Logger.error('Error reading from local cache', e);
    }
    return null;
  }

  // --- Profile Methods ---

  Future<String> getNativeLanguage() async {
    final local = await _getLocal('native_language');
    if (local is String) {
      _syncFromFirestore(); // Background sync
      return local;
    }

    if (_uid == null) return 'Arabic';
    try {
      final doc = await _firestore.collection('users').doc(_uid).get();
      if (doc.exists && doc.data() != null) {
        final val = doc.data()!['native_language'] as String? ?? 'Arabic';
        await _setLocal('native_language', val);
        return val;
      }
    } catch (e) {
      Logger.error('Error getting native language', e);
    }
    return 'Arabic';
  }

  Future<String?> getPhotoUrl() async {
    final local = await _getLocal('photo_url');
    if (local is String) {
      _syncFromFirestore();
      return local;
    }

    if (_uid == null) return null;
    try {
      final doc = await _firestore.collection('users').doc(_uid).get();
      if (doc.exists && doc.data() != null) {
        final val = doc.data()!['photo_url'] as String?;
        if (val != null) {
          await _setLocal('photo_url', val);
        }
        return val;
      }
    } catch (e) {
      Logger.error('Error getting photo url', e);
    }
    return null;
  }

  Future<String?> getDisplayName() async {
    final local = await _getLocal('display_name');
    if (local is String) {
      _syncFromFirestore();
      return local;
    }

    if (_uid == null) return null;
    try {
      final doc = await _firestore.collection('users').doc(_uid).get();
      if (doc.exists && doc.data() != null) {
        final val = doc.data()!['display_name'] as String?;
        if (val != null) {
          await _setLocal('display_name', val);
        }
        return val;
      }
    } catch (e) {
      Logger.error('Error getting display name', e);
    }
    return null;
  }

  Future<String?> getBio() async {
    final local = await _getLocal('bio');
    if (local is String) {
      _syncFromFirestore();
      return local;
    }

    if (_uid == null) return null;
    try {
      final doc = await _firestore.collection('users').doc(_uid).get();
      if (doc.exists && doc.data() != null) {
        final val = doc.data()!['bio'] as String?;
        if (val != null) {
          await _setLocal('bio', val);
        }
        return val;
      }
    } catch (e) {
      Logger.error('Error getting bio', e);
    }
    return null;
  }

  Future<bool> getIsPublic() async {
    final local = await _getLocal('is_public');
    if (local is bool) {
      _syncFromFirestore();
      return local;
    }

    if (_uid == null) return true;
    try {
      final doc = await _firestore.collection('users').doc(_uid).get();
      if (doc.exists && doc.data() != null) {
        final val = doc.data()!['is_public'] as bool? ?? true;
        await _setLocal('is_public', val);
        return val;
      }
    } catch (e) {
      Logger.error('Error getting is_public', e);
    }
    return true;
  }

  Future<Map<String, bool>> getProfileVisibility() async {
    final local = await _getLocal('profile_visibility');
    if (local is String) {
      _syncFromFirestore();
      try {
        final decoded = Map<String, dynamic>.from(
          jsonDecode(local) as Map<String, dynamic>,
        );
        return decoded.map((key, value) => MapEntry(key, value as bool));
      } catch (e) {
        Logger.warn('Failed to decode profile visibility cache: $e');
      }
    }

    if (_uid == null) {
      return _defaultVisibility();
    }
    try {
      final doc = await _firestore.collection('users').doc(_uid).get();
      if (doc.exists && doc.data() != null) {
        final visibility = doc.data()!['profile_visibility'];
        if (visibility is Map) {
          final map = Map<String, bool>.from(
            visibility.map(
              (key, value) => MapEntry(key as String, value as bool),
            ),
          );
          await _setLocal('profile_visibility', map);
          return map;
        }
      }
    } catch (e) {
      Logger.error('Error getting profile visibility', e);
    }
    return _defaultVisibility();
  }

  Future<String> getCurrentLanguage() async {
    final local = await _getLocal('current_language');
    if (local is String) {
      _syncFromFirestore();
      return local;
    }

    if (_uid == null) return 'English';
    try {
      final doc = await _firestore.collection('users').doc(_uid).get();
      if (doc.exists && doc.data() != null) {
        final val = doc.data()!['current_language'] as String? ?? 'English';
        await _setLocal('current_language', val);
        return val;
      }
    } catch (e) {
      Logger.error('Error getting current language', e);
    }
    return 'English';
  }

  Future<List<String>> getMyLanguages() async {
    final local = await _getLocal('my_languages');
    if (local is List<String>) {
      _syncFromFirestore();
      return local;
    }

    if (_uid == null) return ['English'];
    try {
      final doc = await _firestore.collection('users').doc(_uid).get();
      if (doc.exists && doc.data() != null) {
        final languages = doc.data()!['my_languages'];
        if (languages is List) {
          final val = List<String>.from(languages);
          await _setLocal('my_languages', val);
          return val;
        }
      }
    } catch (e) {
      Logger.error('Error getting my languages', e);
    }
    return ['English'];
  }

  Future<Map<String, String>> getLearningDialects() async {
    final local = await _getLocal('learning_dialects');
    if (local is String) {
      _syncFromFirestore();
      try {
        return Map<String, String>.from(jsonDecode(local));
      } catch (e) {
        Logger.warn('Failed to decode learning dialects cache: $e');
      }
    }

    if (_uid == null) return {};
    try {
      final doc = await _firestore.collection('users').doc(_uid).get();
      if (doc.exists && doc.data() != null) {
        final dialects = doc.data()!['learning_dialects'];
        if (dialects is Map) {
          final val = Map<String, String>.from(dialects);
          await _setLocal('learning_dialects', val);
          return val;
        }
      }
    } catch (e) {
      Logger.error('Error getting learning dialects', e);
    }
    return {};
  }

  // Background sync helper
  void _syncFromFirestore() {
    if (_uid == null) return;
    _firestore
        .collection('users')
        .doc(_uid)
        .get()
        .then((doc) {
          if (doc.exists && doc.data() != null) {
            final data = doc.data()!;
            if (data['native_language'] != null) {
              _setLocal('native_language', data['native_language']);
            }
            if (data['current_language'] != null) {
              _setLocal('current_language', data['current_language']);
            }
            if (data['my_languages'] != null) {
              _setLocal(
                'my_languages',
                List<String>.from(data['my_languages']),
              );
            }
            if (data['learning_dialects'] != null) {
              _setLocal(
                'learning_dialects',
                Map<String, String>.from(data['learning_dialects']),
              );
            }
            if (data['display_name'] != null) {
              _setLocal('display_name', data['display_name']);
            }
            if (data['photo_url'] != null) {
              _setLocal('photo_url', data['photo_url']);
            }
            if (data['bio'] != null) {
              _setLocal('bio', data['bio']);
            }
            if (data['is_public'] != null) {
              _setLocal('is_public', data['is_public']);
            }
            if (data['profile_visibility'] != null) {
              _setLocal(
                'profile_visibility',
                Map<String, bool>.from(
                  Map<String, dynamic>.from(data['profile_visibility']),
                ),
              );
            }
          }
        })
        .catchError((e) {
          Logger.error('Error background syncing preferences', e);
        });
  }

  // --- Update Methods ---

  Future<void> updateCurrentLanguage(String language) async {
    await _setLocal('current_language', language);
    if (_uid == null) return;
    try {
      await _firestoreWrite(() => _firestore.collection('users').doc(_uid).set({
        'current_language': language,
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)));
    } catch (e) {
      Logger.error('Error updating current language', e);
    }
  }

  Future<void> updateDisplayName(String displayName) async {
    await _setLocal('display_name', displayName);
    if (_uid == null) return;
    try {
      await _firestoreWrite(() => _firestore.collection('users').doc(_uid).set({
        'display_name': displayName,
        'display_name_lowercase': displayName.toLowerCase(),
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)));

      // Also update Firebase Auth profile
      await _auth.currentUser?.updateDisplayName(displayName);
    } catch (e) {
      Logger.error('Error updating display name', e);
    }
  }

  Future<void> updatePhotoUrl(String? photoUrl) async {
    if (photoUrl == null) {
      _memoryCache.remove(_getCacheKey('photo_url'));
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_getCacheKey('photo_url'));
    } else {
      await _setLocal('photo_url', photoUrl);
    }

    if (_uid == null) return;
    try {
      await _firestoreWrite(() => _firestore.collection('users').doc(_uid).set({
        'photo_url': photoUrl,
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)));

      // Also update Firebase Auth profile
      await _auth.currentUser?.updatePhotoURL(photoUrl);
    } catch (e) {
      Logger.error('Error updating photo url', e);
    }
  }

  Future<void> updateBio(String bio) async {
    await _setLocal('bio', bio);
    if (_uid == null) return;
    try {
      await _firestoreWrite(() => _firestore.collection('users').doc(_uid).set({
        'bio': bio,
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)));
    } catch (e) {
      Logger.error('Error updating bio', e);
    }
  }

  Future<void> updateIsPublic(bool isPublic) async {
    await _setLocal('is_public', isPublic);
    if (_uid == null) return;
    try {
      await _firestoreWrite(() => _firestore.collection('users').doc(_uid).set({
        'is_public': isPublic,
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)));
    } catch (e) {
      Logger.error('Error updating is_public', e);
    }
  }

  Future<void> updateProfileVisibility(Map<String, bool> visibility) async {
    await _setLocal('profile_visibility', visibility);
    if (_uid == null) return;
    try {
      await _firestoreWrite(() => _firestore.collection('users').doc(_uid).set({
        'profile_visibility': visibility,
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)));
    } catch (e) {
      Logger.error('Error updating profile visibility', e);
    }
  }

  Future<void> updateMyLanguages(List<String> languages) async {
    await _setLocal('my_languages', languages);
    if (_uid == null) return;
    try {
      await _firestoreWrite(() => _firestore.collection('users').doc(_uid).set({
        'my_languages': languages,
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)));
    } catch (e) {
      Logger.error('Error updating my languages', e);
    }
  }

  Future<void> updateLearningDialects(Map<String, String> dialects) async {
    await _setLocal('learning_dialects', dialects);
    if (_uid == null) return;
    try {
      await _firestoreWrite(() => _firestore.collection('users').doc(_uid).set({
        'learning_dialects': dialects,
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)));
    } catch (e) {
      Logger.error('Error updating learning dialects', e);
    }
  }

  // --- Issue Reports ---

  /// Submit an issue report (feedback) for the current user.
  ///
  /// Stores a document in the top-level `feedback` collection with:
  /// - `user_id` (Firebase Auth UID)
  /// - `category`
  /// - `description`
  /// - `user_email` (from Firebase Auth)
  /// - `user_display_name` (from Firebase Auth)
  /// - `timestamp` (server timestamp)
  Future<void> submitIssueReport(String category, String? description) async {
    if (_uid == null) {
      Logger.warn('submitIssueReport called with no authenticated user.');
      return;
    }

    try {
      final user = _auth.currentUser;
      // The `feedback` rules cap `user_display_name` at 100 chars —
      // truncate so a long display name can't make the write fail rules
      // validation (the rules reject the whole create on over-length).
      final displayName = (user?.displayName ?? '');
      final truncatedName = displayName.length > 100
          ? displayName.substring(0, 100)
          : displayName;
      await _firestore
          .collection('feedback')
          .add({
            'user_id': _uid,
            'category': category,
            'description': description ?? '',
            'user_email': user?.email ?? '',
            'user_display_name': truncatedName,
            'timestamp': FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      Logger.error('Error submitting issue report', e);
      rethrow;
    }
  }

  Stream<DocumentSnapshot> watchUserPreferences() {
    if (_uid == null) return Stream.empty();
    return _firestore.collection('users').doc(_uid).snapshots();
  }

  Future<Map<String, dynamic>> getReaderSettings() async {
    final local = await _getLocal('reader_settings');
    if (local is String) {
      _syncFromFirestore();
      try {
        return Map<String, dynamic>.from(jsonDecode(local));
      } catch (e) {
        Logger.warn('Failed to decode reader settings cache: $e');
      }
    }

    if (_uid == null) return _defaultReaderSettings();
    try {
      final doc = await _firestore.collection('users').doc(_uid).get();
      if (doc.exists && doc.data() != null) {
        final settings = doc.data()!['reader_settings'];
        if (settings is Map) {
          final map = Map<String, dynamic>.from(settings);
          await _setLocal('reader_settings', map);
          return map;
        }
      }
    } catch (e) {
      Logger.error('Error getting reader settings', e);
    }
    return _defaultReaderSettings();
  }

  static Timer? _readerSettingsDebounceTimer;

  Future<void> updateReaderSettings(Map<String, dynamic> settings) async {
    await _setLocal('reader_settings', settings);
    if (_uid == null) return;
    _readerSettingsDebounceTimer?.cancel();
    _readerSettingsDebounceTimer = Timer(const Duration(milliseconds: 600), () async {
      try {
        await _firestoreWrite(() => _firestore.collection('users').doc(_uid).set({
          'reader_settings': settings,
          'last_updated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)));
      } catch (e) {
        Logger.error('Error updating reader settings', e);
      }
    });
  }

  Map<String, dynamic> _defaultReaderSettings() {
    return {'font_size': 18.0, 'font_family': 'Noto Serif'};
  }

  Map<String, bool> _defaultVisibility() {
    return {
      'show_xp': true,
      'show_level': true,
      'show_streak': true,
      'show_coins': false,
      'show_achievements': true,
      'show_languages': true,
      'show_following': true,
      'show_stats': true,
    };
  }
}
