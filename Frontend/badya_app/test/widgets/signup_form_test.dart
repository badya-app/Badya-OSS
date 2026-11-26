import 'package:Badya/services/auth_service.dart';
import 'package:Badya/widgets/custom_button.dart';
import 'package:Badya/widgets/signup_form.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  Widget wrap() {
    return ChangeNotifierProvider<AuthService>(
      create: (_) => AuthService(auth: MockFirebaseAuth()),
      child: const MaterialApp(home: Scaffold(body: SignUpForm())),
    );
  }

  Future<void> pumpForm(WidgetTester tester) async {
    await tester.pumpWidget(wrap());
    // Flush the signup form's entrance animations (delays up to 1100ms).
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('renders the ToS acceptance row with links', (tester) async {
    await pumpForm(tester);

    expect(find.textContaining('I agree to the'), findsOneWidget);
    expect(find.text('Terms of Service'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
  });

  testWidgets('SIGN UP is disabled until the terms are accepted',
      (tester) async {
    await pumpForm(tester);

    CustomButton signUpButton() =>
        tester.widget<CustomButton>(find.byType(CustomButton));

    // Disabled before accepting.
    expect(signUpButton().isEnabled, isFalse);

    // Tapping the checkbox enables the button.
    await tester.tap(find.byKey(const Key('accept_terms_checkbox')));
    await tester.pump();

    expect(signUpButton().isEnabled, isTrue);

    // Tapping the label toggles it back off.
    await tester.tap(find.textContaining('I agree to the'));
    await tester.pump();

    expect(signUpButton().isEnabled, isFalse);
  });

  testWidgets('tapping the Terms of Service link opens the legal page',
      (tester) async {
    await pumpForm(tester);

    await tester.tap(find.text('Terms of Service'));
    await tester.pump(); // start the route transition
    await tester.pump(const Duration(milliseconds: 400)); // finish it
    await tester.pump(const Duration(seconds: 2)); // flush animate timers

    expect(find.text('Acceptance of These Terms'), findsOneWidget);

    // Go back so the test ends on the form (ticker cleanup).
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('tapping the Privacy Policy link opens the legal page',
      (tester) async {
    await pumpForm(tester);

    await tester.tap(find.text('Privacy Policy'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Information We Collect'), findsOneWidget);

    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('shows live mismatch hint when passwords do not match',
      (tester) async {
    await pumpForm(tester);

    // No hint before typing.
    expect(find.text('Passwords do not match'), findsNothing);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'password123',
    );
    await tester.pump();

    // Only the password field is filled — no mismatch hint yet.
    expect(find.text('Passwords do not match'), findsNothing);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm Password'),
      'different456',
    );
    await tester.pump();

    expect(find.text('Passwords do not match'), findsOneWidget);

    // Fixing the confirm password removes the hint.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm Password'),
      'password123',
    );
    await tester.pump();

    expect(find.text('Passwords do not match'), findsNothing);
  });

  testWidgets('rejects signup with mismatched passwords', (tester) async {
    await pumpForm(tester);

    await tester.tap(find.byKey(const Key('accept_terms_checkbox')));
    await tester.pump();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Full Name'),
      'Test User',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email Address'),
      'test@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'password123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm Password'),
      'nope123456',
    );
    await tester.pump();

    await tester.tap(find.byType(CustomButton));
    await tester.pump();

    expect(find.text('Passwords do not match.'), findsOneWidget);
  });

  testWidgets('rejects signup with an invalid email format', (tester) async {
    await pumpForm(tester);

    await tester.tap(find.byKey(const Key('accept_terms_checkbox')));
    await tester.pump();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Full Name'),
      'Test User',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email Address'),
      'not-an-email',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'password123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm Password'),
      'password123',
    );
    await tester.pump();

    await tester.tap(find.byType(CustomButton));
    await tester.pump();

    expect(find.text('Please provide a valid email address.'), findsOneWidget);
  });

  testWidgets('rejects signup when required fields are empty',
      (tester) async {
    await pumpForm(tester);

    await tester.tap(find.byKey(const Key('accept_terms_checkbox')));
    await tester.pump();

    await tester.tap(find.byType(CustomButton));
    await tester.pump();

    expect(
      find.text('Please complete all required fields to create your account.'),
      findsOneWidget,
    );
  });

  testWidgets(
      'pops back to the root route after a successful signup so the '
      'verification page is shown', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthService>(
        create: (_) => AuthService(auth: MockFirebaseAuth()),
        child: const MaterialApp(home: Scaffold(body: Text('ROOT'))),
      ),
    );

    // Push SignUpPage on top of the root route, exactly like the app does
    // from the login page. Without the fix, a successful signup leaves the
    // user stuck on this page and they never see the email-verification UI
    // (AuthWrapper is the MaterialApp `home` route behind this push).
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: SignUpForm()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2)); // entrance animations

    expect(find.byType(SignUpForm), findsOneWidget);

    await tester.tap(find.byKey(const Key('accept_terms_checkbox')));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Full Name'),
      'Test User',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email Address'),
      'test@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'password123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm Password'),
      'password123',
    );
    await tester.pump();

    await tester.tap(find.byType(CustomButton));
    await tester.pump(); // start the async signup
    await tester.pump(const Duration(milliseconds: 300)); // let futures resolve
    await tester.pump(const Duration(milliseconds: 400)); // pop transition
    await tester.pump(const Duration(seconds: 2)); // flush entrance animations

    // The SignUpPage is popped and the root route is visible again — in the
    // real app this root is AuthWrapper, which routes the unverified user to
    // EmailVerificationPage.
    expect(find.byType(SignUpForm), findsNothing);
    expect(find.text('ROOT'), findsOneWidget);
    expect(
      find.text('Account created! Check your email to verify your account.'),
      findsOneWidget,
    );

    // Let the snackbar auto-dismiss so no timers are left pending.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 500));
  });
}
