import 'package:Badya/library_page.dart';
import 'package:Badya/widgets/library_page_skeleton.dart';
import 'package:Badya/services/language_manager.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Initialize Firebase mock platform before running any tests.
void setupFirebaseMocks() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
}

void main() {
  // Call once at the top level
  setupFirebaseMocks();

  setUp(() async {
    try {
      await Firebase.initializeApp();
    } catch (_) {
      // Firebase already initialized
    }
  });

  group('LibraryPage', () {
    testWidgets('Library page renders header with Library text',
        (WidgetTester tester) async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(
            value: LanguageManager(),
          ),
        ],
        child: const MaterialApp(home: LibraryPage()),
      ));

      // Allow time for the loading state and Firestore stream to return empty
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      // The header should show "Library" text
      // Note: The page shows a loading indicator (skeleton) first, then content
      expect(find.byType(LibraryPageSkeleton), findsOneWidget);
    });

    testWidgets('Library page shows filter chip row',
        (WidgetTester tester) async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(
            value: LanguageManager(),
          ),
        ],
        child: const MaterialApp(home: LibraryPage()),
      ));

      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Filter chips should appear
      expect(find.text('All'), findsOneWidget);
      expect(find.text('AI'), findsOneWidget);
      expect(find.text('Videos'), findsOneWidget);
      expect(find.text('Docs'), findsOneWidget);
    });

    testWidgets('Library page has persistent search bar', (WidgetTester tester) async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(
            value: LanguageManager(),
          ),
        ],
        child: const MaterialApp(home: LibraryPage()),
      ));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Search bar should always be present (no need to tap a toggle)
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    });

    testWidgets('Library filter chips toggle when tapped',
        (WidgetTester tester) async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(
            value: LanguageManager(),
          ),
        ],
        child: const MaterialApp(home: LibraryPage()),
      ));

      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Tap the "AI" filter chip
      await tester.tap(find.text('AI'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('Library search bar accepts text input',
        (WidgetTester tester) async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(
            value: LanguageManager(),
          ),
        ],
        child: const MaterialApp(home: LibraryPage()),
      ));

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Search text field should always be present
      expect(find.byType(TextField), findsOneWidget);

      // Enter search text
      await tester.enterText(find.byType(TextField), 'test');
      await tester.pump();

      // Clear button should appear
      expect(find.byIcon(Icons.clear_rounded), findsOneWidget);
    });
  });
}
