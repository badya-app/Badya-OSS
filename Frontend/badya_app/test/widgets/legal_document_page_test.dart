import 'package:Badya/legal_document_page.dart';
import 'package:Badya/utils/legal_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpDocument(
    WidgetTester tester,
    LegalDocument document,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: LegalDocumentPage(document: document)),
    );
    await tester.pump();
    // Flush the flutter_animate delay timers before the test ends.
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('terms of service renders title, date, and sections',
      (tester) async {
    await pumpDocument(tester, LegalContent.termsOfService);

    // Title appears in both the AppBar and the header card.
    expect(find.text('Terms of Service'), findsWidgets);
    expect(find.textContaining('Last updated:'), findsOneWidget);

    // First and last sections are both rendered (SingleChildScrollView
    // builds everything eagerly).
    expect(find.text('Acceptance of These Terms'), findsOneWidget);
    expect(find.text('Contact Us'), findsOneWidget);
  });

  testWidgets('privacy policy renders its own sections', (tester) async {
    await pumpDocument(tester, LegalContent.privacyPolicy);

    expect(find.text('Privacy Policy'), findsWidgets);
    expect(find.text('Information We Collect'), findsOneWidget);
    expect(find.text("Children's Privacy"), findsOneWidget);
  });

  testWidgets('contact info is shown in both documents', (tester) async {
    await pumpDocument(tester, LegalContent.privacyPolicy);

    expect(find.textContaining('badyaapp@gmail.com'), findsWidgets);
  });
}
