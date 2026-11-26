import 'dart:async';

import 'package:Badya/config/local_mode.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:Badya/utils/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageManager extends ChangeNotifier {
  List<String> _myLanguages = ['English'];
  String _currentLanguage = 'English';
  String _nativeLanguage = 'Arabic';
  bool _isLoading = true;

  /// Tracks the UID that was loaded so we can detect account switches.
  String? _loadedUid;

  /// Subscription to auth state changes — cancelled on dispose.
  StreamSubscription<User?>? _authSubscription;

  List<String> get myLanguages => _myLanguages;
  String get currentLanguage => _currentLanguage;
  String get nativeLanguage => _nativeLanguage;
  bool get isLoading => _isLoading;

  LanguageManager() {
    _loadPreferences();
    if (!LocalMode.enabled) {
      // Listen for auth state changes (sign-in / sign-out / account switch)
      // so language data is always fresh for the current user.
      _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
        final newUid = user?.uid;
        if (newUid != _loadedUid) {
          // Reset to defaults so stale data from the previous user is never
          // shown while the new user's preferences are loading.
          _myLanguages = ['English'];
          _currentLanguage = 'English';
          _nativeLanguage = 'Arabic';
          _isLoading = true;
          notifyListeners();
          _loadPreferences();
        }
      });
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    if (LocalMode.enabled) {
      try {
        final prefs = await SharedPreferences.getInstance();
        const uid = LocalMode.guestUid;
        _currentLanguage =
            prefs.getString('${uid}_current_language') ?? 'English';
        _nativeLanguage =
            prefs.getString('${uid}_native_language') ?? 'Arabic';
        _myLanguages =
            prefs.getStringList('${uid}_my_languages') ?? ['English'];
        _loadedUid = uid;
      } catch (e) {
        Logger.error('Error loading local preferences', e);
      }
      _isLoading = false;
      notifyListeners();
      return;
    }

    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _loadedUid = null;
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        _currentLanguage = data['current_language'] ?? 'English';
        _nativeLanguage = data['native_language'] ?? 'Arabic';
        _myLanguages = List<String>.from(data['my_languages'] ?? ['English']);
      }
      _loadedUid = uid;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      Logger.error('Error loading preferences', e);
      _loadedUid = uid;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addLanguage(String language) async {
    if (_myLanguages.contains(language)) return;

    _myLanguages.add(language);
    notifyListeners();

    // Persist to Firestore
    await _savePreferences();
  }

  Future<void> removeLanguage(String language) async {
    _myLanguages.remove(language);
    if (_currentLanguage == language && _myLanguages.isNotEmpty) {
      _currentLanguage = _myLanguages.first;
    }
    notifyListeners();

    // Persist to Firestore
    await _savePreferences();
  }

  Future<void> updateCurrentLanguage(String language) async {
    _currentLanguage = language;
    notifyListeners();
    await _savePreferences();
  }

  Future<void> _savePreferences() async {
    if (LocalMode.enabled) {
      try {
        final prefs = await SharedPreferences.getInstance();
        const uid = LocalMode.guestUid;
        await prefs.setString('${uid}_current_language', _currentLanguage);
        await prefs.setString('${uid}_native_language', _nativeLanguage);
        await prefs.setStringList('${uid}_my_languages', _myLanguages);
      } catch (e) {
        Logger.error('Error saving local preferences', e);
      }
      return;
    }

    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      // 10s timeout so an offline device can never hang the calling UI
      // indefinitely (offline writes don't throw — they just never complete).
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({
        'current_language': _currentLanguage,
        'native_language': _nativeLanguage,
        'my_languages': _myLanguages,
        'last_updated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 10));
    } catch (e) {
      Logger.error('Error saving preferences', e);
    }
  }

  Future<void> refresh() async {
    await _loadPreferences();
  }
}
