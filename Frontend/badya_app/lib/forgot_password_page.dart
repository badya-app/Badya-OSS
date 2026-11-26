import 'dart:ui';
import 'package:Badya/utils/ui_utils.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'services/auth_service.dart';
import 'widgets/custom_text_field.dart';
import 'widgets/custom_button.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailController = TextEditingController();
  bool _isLoading = false;

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      UiUtils.showErrorSnackbar(
        context,
        'Please provide your email address to receive the reset link.',
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
      await context.read<AuthService>().resetPassword(email);
      if (mounted) {
        UiUtils.showSuccessSnackbar(
          context,
          'A password reset link has been sent to your inbox.',
        );
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = 'We couldn\'t find an account associated with this email.';
          break;
        case 'invalid-email':
          message = 'Please provide a valid email address.';
          break;
        case 'too-many-requests':
          message = 'Too many requests. Please try again in a few minutes.';
          break;
        default:
          message =
              'Could not process your request at this time. Please try again.';
      }
      if (mounted) {
        UiUtils.showErrorSnackbar(context, message, error: e.toString());
      }
    } catch (e) {
      if (mounted) {
        UiUtils.showErrorSnackbar(
          context,
          'An unexpected error occurred. Please try again.',
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
    final subtitleColor = isDark
        ? Colors.white.withValues(alpha: 0.9)
        : const Color(0xFF2D3436);

    return Scaffold(
      body: Stack(
        children: [
          SizedBox.expand(
            child: SvgPicture.asset(
              isDark
                  ? 'assets/images/logindark.svg'
                  : 'assets/images/login_background.svg',
              fit: BoxFit.cover,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  Text(
                    'Forgot Password?',
                    style: GoogleFonts.merriweather(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFFF78B1E),
                    ),
                  ).animate().fadeIn().slideX(),
                  const SizedBox(height: 8),
                  Text(
                    "Don't worry! Enter your email and we'll send you a link to reset your password.",
                    style: GoogleFonts.nunito(
                      fontSize: 16,
                      color: subtitleColor,
                    ),
                  ).animate().fadeIn(delay: 200.ms).slideX(),
                  const SizedBox(height: 32),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.black.withValues(alpha: 0.3)
                              : Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Column(
                          children: [
                            CustomTextField(
                              controller: _emailController,
                              labelText: 'Email',
                              prefixIcon: Icons.email_rounded,
                              keyboardType: TextInputType.emailAddress,
                            ),
                            const SizedBox(height: 24),
                            _isLoading
                                ? const CircularProgressIndicator(
                                    color: Color(0xFFF78B1E),
                                  )
                                : CustomButton(
                                    text: 'SEND RESET LINK',
                                    backgroundColor: const Color(0xFFF78B1E),
                                    onPressed: _resetPassword,
                                  ),
                          ],
                        ),
                      ),
                    ),
                  ).animate().fadeIn(delay: 400.ms).scale(),
                  const Spacer(flex: 2),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
