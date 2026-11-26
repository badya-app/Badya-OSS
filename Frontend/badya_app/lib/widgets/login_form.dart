import 'dart:ui';
import 'package:Badya/forgot_password_page.dart';
import 'package:Badya/services/auth_service.dart';
import 'package:Badya/utils/ui_utils.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'custom_button.dart';
import 'custom_text_field.dart';

class LoginForm extends StatefulWidget {
  const LoginForm({super.key});

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || _passwordController.text.trim().isEmpty) {
      UiUtils.showErrorSnackbar(
        context,
        'Please provide both email and password to continue.',
      );
      return;
    }
    if (!UiUtils.isValidEmail(email)) {
      UiUtils.showErrorSnackbar(
        context,
        'Please provide a valid email address.',
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await context.read<AuthService>().signInWithEmail(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = 'No account associated with this email. Please sign up.';
          break;
        case 'wrong-password':
          message = 'The password you entered is incorrect. Please try again.';
          break;
        case 'invalid-email':
          message = 'Please enter a valid email address.';
          break;
        case 'user-disabled':
          message =
              'This account has been deactivated. Contact support for help.';
          break;
        case 'too-many-requests':
          message = 'Too many failed attempts. Please try again later.';
          break;
        default:
          message =
              'Login failed. Please check your credentials and try again.';
      }
      if (mounted) {
        UiUtils.showErrorSnackbar(context, message);
      }
    } catch (e) {
      if (mounted) {
        UiUtils.showErrorSnackbar(
          context,
          'An unexpected error occurred.',
          error: e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      final result = await context.read<AuthService>().signInWithGoogle();
      
      // User cancelled the sign-in
      if (result == null) {
        if (mounted) {
          UiUtils.showErrorSnackbar(
            context,
            'Google Sign-In was cancelled.',
          );
        }
        return;
      }
      
      if (mounted) {
        UiUtils.showSuccessSnackbar(
          context,
          'Signed in with Google successfully!',
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'account-exists-with-different-credential':
          message = 'An account already exists with a different sign-in method.';
          break;
        case 'invalid-credential':
          message = 'The credential received is invalid. Please try again.';
          break;
        case 'operation-not-allowed':
          message = 'Google Sign-In is not enabled. Please contact support.';
          break;
        case 'user-disabled':
          message = 'This account has been disabled. Contact support for help.';
          break;
        case 'user-not-found':
          message = 'No account found. Please try again.';
          break;
        case 'missing-id-token':
          message = 'Google Sign-In failed: Missing authentication token. Please try again.';
          break;
        case 'google-sign-in-failed':
          message = e.message ?? 'Google Sign-In failed. Please try again.';
          break;
        default:
          message = 'Google Sign-In failed: ${e.message ?? "Unknown error"}';
      }
      if (mounted) {
        UiUtils.showErrorSnackbar(context, message, error: e.toString());
      }
    } catch (e) {
      if (mounted) {
        UiUtils.showErrorSnackbar(
          context,
          'Google Sign-In failed. Please try again.',
          error: e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                  CustomTextField(
                    controller: _emailController,
                    labelText: 'Email Address',
                    hintText: 'your@email.com',
                    prefixIcon: Icons.alternate_email_rounded,
                    keyboardType: TextInputType.emailAddress,
                  ).animate().fadeIn(delay: 700.ms).slideX(begin: -0.1),
                  const SizedBox(height: 16),
                  CustomTextField(
                    controller: _passwordController,
                    labelText: 'Password',
                    hintText: '••••••••',
                    prefixIcon: Icons.lock_outline_rounded,
                    isPasswordField: true,
                  ).animate().fadeIn(delay: 800.ms).slideX(begin: -0.1),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ForgotPasswordPage(),
                          ),
                        );
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Forgot Password?',
                        style: GoogleFonts.nunito(
                          color: const Color(0xFFF78B1E),
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ).animate().fadeIn(delay: 900.ms),
                  const SizedBox(height: 24),
                  CustomButton(
                        text: 'LOG IN',
                        backgroundColor: const Color(0xFF2ECC71),
                        isLoading: _isLoading,
                        onPressed: _handleLogin,
                      )
                      .animate(onPlay: (c) => c.repeat())
                      .shimmer(
                        delay: 2500.ms,
                        duration: 1500.ms,
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
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
                          "OR",
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
                  ).animate().fadeIn(delay: 1000.ms),
                  const SizedBox(height: 24),
                  _isLoading
                      ? const SizedBox.shrink()
                      : ElevatedButton.icon(
                          onPressed: _handleGoogleSignIn,
                          icon: const FaIcon(
                            FontAwesomeIcons.google,
                            color: Colors.white,
                            size: 20,
                          ),
                          label: Text(
                            'Continue with Google',
                            style: GoogleFonts.nunito(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4285F4),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 56),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 4,
                            shadowColor: Colors.black.withValues(alpha: 0.3),
                          ),
                        ).animate().fadeIn(delay: 1100.ms).slideY(begin: 0.1),
                ],
              ),
            ),
          ),
        )
        .animate()
        .fadeIn(delay: 600.ms)
        .scale(begin: const Offset(0.95, 0.95), curve: Curves.easeOutCubic);
  }
}
