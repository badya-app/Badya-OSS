import 'package:Badya/services/auth_service.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Badya/main.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('App renders login page smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => AuthService(auth: MockFirebaseAuth()),
          ),
        ],
        child: const MyApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2)); // Wait for animations

    // Verify that the login page is shown by finding the 'Badya' text.
    expect(find.text('Badya'), findsOneWidget);
    expect(find.text('Counter'), findsNothing);
  });
}