import 'package:Badya/privacy_visibility_settings_page.dart';
import 'package:Badya/services/user_preferences_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PrivacyVisibilitySettingsPage Tests (Task 12.2)', () {
    late FakeFirebaseFirestore fakeFirestore;
    late MockFirebaseAuth mockAuth;
    late UserPreferencesService prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      fakeFirestore = FakeFirebaseFirestore();
      mockAuth = MockFirebaseAuth(signedIn: true);
      prefs = UserPreferencesService(
        firestore: fakeFirestore,
        auth: mockAuth,
      );

      // Create a user document
      final uid = mockAuth.currentUser!.uid;
      await fakeFirestore.collection('users').doc(uid).set({
        'profile_visibility': {
          'show_xp': true,
          'show_level': true,
          'show_streak': true,
          'show_coins': false,
          'show_achievements': true,
          'show_languages': true,
          'show_following': true,
          'show_stats': true,
        },
      });
    });

    testWidgets('PrivacyVisibilitySettingsPage renders all visibility toggles',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PrivacyVisibilitySettingsPage(prefs: prefs),
        ),
      );

      await tester.pumpAndSettle();

      // Check that all visibility toggles are present
      expect(find.text('Show XP & Progress Bar'), findsOneWidget);
      expect(find.text('Show Level Badge'), findsOneWidget);
      expect(find.text('Show Streak & Calendar'), findsOneWidget);
      expect(find.text('Show Coins'), findsOneWidget);
      expect(find.text('Show Achievements'), findsOneWidget);
      expect(find.text('Show Languages'), findsOneWidget);
      expect(find.text('Show Following/Followers'), findsOneWidget);
      expect(find.text('Show Stats Row'), findsOneWidget);
    });

    testWidgets('Toggling visibility updates the switch state',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PrivacyVisibilitySettingsPage(prefs: prefs),
        ),
      );

      await tester.pumpAndSettle();

      // Find the "Show Coins" switch (should be off by default)
      final coinsSwitch = find.byType(Switch).at(3); // show_coins is the 4th item
      expect(tester.widget<Switch>(coinsSwitch).value, false);

      // Tap the switch
      await tester.tap(coinsSwitch);
      await tester.pumpAndSettle();

      // Switch should now be on
      expect(tester.widget<Switch>(coinsSwitch).value, true);
    });
  });
}

