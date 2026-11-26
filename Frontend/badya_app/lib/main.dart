import 'package:Badya/email_verification_page.dart';
import 'package:Badya/onboarding_page.dart';
import 'package:Badya/login_page.dart';
import 'package:Badya/main_shell_page.dart';
import 'package:Badya/utils/app_theme.dart';
import 'package:Badya/utils/theme_service.dart';
import 'package:Badya/services/auth_service.dart';
import 'package:Badya/services/cache_service.dart';
import 'package:Badya/services/content_service.dart';
import 'package:Badya/services/fork_tracking_provider.dart';
import 'package:Badya/services/language_manager.dart';
import 'package:Badya/services/coin_service.dart';
import 'package:Badya/services/iap_service.dart';
import 'package:Badya/config/local_mode.dart';
import 'package:Badya/firebase_options.dart';
import 'package:Badya/services/app_initializer.dart';
import 'package:Badya/services/notification_service.dart';
import 'package:Badya/utils/logger.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!LocalMode.enabled) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

    // App Check: the Firebase project enforces App Check on its backends, so a
    // provider must be installed. Without one, Firebase requests carry a
    // placeholder token and are rejected (logcat: "Error getting App Check
    // token; ... No AppCheckProvider installed"), which breaks login/signup.
    // Debug builds use the debug provider (register the debug token printed to
    // the console under App Check → Apps → Manage debug tokens in the Firebase
    // console); release builds use Play Integrity (Android) / App Attest
    // (Apple). Web is skipped — it needs a reCAPTCHA site key from the console.
    if (!kIsWeb) {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: kDebugMode
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
        providerApple: kDebugMode
            ? const AppleDebugProvider()
            : const AppleAppAttestProvider(),
      );
    }
  } else {
    // LOCAL_MODE: Initialize Firebase with placeholder config so that any
    // transitive FirebaseAuth/Firestore references don't throw [core/no-app].
    // No real Firebase project is needed — calls will simply return empty data.
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }

  await ThemeService.loadTheme();

  // Register a shared CacheService with ContentService so the
  // `metadata/tag_counts` and recommendations caches are usable from every
  // `ContentService()` call site. AppInitializer also registers the same
  // cache (idempotent) — registering here as well ensures the cache is
  // available even before a user signs in (login page uses ContentService).
  try {
    final prefs = await SharedPreferences.getInstance();
    ContentService.registerSharedCacheService(CacheService(prefs));
  } catch (e) {
    Logger.warn('Failed to register shared CacheService in main(): $e');
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => LanguageManager()),
        ChangeNotifierProvider(create: (_) => ForkTrackingProvider()),
        Provider<CoinService>(create: (_) => CoinService()),
        Provider<IAPService>(create: (_) => IAPService()),
      ],
      child: const MyApp(),
    ),
  );

}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.themeMode,
      builder: (context, themeMode, _) {
        return MaterialApp(
          navigatorKey: NotificationService.navigatorKey,
          title: 'Badya',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          home: LocalMode.enabled ? const MainShellPage() : const AuthWrapper(),
        );
      },
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  /// Whether the user's profile (incl. emailVerified) has been refreshed from
  /// the server at least once. On cold start the cached token claims can be
  /// stale — e.g. the user verified their email in a browser earlier, but the
  /// app still sees the old unverified state until a reload happens.
  bool _authRefreshed = false;
  String? _activeUid;
  Future<bool>? _onboardingFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = context.watch<AuthService>().currentUser;
    if (user?.uid != _activeUid) {
      _activeUid = user?.uid;
      if (user != null) {
        _authRefreshed = false;
        _onboardingFuture = _initializeAndCheckOnboarding(user.uid);
        _refreshUser();
      } else {
        _authRefreshed = true;
        _onboardingFuture = null;
      }
    }
  }

  Future<void> _refreshUser() async {
    final authService = context.read<AuthService>();
    if (authService.currentUser != null) {
      try {
        await authService.reloadUser();
      } catch (_) {
        // Non-fatal: fall back to the cached verification status.
      }
    }
    if (mounted) setState(() => _authRefreshed = true);
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final user = authService.currentUser;

    if (user == null) {
      return const LoginPage();
    }

    if (!_authRefreshed) {
      return const _AuthLoadingScaffold();
    }

    // Gate: only accounts without a verified federated provider must verify
    // their email before using the app. Google/Apple accounts are verified by
    // their provider, and their `emailVerified` flag can be stale/false right
    // after OAuth sign-in — never block them (they'd get stuck on the
    // verification screen). Unverified email/password users see the
    // verification screen with resend + continue.
    if (AuthService.requiresEmailVerification(user)) {
      return const EmailVerificationPage();
    }

    return FutureBuilder<bool>(
      future: _onboardingFuture ??= _initializeAndCheckOnboarding(user.uid),
      builder: (context, onboardSnapshot) {
        if (onboardSnapshot.connectionState == ConnectionState.waiting) {
          return const _AuthLoadingScaffold();
        }
        if (onboardSnapshot.data == true) {
          return const MainShellPage();
        }
        return const OnboardingPage();
      },
    );
  }

  Future<bool> _initializeAndCheckOnboarding(String uid) async {
    await AppInitializer.initializeServices(uid);
    return await AppInitializer.checkOnboardingStatus(uid);
  }
}

class _AuthLoadingScaffold extends StatelessWidget {
  const _AuthLoadingScaffold();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF1A1A1A) : const Color(0xFFFDF4DD),
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}
