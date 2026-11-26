import 'dart:convert';

import 'package:Badya/config/local_mode.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MigrationService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;

  Future<void> migrateIfNeeded() async {
    if (LocalMode.enabled) return;
    final prefs = await SharedPreferences.getInstance();
    final bool migrationCompleted =
        prefs.getBool('migration_completed') ?? false;

    if (migrationCompleted) {
      return;
    }

    final user = _auth.currentUser;
    if (user == null) {
      return;
    }

    await _migrateUserPreferences(prefs, user.uid);
    await _migrateCustomTopicsAndSections(prefs, user.uid);

    await prefs.setBool('migration_completed', true);
  }

  Future<void> _migrateUserPreferences(
    SharedPreferences prefs,
    String uid,
  ) async {
    final String? nativeLanguage = prefs.getString('native_language_$uid');
    final String? currentLanguage = prefs.getString('current_language_$uid');
    final List<String>? myLanguages = prefs.getStringList('my_languages_$uid');
    final String? learningDialectsJson = prefs.getString(
      'learning_dialects_$uid',
    );

    final Map<String, dynamic> userData = {
      'last_updated': FieldValue.serverTimestamp(),
    };

    if (nativeLanguage != null) {
      userData['native_language'] = nativeLanguage;
    }
    if (currentLanguage != null) {
      userData['current_language'] = currentLanguage;
    }
    if (myLanguages != null) {
      userData['my_languages'] = myLanguages;
    }
    if (learningDialectsJson != null) {
      try {
        final learningDialects = Map<String, String>.from(
          jsonDecode(learningDialectsJson),
        );
        userData['learning_dialects'] = learningDialects;
      } catch (e) {
        // Handle error if json is invalid
      }
    }

    if (userData.length > 1) {
      await _firestore
          .collection('users')
          .doc(uid)
          .set(userData, SetOptions(merge: true));
    }
  }

  Future<void> _migrateCustomTopicsAndSections(
    SharedPreferences prefs,
    String uid,
  ) async {
    final String? subjectsJson = prefs.getString('my_subjects_sections');
    if (subjectsJson == null) {
      return;
    }

    try {
      final List<dynamic> sections = jsonDecode(subjectsJson);
      final String currentLanguage =
          prefs.getString('current_language_$uid') ?? 'English';
      int sectionOrder = 0;
      for (var sectionData in sections) {
        if (sectionData is Map<String, dynamic>) {
          final String sectionTitle =
              sectionData['title'] ?? 'Untitled Section';
          final sectionRef = await _firestore
              .collection('users')
              .doc(uid)
              .collection('sections')
              .add({
                'title': sectionTitle,
                'order_index': sectionOrder,
                'language': currentLanguage, // Add language field per schema
              });
          sectionOrder++;

          if (sectionData.containsKey('topics') &&
              sectionData['topics'] is List) {
            for (var topicData in sectionData['topics']) {
              if (topicData is Map<String, dynamic>) {
                await _firestore
                    .collection('users')
                    .doc(uid)
                    .collection('custom_topics')
                    .add({
                      'title': topicData['title'],
                      'description': topicData['description'],
                      'image_path': topicData['image'],
                      'color': topicData['color'],
                      'is_public': topicData['isPublic'] ?? false,
                      'created_at': FieldValue.serverTimestamp(),
                      'language': currentLanguage,
                      'section_id': sectionRef.id,
                    });
              }
            }
          }
        }
      }
    } catch (e) {
      // Handle error if json is invalid
    }
  }
}
