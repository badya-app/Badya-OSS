import 'package:Badya/config/api_config.dart';
import 'package:Badya/config/local_mode.dart';
import 'package:Badya/utils/logger.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// Result of a successful GDPR data export request.
///
/// The [downloadUrl] is a short-lived (15 min) signed URL that downloads the
/// JSON export file.
class DataExportResult {
  final String downloadUrl;
  final String filename;
  final int sizeBytes;
  final String exportedAt;

  const DataExportResult({
    required this.downloadUrl,
    required this.filename,
    required this.sizeBytes,
    required this.exportedAt,
  });

  factory DataExportResult.fromJson(Map<String, dynamic> json) {
    return DataExportResult(
      downloadUrl: json['downloadUrl'] as String,
      filename: json['filename'] as String,
      sizeBytes: (json['sizeBytes'] as num).toInt(),
      exportedAt: json['exportedAt'] as String,
    );
  }
}

class AuthService extends ChangeNotifier {
  final FirebaseAuth? _auth;
  // Configure GoogleSignIn with web client ID for proper OAuth flow
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId: ApiConfig.googleClientId,
  );

  /// Injected remote call for [deleteAccount] — overridable in tests so the
  /// real Cloud Function isn't invoked.
  @visibleForTesting
  Future<void> Function()? deleteAccountRemoteOverride;

  /// Injected remote call for [exportData] — overridable in tests so the
  /// real Cloud Function isn't invoked.
  @visibleForTesting
  Future<DataExportResult> Function()? exportDataRemoteOverride;

  AuthService({FirebaseAuth? auth})
    : _auth = LocalMode.enabled ? auth : (auth ?? FirebaseAuth.instance) {
    _auth?.authStateChanges().listen((User? user) {
      notifyListeners();
    });
  }

  User? get currentUser => _auth?.currentUser;

  String? get currentUid =>
      LocalMode.enabled ? LocalMode.guestUid : _auth?.currentUser?.uid;

  Stream<User?> get authStateChanges =>
      _auth?.authStateChanges() ?? const Stream.empty();

  // Email & Password Sign Up
  Future<UserCredential?> signUpWithEmail(String email, String password) async {
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Send a verification email so users can't use the app with
      // fake/disposable emails. A failure here is logged but does NOT block
      // account creation — the email verification screen offers a resend.
      try {
        await userCredential.user?.sendEmailVerification();
        Logger.info('Verification email sent to $email');
      } catch (e) {
        Logger.error('Failed to send verification email after signup', e);
      }

      // Explicitly notify listeners so watching widgets rebuild immediately
      // without relying solely on the broadcast authStateChanges stream.
      notifyListeners();
      return userCredential;
    } catch (e) {
      Logger.error('Email sign up failed', e);
      rethrow;
    }
  }

  // Email & Password Sign In
  Future<UserCredential?> signInWithEmail(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      // Explicitly notify listeners so watching widgets rebuild immediately
      // without relying solely on the broadcast authStateChanges stream.
      notifyListeners();
      return credential;
    } catch (e) {
      Logger.error('Email sign in failed', e);
      rethrow;
    }
  }

  // Google Sign In - Works for both sign in and sign up
  Future<UserCredential?> signInWithGoogle() async {
    try {
      Logger.info('Starting Google Sign-In flow...');

      GoogleSignInAccount? googleUser;
      try {
        googleUser = await _googleSignIn.signIn();
      } catch (e) {
        Logger.error('Error during Google Sign-In account selection', e);
        throw FirebaseAuthException(
          code: 'google-sign-in-failed',
          message: 'Failed to start Google Sign-In: ${e.toString()}',
        );
      }

      if (googleUser == null) {
        Logger.info('Google Sign-In cancelled by user');
        return null;
      }

      Logger.info('Google account selected: ${googleUser.email}');

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      Logger.info(
        'Google authentication obtained. ID Token: ${googleAuth.idToken != null ? "present" : "missing"}',
      );

      if (googleAuth.idToken == null) {
        Logger.error('Missing ID token from Google Sign-In');
        throw FirebaseAuthException(
          code: 'missing-id-token',
          message: 'Google Sign-In failed: Missing ID token. Please try again.',
        );
      }

      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      Logger.info('Credential created, signing in to Firebase...');

      final UserCredential userCredential = await _auth.signInWithCredential(
        credential,
      );

      Logger.info(
        'Firebase sign-in successful. New user: ${userCredential.additionalUserInfo?.isNewUser}',
      );

      if (userCredential.additionalUserInfo?.isNewUser == true) {
        Logger.info(
          'Updating display name for new user: ${googleUser.displayName}',
        );
        await userCredential.user?.updateDisplayName(googleUser.displayName);
        await userCredential.user?.reload();
      }

      Logger.info('Google Sign-In completed successfully');

      // Belt & suspenders: explicitly notify listeners after a successful
      // sign-in. `authStateChanges` normally fires on its own, but there are
      // documented flutterfire cases (signInWithCredential + google_sign_in)
      // where the stream event is missed/never emitted. Without this, MyApp
      // never rebuilds and the user stays stuck on the login page even though
      // Firebase signed them in.
      notifyListeners();

      return userCredential;
    } on FirebaseAuthException catch (e) {
      Logger.error(
        'Firebase Auth Error during Google Sign-In: ${e.code} - ${e.message}',
      );

      throw FirebaseAuthException(
        code: e.code,
        message: e.message ?? 'Google Sign-In failed. Please try again.',
        email: e.email,
        credential: e.credential,
      );
    } catch (e, stackTrace) {
      Logger.error('Unexpected error during Google Sign-In', e, stackTrace);

      final errorString = e.toString().toLowerCase();
      if (errorString.contains('sign_in_canceled') ||
          errorString.contains('canceled') ||
          errorString.contains('cancelled')) {
        return null;
      }

      throw FirebaseAuthException(
        code: 'google-sign-in-failed',
        message: 'Google Sign-In failed: ${e.toString()}',
      );
    }
  }

  // Sign Out
  Future<void> signOut() async {
    if (LocalMode.enabled) return;
    final uid = _auth?.currentUser?.uid;
    // Google first, best-effort: if Google sign-out fails (e.g. plugin or
    // network issue) the Firebase session must STILL be terminated — otherwise
    // the user would stay signed in (review issue: partial sign-out failure).
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      Logger.error('Error during Google sign out', e);
    }
    try {
      await _auth.signOut();
      Logger.info('User signed out');
    } catch (e) {
      Logger.error('Error during Firebase sign out', e);
    }
    // Local cache cleanup (review issue #7): clear uid-scoped
    // SharedPreferences entries + content cache keys so no personal data
    // survives on the device after logout.
    if (uid != null) {
      await _clearLocalCache(uid);
    }
    // Belt & suspenders: explicitly notify listeners after sign-out.
    // authStateChanges can miss/defer the event (documented FlutterFire
    // edge-case). Without this, MyApp may not rebuild and the user stays
    // stuck on the current page instead of returning to the login screen.
    notifyListeners();
  }

  // Reset Password
  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      Logger.info('Password reset email sent to $email');
    } catch (e) {
      Logger.error('Password reset failed', e);
      rethrow;
    }
  }

  // Change Password
  Future<void> changePassword(String newPassword) async {
    try {
      await _auth.currentUser?.updatePassword(newPassword);
      Logger.info('Password updated successfully');
    } catch (e) {
      Logger.error('Password change failed', e);
      rethrow;
    }
  }

  // ---- Email Verification ----

  /// Whether [user] must verify their email before using the app.
  ///
  /// Only accounts without a verified federated provider are gated.
  /// Google/Apple accounts are verified by their provider, and their
  /// `emailVerified` flag can be stale/false right after OAuth sign-in
  /// (flutterfire #8777/#10159), so they are never blocked by this gate.
  static bool requiresEmailVerification(User? user) {
    if (user == null) return false;
    final isFederated = user.providerData.any(
      (p) => p.providerId == 'google.com' || p.providerId == 'apple.com',
    );
    return !user.emailVerified && !isFederated;
  }

  /// Whether the currently signed-in user has verified their email address.
  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  /// Re-sends the verification email to the current user
  /// (used by the email verification screen's resend button).
  Future<void> sendVerificationEmail() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await user.sendEmailVerification();
      Logger.info('Verification email sent to ${user.email}');
    } catch (e) {
      Logger.error('Failed to send verification email', e);
      rethrow;
    }
  }

  /// Refreshes the current user's profile from the server so a fresh
  /// [emailVerified] status is picked up (e.g. after the user taps the
  /// verification link in their inbox), then notifies listeners so
  /// AuthWrapper can re-evaluate routing.
  Future<void> reloadUser() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await user.reload();
      Logger.info('User reloaded. emailVerified: ${user.emailVerified}');
    } catch (e) {
      Logger.error('Failed to reload user', e);
      rethrow;
    }
    notifyListeners();
  }

  // ---- Account Deletion (GDPR Article 17 / CCPA) ----

  /// Permanently deletes the current user's account and ALL associated data.
  ///
  /// Security model:
  ///  1. Reauthenticates the user (fresh credentials) — required before any
  ///     destructive Firebase Auth operation.
  ///  2. Calls the `deleteUserAccount` Cloud Function which uses the Admin SDK
  ///     to wipe every server-side trace of the user: the `users/{uid}`
  ///     document + all subcollections, owned `user_content` (+ subcollections),
  ///     `usernames` entries, `fork_events`/`recommendation_clicks` analytics,
  ///     recommendation docs, uploaded Storage files, and finally the Firebase
  ///     Auth user itself.
  ///  3. Clears local caches (SharedPreferences) so no personal data remains
  ///     on the device.
  ///  4. Signs out locally — the AuthWrapper in main.dart routes back to the
  ///     login page via the auth state stream.
  ///
  /// [password] is required for email/password accounts (used to reauthenticate).
  /// Google-only accounts are reauthenticated via a fresh Google sign-in.
  Future<void> deleteAccount({String? password}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // 1. Reauthenticate
    final hasEmailProvider = user.providerData.any(
      (p) => p.providerId == 'password',
    );
    if (hasEmailProvider) {
      final email = user.email;
      if (email == null) {
        throw FirebaseAuthException(
          code: 'invalid-email',
          message: 'No email on account — cannot reauthenticate.',
        );
      }
      if (password == null || password.isEmpty) {
        throw FirebaseAuthException(
          code: 'missing-password',
          message: 'Your password is required to delete your account.',
        );
      }
      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);
    } else {
      // Google-only account: force a fresh Google sign-in to reauthenticate.
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw FirebaseAuthException(
          code: 'cancelled-popup-request',
          message: 'Google re-authentication was cancelled.',
        );
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await user.reauthenticateWithCredential(credential);
    }

    // 2. Server-side deletion (Firestore + Storage + Auth user)
    await _callDeleteAccountRemote();

    // 3. Clear local cache
    await _clearLocalCache(user.uid);

    // 4. Sign out locally (Google first so its session is also cleared).
    //    Best-effort: the auth user no longer exists server-side.
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      Logger.warn('Google sign-out during account deletion failed: $e');
    }
    await _auth.signOut();
    // Belt & suspenders: explicitly notify listeners after sign-out.
    // authStateChanges can miss/defer the event after the server-side user
    // has already been deleted (same documented edge-case guarded in
    // signInWithGoogle). Without this, MyApp never rebuilds and the user
    // stays stuck on the account page.
    notifyListeners();
  }

  Future<void> _callDeleteAccountRemote() async {
    final override = deleteAccountRemoteOverride;
    if (override != null) {
      await override();
      return;
    }
    final callable = FirebaseFunctions.instance.httpsCallable(
      'deleteUserAccount',
    );
    await callable();
  }

  // ---- Data Export (GDPR Article 20 — Right to Portability) ----

  /// Exports the current user's data via the `exportUserData` Cloud Function.
  ///
  /// The function walks every server-side trace of the user (profile,
  /// progress, languages, scores, coins, imports, content, transactions,
  /// recommendation data, storage references) into a JSON file, uploads it to
  /// Cloud Storage, and returns a short-lived signed download URL.
  ///
  /// Returns null when the user is signed out (nothing to export).
  Future<DataExportResult?> exportData() async {
    if (_auth.currentUser == null) return null;

    final override = exportDataRemoteOverride;
    if (override != null) return override();

    final callable = FirebaseFunctions.instance.httpsCallable('exportUserData');
    final result = await callable();
    final data = Map<String, dynamic>.from(result.data as Map);
    return DataExportResult.fromJson(data);
  }

  /// Removes all SharedPreferences entries that belong to this user so no
  /// personal data survives on-device after account deletion OR logout.
  ///
  /// Handles both key styles used across the app:
  ///  - uid-scoped keys: "{uid}_native_language", "is_onboarded_{uid}", ...
  ///  - content cache keys: "cache_{contentId}" / "cache_expiry_{contentId}"
  ///    (cache keys are not uid-scoped, but they hold user-generated content).
  Future<void> _clearLocalCache(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().toList();
      for (final key in keys) {
        if (key.contains(uid) ||
            key.startsWith('cache_') ||
            key == 'cache_keys' ||
            // Not uid-scoped — must be explicitly cleared so a subsequent
            // user on the same device doesn't trigger a spurious starter bonus.
            key == 'pending_starter_celebration') {
          await prefs.remove(key);
        }
      }
      Logger.info('Cleared local cache for deleted user');
    } catch (e) {
      Logger.error('Failed to clear local cache during account deletion', e);
    }
  }
}
