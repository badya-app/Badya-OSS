import 'package:Badya/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Constructible [AuthProvider] for the email/password provider id — the real
/// [EmailAuthProvider] is abstract, so tests use this minimal subclass.
class _PasswordAuthProvider extends AuthProvider {
  _PasswordAuthProvider() : super('password');
}

void main() {
  // Required by GoogleSignIn/ServicesBinding platform-channel calls that
  // signOut() triggers even when the user is signed out.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthService.requiresEmailVerification', () {
    // Build a MockUser whose providerData reflects a specific sign-in provider
    // (e.g. google.com / password) by linking the corresponding provider — the
    // mock then populates the user's providerData automatically.
    Future<MockUser> userWithProvider(
      String uid,
      String email, {
      bool verified = false,
      required AuthProvider provider,
    }) async {
      final user = MockUser(
        uid: uid,
        email: email,
        isEmailVerified: verified,
      );
      await user.linkWithProvider(provider);
      return user;
    }

    test('returns false when signed out', () {
      expect(AuthService.requiresEmailVerification(null), isFalse);
    });

    test('gates an unverified email/password account', () async {
      final user = await userWithProvider(
        'u1',
        'learner@badya.app',
        provider: _PasswordAuthProvider(),
      );
      expect(AuthService.requiresEmailVerification(user), isTrue);
    });

    test('does not gate a verified account', () async {
      final user = await userWithProvider(
        'u2',
        'verified@badya.app',
        verified: true,
        provider: _PasswordAuthProvider(),
      );
      expect(AuthService.requiresEmailVerification(user), isFalse);
    });

    test('never gates a Google account even when emailVerified is stale/false',
        () async {
      // Regression test: after Google OAuth sign-in the emailVerified flag can
      // briefly be false. The gate must NOT block these users, otherwise they
      // get stuck on the verification screen / login page.
      final googleUser = await userWithProvider(
        'u3',
        'google@user.com',
        provider: GoogleAuthProvider(),
      );
      expect(AuthService.requiresEmailVerification(googleUser), isFalse);
    });

    test('does not gate an Apple account even when unverified', () async {
      final appleUser = await userWithProvider(
        'u4',
        'apple@user.com',
        provider: AppleAuthProvider(),
      );
      expect(AuthService.requiresEmailVerification(appleUser), isFalse);
    });

    test('gates an account with no providers and an unverified email', () {
      final user = MockUser(
        uid: 'u5',
        email: 'nobody@user.com',
        isEmailVerified: false,
      );
      expect(AuthService.requiresEmailVerification(user), isTrue);
    });
  });

  group('AuthService email verification', () {
    test('signUpWithEmail creates an account and completes verification flow',
        () async {
      // verifyEmailAutomatically: false -> the created user is NOT verified,
      // which is exactly the state after a real email/password signup.
      final auth = MockFirebaseAuth(verifyEmailAutomatically: false);
      final service = AuthService(auth: auth);

      final cred = await service.signUpWithEmail('new@user.com', 'password123');

      expect(cred, isNotNull);
      expect(cred?.user, isNotNull);
      expect(auth.currentUser, isNotNull);
      expect(auth.currentUser!.email, 'new@user.com');
      // The verification email send runs inside signUpWithEmail (the mock's
      // sendEmailVerification is a no-op); the account stays unverified until
      // the user taps the link in the email.
      expect(auth.currentUser!.emailVerified, isFalse);
      expect(service.isEmailVerified, isFalse);
    });

    test('signUpWithEmail rethrows when account creation fails', () async {
      final auth = MockFirebaseAuth(verifyEmailAutomatically: false);
      whenCalling(
        Invocation.method(
          #createUserWithEmailAndPassword,
          const [],
          {#email: 'new@user.com', #password: 'password123'},
        ),
      ).on(auth).thenThrow(
        FirebaseAuthException(
          code: 'email-already-in-use',
          message: 'An account already exists.',
        ),
      );
      final service = AuthService(auth: auth);

      await expectLater(
        service.signUpWithEmail('new@user.com', 'password123'),
        throwsA(isA<FirebaseAuthException>()),
      );
    });

    test('sendVerificationEmail rethrows when the underlying call fails',
        () async {
      // NOTE: MockUser has value equality, and the mock_exceptions registry
      // is global across tests — a unique uid/email keeps this registration
      // from leaking into other tests.
      final mockUser = MockUser(
        uid: 'u-rethrow-only',
        email: 'rethrow-only@user.com',
        isEmailVerified: false,
      );
      final auth = MockFirebaseAuth(signedIn: true, mockUser: mockUser);
      whenCalling(Invocation.method(#sendEmailVerification, const []))
          .on(mockUser)
          .thenThrow(Exception('send failed'));
      final service = AuthService(auth: auth);

      await expectLater(
        service.sendVerificationEmail(),
        throwsA(isA<Exception>()),
      );
    });

    test('isEmailVerified reflects the signed-in user', () async {
      final verifiedAuth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
          uid: 'u1',
          email: 'verified@user.com',
          isEmailVerified: true,
        ),
      );
      expect(AuthService(auth: verifiedAuth).isEmailVerified, isTrue);

      final unverifiedAuth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
          uid: 'u2',
          email: 'unverified@user.com',
          isEmailVerified: false,
        ),
      );
      expect(AuthService(auth: unverifiedAuth).isEmailVerified, isFalse);
    });

    test('isEmailVerified is false when signed out', () async {
      final auth = MockFirebaseAuth();
      expect(AuthService(auth: auth).isEmailVerified, isFalse);
    });

    test('sendVerificationEmail completes for a signed-in user', () async {
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
          uid: 'u1',
          email: 'a@user.com',
          isEmailVerified: false,
        ),
      );
      final service = AuthService(auth: auth);

      await expectLater(service.sendVerificationEmail(), completes);
    });

    test('reloadUser refreshes the user and notifies listeners', () async {
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
          uid: 'u1',
          email: 'a@user.com',
          isEmailVerified: false,
        ),
      );
      final service = AuthService(auth: auth);
      var notifications = 0;
      service.addListener(() => notifications++);

      await service.reloadUser();

      expect(notifications, greaterThanOrEqualTo(1));
    });

    test('reloadUser is a no-op when signed out', () async {
      final service = AuthService(auth: MockFirebaseAuth());
      await expectLater(service.reloadUser(), completes);
    });

    test('signInWithEmail signs in the user and notifies listeners', () async {
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'u1', email: 'a@user.com'),
      );
      final service = AuthService(auth: auth);
      var notifications = 0;
      service.addListener(() => notifications++);

      final cred = await service.signInWithEmail('a@user.com', 'password123');

      expect(cred, isNotNull);
      expect(cred?.user?.uid, 'u1');
      expect(notifications, greaterThanOrEqualTo(1));
    });
  });

  group('AuthService account deletion', () {
    test('deleteAccount reauthenticates, calls remote, clears cache, signs out',
        () async {
      SharedPreferences.setMockInitialValues({});

      final auth = MockFirebaseAuth(verifyEmailAutomatically: false);
      final service = AuthService(auth: auth);
      var remoteCalled = false;
      service.deleteAccountRemoteOverride = () async {
        remoteCalled = true;
      };

      await service.signUpWithEmail('delete1@user.com', 'password123');

      // Seed local cache using the ACTUAL (mock-generated) uid.
      final uid = auth.currentUser!.uid;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('${uid}_native_language', 'Arabic');
      await prefs.setBool('is_onboarded_$uid', true);
      await prefs.setString('cache_abc123', '{"x":1}');
      await prefs.setStringList('cache_keys', ['abc123']);

      await service.deleteAccount(password: 'password123');

      expect(remoteCalled, isTrue);
      // Auth user signed out after deletion.
      expect(auth.currentUser, isNull);

      // uid-scoped + cache prefs wiped.
      expect(prefs.get('${uid}_native_language'), isNull);
      expect(prefs.get('is_onboarded_$uid'), isNull);
      expect(prefs.get('cache_abc123'), isNull);
      expect(prefs.getStringList('cache_keys'), isNull);
    });

    test('deleteAccount is a no-op when signed out', () async {
      final auth = MockFirebaseAuth();
      final service = AuthService(auth: auth);
      var remoteCalled = false;
      service.deleteAccountRemoteOverride = () async {
        remoteCalled = true;
      };

      await expectLater(service.deleteAccount(password: 'x'), completes);
      expect(remoteCalled, isFalse);
    });

    test('deleteAccount requires password for email/password accounts',
        () async {
      final auth = MockFirebaseAuth(verifyEmailAutomatically: false);
      final service = AuthService(auth: auth);
      service.deleteAccountRemoteOverride = () async {};

      await service.signUpWithEmail('delete2@user.com', 'password123');

      await expectLater(
        service.deleteAccount(),
        throwsA(
          isA<FirebaseAuthException>().having(
            (e) => e.code,
            'code',
            'missing-password',
          ),
        ),
      );
    });

    test('deleteAccount rethrows reauthentication failures', () async {
      final auth = MockFirebaseAuth(verifyEmailAutomatically: false);
      final service = AuthService(auth: auth);
      service.deleteAccountRemoteOverride = () async {};

      await service.signUpWithEmail('delete3@user.com', 'password123');

      // Force reauthentication to fail (e.g. wrong password).
      final mockUser = auth.currentUser as MockUser;
      whenCalling(
        Invocation.method(
          #reauthenticateWithCredential,
          const [],
        ),
      ).on(mockUser).thenThrow(
        FirebaseAuthException(
          code: 'invalid-credential',
          message: 'The supplied auth credential is incorrect.',
        ),
      );

      await expectLater(
        service.deleteAccount(password: 'wrong-password'),
        throwsA(
          isA<FirebaseAuthException>().having(
            (e) => e.code,
            'code',
            'invalid-credential',
          ),
        ),
      );
      // Remote deletion must NOT run when reauth fails.
      expect(auth.currentUser, isNotNull);
    });
  });

  group('AuthService signOut', () {
    test('signOut clears uid-scoped and cache SharedPreferences keys',
        () async {
      SharedPreferences.setMockInitialValues({});

      final auth = MockFirebaseAuth(verifyEmailAutomatically: false);
      final service = AuthService(auth: auth);

      await service.signUpWithEmail('signout@user.com', 'password123');

      final uid = auth.currentUser!.uid;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('${uid}_native_language', 'Arabic');
      await prefs.setBool('is_onboarded_$uid', true);
      await prefs.setString('cache_abc123', '{"x":1}');
      await prefs.setStringList('cache_keys', ['abc123']);
      // A global (non-user) preference must survive logout.
      await prefs.setString('theme_mode', 'dark');

      await service.signOut();

      expect(auth.currentUser, isNull);
      expect(prefs.get('${uid}_native_language'), isNull);
      expect(prefs.get('is_onboarded_$uid'), isNull);
      expect(prefs.get('cache_abc123'), isNull);
      expect(prefs.getStringList('cache_keys'), isNull);
      // Non-user-global preference stays intact.
      expect(prefs.getString('theme_mode'), 'dark');
    });

    test('signOut completes without error when signed out', () async {
      SharedPreferences.setMockInitialValues({});
      final service = AuthService(auth: MockFirebaseAuth());
      await expectLater(service.signOut(), completes);
    });
  });

  group('AuthService data export', () {
    const expectedResult = DataExportResult(
      downloadUrl: 'https://example.com/badya-export.json?token=abc',
      filename: 'badya-export-20260812-141530.json',
      sizeBytes: 2048,
      exportedAt: '2026-08-12T14:15:30.000Z',
    );

    test('exportData calls the remote and returns the parsed result',
        () async {
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'u1', email: 'export@user.com'),
      );
      final service = AuthService(auth: auth);
      var remoteCalled = false;
      service.exportDataRemoteOverride = () async {
        remoteCalled = true;
        return expectedResult;
      };

      final result = await service.exportData();

      expect(remoteCalled, isTrue);
      expect(result, same(expectedResult));
    });

    test('exportData is a no-op returning null when signed out', () async {
      final auth = MockFirebaseAuth();
      final service = AuthService(auth: auth);
      var remoteCalled = false;
      service.exportDataRemoteOverride = () async {
        remoteCalled = true;
        return expectedResult;
      };

      final result = await service.exportData();

      expect(result, isNull);
      expect(remoteCalled, isFalse);
    });

    test('exportData rethrows remote failures', () async {
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'u2', email: 'export2@user.com'),
      );
      final service = AuthService(auth: auth);
      service.exportDataRemoteOverride = () async {
        throw Exception('export failed');
      };

      await expectLater(
        service.exportData(),
        throwsA(isA<Exception>()),
      );
    });

    test('DataExportResult parses the callable payload', () {
      final result = DataExportResult.fromJson(const {
        'downloadUrl': 'https://example.com/badya-export.json?token=abc',
        'filename': 'badya-export-20260812-141530.json',
        'sizeBytes': 2048,
        'exportedAt': '2026-08-12T14:15:30.000Z',
      });

      expect(result.downloadUrl, 'https://example.com/badya-export.json?token=abc');
      expect(result.filename, 'badya-export-20260812-141530.json');
      expect(result.sizeBytes, 2048);
      expect(result.exportedAt, '2026-08-12T14:15:30.000Z');
    });
  });
}
