import 'package:Badya/email_verification_page.dart';
import 'package:Badya/services/auth_service.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  Widget wrap(AuthService authService) {
    return ChangeNotifierProvider<AuthService>(
      create: (_) => authService,
      child: const MaterialApp(home: EmailVerificationPage()),
    );
  }

  AuthService unverifiedService() {
    return AuthService(
      auth: MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
          uid: 'u1',
          email: 'learner@badya.app',
          isEmailVerified: false,
        ),
      ),
    );
  }

  testWidgets('renders verification copy with the user email',
      (tester) async {
    await tester.pumpWidget(wrap(unverifiedService()));
    await tester.pump();

    expect(find.text('Verify your email'), findsOneWidget);
    expect(find.text('learner@badya.app'), findsOneWidget);
    expect(find.textContaining('OPEN EMAIL APP'), findsOneWidget);
    expect(find.text('RESEND EMAIL'), findsOneWidget);
    expect(find.textContaining("I'VE VERIFIED"), findsOneWidget);
    expect(find.textContaining('Log out'), findsOneWidget);

    // Flush the flutter_animate delay timers before the test ends.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('resending starts a 60s cooldown countdown', (tester) async {
    await tester.pumpWidget(wrap(unverifiedService()));
    await tester.pump();

    await tester.tap(find.text('RESEND EMAIL'));
    await tester.pump(); // let the async resend run
    await tester.pump(); // rebuild with cooldown started
    await tester.pump(const Duration(seconds: 1)); // first timer tick

    expect(find.text('RESEND EMAIL (59S)'), findsOneWidget);

    // Cooldown is enforced: tapping again while cooling down does nothing.
    await tester.tap(find.text('RESEND EMAIL (59S)'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('RESEND EMAIL (58S)'), findsOneWidget);

    // Let the cooldown timer expire so no timers are left pending.
    await tester.pump(const Duration(seconds: 61));
  });

  testWidgets('continue shows not-verified notice when email is unverified',
      (tester) async {
    await tester.pumpWidget(wrap(unverifiedService()));
    await tester.pump();

    // The button sits below the fold in the 800x600 test viewport, so bring
    // it on-screen before tapping (otherwise the tap misses and nothing runs).
    await tester.ensureVisible(find.textContaining("I'VE VERIFIED"));
    await tester.pump();
    await tester.tap(find.textContaining("I'VE VERIFIED"));
    await tester.pump(); // run reload + checks
    await tester.pump(); // render the overlay notification

    expect(find.textContaining('Not verified yet'), findsOneWidget);

    // Let the notification's auto-dismiss timer fire before the test ends.
    await tester.pump(const Duration(seconds: 4));
  });
}
