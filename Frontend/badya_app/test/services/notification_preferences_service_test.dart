import 'package:flutter_test/flutter_test.dart';
import 'package:Badya/services/notification_preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:mockito/mockito.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

// Mock FirebaseAuth
class MockFirebaseAuth extends Mock implements FirebaseAuth {
  MockUser? _currentUser;

  @override
  MockUser? get currentUser => _currentUser;

  void setCurrentUser(String uid) {
    _currentUser = MockUser(uid);
  }
}

class MockUser extends Mock implements User {
  final String _uid;

  MockUser(this._uid);

  @override
  String get uid => _uid;
}


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationPreferencesService Tests', () {
    late NotificationPreferencesService preferencesService;
    late MockFirebaseAuth mockAuth;
    late FakeFirebaseFirestore mockFirestore;
    const testUserId = 'test-user-123';

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      mockFirestore = FakeFirebaseFirestore();
      mockAuth = MockFirebaseAuth();
      mockAuth.setCurrentUser(testUserId);

      preferencesService = NotificationPreferencesService(
        firestore: mockFirestore,
        auth: mockAuth,
        userId: testUserId,
      );

      // Give it time to initialize
      await Future.delayed(const Duration(milliseconds: 100));
    });

    group('Reminder Time Tests', () {
      test('getReminderTime returns default time on first launch', () async {
        final time = await preferencesService.getReminderTime();
        expect(time.hour, equals(19)); // 7:00 PM
        expect(time.minute, equals(0));
      });

      test('saveReminderTime saves and retrieves correctly', () async {
        const newTime = TimeOfDay(hour: 21, minute: 30);
        await preferencesService.saveReminderTime(newTime);

        final retrieved = await preferencesService.getReminderTime();
        expect(retrieved.hour, equals(21));
        expect(retrieved.minute, equals(30));
      });

      test('saveReminderTime notifies listeners', () async {
        bool listenerCalled = false;
        preferencesService.addListener(() {
          listenerCalled = true;
        });

        await preferencesService.saveReminderTime(
          const TimeOfDay(hour: 20, minute: 0),
        );

        expect(listenerCalled, isTrue);
      });
    });

    group('Master Toggle Tests', () {
      test('getMasterToggle returns default value on first launch', () async {
        final toggle = await preferencesService.getMasterToggle();
        expect(toggle, isTrue);
      });

      test('saveMasterToggle saves and retrieves correctly', () async {
        await preferencesService.saveMasterToggle(false);

        final retrieved = await preferencesService.getMasterToggle();
        expect(retrieved, isFalse);
      });

      test('saveMasterToggle notifies listeners', () async {
        bool listenerCalled = false;
        preferencesService.addListener(() {
          listenerCalled = true;
        });

        await preferencesService.saveMasterToggle(false);

        expect(listenerCalled, isTrue);
      });
    });

    test('clearPreferences removes all stored preferences', () async {
      // Set some preferences first
      await preferencesService.saveReminderTime(
        const TimeOfDay(hour: 20, minute: 0),
      );
      await preferencesService.saveMasterToggle(false);

      // Clear all
      await preferencesService.clearPreferences();

      // Verify they're cleared (should return defaults)
      final time = await preferencesService.getReminderTime();
      expect(time.hour, equals(19)); // Back to default

      final toggle = await preferencesService.getMasterToggle();
      expect(toggle, isTrue); // Back to default
    });
  });
}
