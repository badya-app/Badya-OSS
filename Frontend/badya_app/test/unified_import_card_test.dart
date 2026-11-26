import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Badya/widgets/unified_import_card.dart';

void main() {
  group('UnifiedImportCard Tests', () {
    testWidgets('renders ready state correctly', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnifiedImportCard(
              title: 'Test Import',
              description: 'A test import',
              status: 'ready',
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.text('Test Import'), findsOneWidget);
      expect(find.text('A test import'), findsOneWidget);
    });

    testWidgets('renders failed state correctly and shows retry button', (WidgetTester tester) async {
      bool retryClicked = false;
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnifiedImportCard(
              title: 'Failed Import',
              description: 'A failed import',
              status: 'failed',
              onTap: () {},
              onRetry: () {
                retryClicked = true;
              },
            ),
          ),
        ),
      );

      // Verify the title is displayed
      expect(find.text('Failed Import'), findsOneWidget);

      // Check for failed hint text
      expect(find.textContaining('Import failed'), findsOneWidget);
      
      // Tap the popup menu to reveal 'Retry'
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();

      // Verify 'Retry' button appears
      expect(find.text('Retry'), findsOneWidget);

      // Tap 'Retry'
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      // Verify callback was triggered
      expect(retryClicked, isTrue);
    });
  });
}
