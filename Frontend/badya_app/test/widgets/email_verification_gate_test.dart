import 'package:Badya/main.dart';
import 'package:Badya/services/auth_service.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
      'AuthWrapper routes unverified signed-in users to EmailVerificationPage',
      (tester) async {
    final authService = AuthService(
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
          uid: 'u1',
          email: 'learner@badya.app',
          isEmailVerified: false,
        ),
      ),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: authService),
        ],
        child: const MyApp(),
      ),
    );
    await tester.pump(); // run the initState profile refresh
    await tester.pump(); // rebuild after the refresh completes
    await tester.pump(const Duration(seconds: 1)); // flush animations

    expect(find.text('Verify your email'), findsOneWidget);
    expect(find.text('learner@badya.app'), findsOneWidget);
  });
}
