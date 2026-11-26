import 'dart:async';
import 'dart:ui';

import 'package:Badya/services/auth_service.dart';
import 'package:Badya/utils/ui_utils.dart';
import 'package:Badya/widgets/custom_button.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shown to email/password accounts that haven't verified their email yet.
///
/// AuthWrapper (lib/main.dart) routes unverified users here after signup or
/// login, so nobody can use the app with a fake/disposable email. The user
/// taps the link in their inbox, comes back, and presses "I've Verified".
class EmailVerificationPage extends StatefulWidget {
  const EmailVerificationPage({super.key});

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  static const int _resendCooldownSeconds = 60;

  Timer? _cooldownTimer;
  int _cooldownRemaining = 0;
  bool _isChecking = false;
  bool _isResending = false;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  /// Anti-abuse cooldown: the resend button is disabled for 60s after each
  /// successful resend so users can't spam verification emails.
  void _startResendCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldownRemaining = _resendCooldownSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _cooldownRemaining--;
        if (_cooldownRemaining <= 0) timer.cancel();
      });
    });
  }

  /// Returns the web inbox URL for the user's email provider,
  /// or `null` if the domain isn't recognised.
  Uri? _inboxUriForEmail(String email) {
    final domain = email.split('@').last.toLowerCase();

    const inboxUrls = <String, String>{
      'gmail.com': 'https://mail.google.com',
      'googlemail.com': 'https://mail.google.com',
      'outlook.com': 'https://outlook.live.com/mail/0/',
      'hotmail.com': 'https://outlook.live.com/mail/0/',
      'live.com': 'https://outlook.live.com/mail/0/',
      'msn.com': 'https://outlook.live.com/mail/0/',
      'yahoo.com': 'https://mail.yahoo.com',
      'icloud.com': 'https://www.icloud.com/mail/',
      'me.com': 'https://www.icloud.com/mail/',
      'mac.com': 'https://www.icloud.com/mail/',
      'aol.com': 'https://mail.aol.com',
    };

    // Handle regional Yahoo domains (e.g. yahoo.co.uk, yahoo.co.jp).
    if (domain.startsWith('yahoo.')) {
      return Uri.parse('https://mail.yahoo.com');
    }

    final url = inboxUrls[domain];
    return url != null ? Uri.parse(url) : null;
  }

  /// Opens the user's email inbox — web inbox for known providers,
  /// generic mailto: for unknown ones.
  Future<void> _openEmailApp() async {
    try {
      final email = context.read<AuthService>().currentUser?.email ?? '';
      final inboxUri = _inboxUriForEmail(email);
      final uri = inboxUri ?? Uri(scheme: 'mailto');
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        UiUtils.showErrorSnackbar(context, 'Could not open your email inbox.');
      }
    } catch (e) {
      if (mounted) {
        UiUtils.showErrorSnackbar(
          context,
          'Could not open your email inbox.',
          error: e.toString(),
        );
      }
    }
  }

  Future<void> _resendEmail() async {
    if (_isResending || _cooldownRemaining > 0) return;
    setState(() => _isResending = true);
    try {
      await context.read<AuthService>().sendVerificationEmail();
      if (!mounted) return;
      UiUtils.showSuccessSnackbar(
        context,
        'Verification email sent! Check your inbox.',
      );
      _startResendCooldown();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        UiUtils.showErrorSnackbar(context, _messageFor(e), error: e.toString());
      }
    } catch (e) {
      if (mounted) {
        UiUtils.showErrorSnackbar(
          context,
          'Could not resend the email. Please try again.',
          error: e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  Future<void> _checkVerification() async {
    if (_isChecking) return;
    setState(() => _isChecking = true);
    try {
      final authService = context.read<AuthService>();
      // Pull the freshest emailVerified status from the server.
      await authService.reloadUser();

      if (authService.isEmailVerified) {
        // AuthWrapper is watching AuthService and rebuilds into the
        // onboarding / main shell automatically.
        if (mounted) {
          UiUtils.showSuccessSnackbar(
            context,
            'Email verified! Welcome to Badya 🎉',
          );
        }
      } else if (mounted) {
        UiUtils.showTopNotification(
          context,
          'Not verified yet — tap the link in your email, then try again.',
          type: NotificationType.info,
        );
      }
    } catch (e) {
      if (mounted) {
        UiUtils.showErrorSnackbar(
          context,
          'Could not check your verification status. '
          'Please check your connection and try again.',
          error: e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _signOut() async {
    await context.read<AuthService>().signOut();
    // MyApp/AuthWrapper routes back to the login page automatically.
  }

  String _messageFor(FirebaseAuthException e) {
    switch (e.code) {
      case 'too-many-requests':
        return 'Too many emails sent. Please wait a minute and try again.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      default:
        return 'Could not resend the email. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgImage = isDark
        ? 'assets/images/logindark.svg'
        : 'assets/images/login_background.svg';
    final user = context.select<AuthService, User?>((s) => s.currentUser);
    final email = user?.email ?? '';

    return Scaffold(
      body: Stack(
        children: [
          SizedBox.expand(
            child: SvgPicture.asset(
              bgImage,
              fit: BoxFit.cover,
            ).animate().fadeIn(duration: 800.ms),
          ),
          Container(
            color: (isDark ? Colors.black : Colors.white).withValues(alpha: 0.15),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 16.0,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 32,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Spacer(),
                          _buildCard(isDark, email),
                          const Spacer(),
                          const SizedBox(height: 24),
                          _buildSignOutButton(isDark),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(bool isDark, String email) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.6),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
                blurRadius: 25,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFF78B1E), Color(0xFFFFB75E)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF78B1E).withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.mark_email_read_rounded,
                  color: Colors.white,
                  size: 44,
                ),
              ).animate().scale(delay: 100.ms, curve: Curves.easeOutBack),
              const SizedBox(height: 24),
              Text(
                'Verify your email',
                textAlign: TextAlign.center,
                style: GoogleFonts.merriweather(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : const Color(0xFF2D3436),
                ),
              ).animate().fadeIn(delay: 200.ms),
              const SizedBox(height: 16),
              Text(
                'We sent a verification link to',
                textAlign: TextAlign.center,
                style: GoogleFonts.nunito(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ).animate().fadeIn(delay: 300.ms),
              const SizedBox(height: 6),
              Text(
                email,
                textAlign: TextAlign.center,
                style: GoogleFonts.nunito(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFFF78B1E),
                ),
              ).animate().fadeIn(delay: 350.ms),
              const SizedBox(height: 12),
              Text(
                'Tap the link in the email to confirm your account. '
                'You won\u2019t be able to use Badya until it\u2019s verified.',
                textAlign: TextAlign.center,
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ).animate().fadeIn(delay: 400.ms),
              const SizedBox(height: 14),
              // Spam warning — Firebase verification emails often land in
              // Spam/Promotions; without this hint users get stuck and think
              // signup failed. Make it prominent and actionable.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF78B1E).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFF78B1E).withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.mark_email_unread_rounded,
                      size: 20,
                      color: const Color(0xFFF78B1E),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Didn\u2019t see it? Check your Spam or Promotions '
                        'folder \u2014 it sometimes lands there. If found, '
                        'mark it as \u201cNot Spam\u201d so future emails '
                        'arrive in your inbox.',
                        style: GoogleFonts.nunito(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          height: 1.45,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 450.ms),
              const SizedBox(height: 28),
              CustomButton(
                text: 'Open Inbox',
                backgroundColor: const Color(0xFFF78B1E),
                onPressed: _openEmailApp,
              ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.1),
              const SizedBox(height: 12),
              CustomButton(
                text: _cooldownRemaining > 0
                    ? 'Resend Email (${_cooldownRemaining}s)'
                    : 'Resend Email',
                backgroundColor: Colors.transparent,
                foregroundColor: isDark ? Colors.white : const Color(0xFF2D3436),
                borderColor: isDark ? Colors.white38 : Colors.black26,
                borderWidth: 1.5,
                isLoading: _isResending,
                onPressed: _cooldownRemaining > 0 ? () {} : _resendEmail,
              ).animate().fadeIn(delay: 550.ms).slideY(begin: 0.1),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Divider(
                      color: isDark ? Colors.white24 : Colors.black12,
                      thickness: 1,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'OR',
                      style: GoogleFonts.nunito(
                        color: isDark ? Colors.white38 : Colors.black38,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Divider(
                      color: isDark ? Colors.white24 : Colors.black12,
                      thickness: 1,
                    ),
                  ),
                ],
              ).animate().fadeIn(delay: 600.ms),
              const SizedBox(height: 24),
              CustomButton(
                text: "I've Verified",
                backgroundColor: const Color(0xFF2ECC71),
                isLoading: _isChecking,
                onPressed: _checkVerification,
              ).animate().fadeIn(delay: 650.ms).slideY(begin: 0.1),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSignOutButton(bool isDark) {
    return TextButton(
      onPressed: _signOut,
      child: Text(
        'Log out & use a different email',
        style: GoogleFonts.nunito(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white54 : Colors.black45,
        ),
      ),
    ).animate().fadeIn(delay: 700.ms);
  }
}
