import 'dart:ui';
import 'package:Badya/legal_document_page.dart';
import 'package:Badya/services/auth_service.dart';
import 'package:Badya/utils/legal_content.dart';
import 'package:Badya/utils/ui_utils.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'custom_button.dart';
import 'custom_text_field.dart';

class SignUpForm extends StatefulWidget {
  const SignUpForm({super.key});

  @override
  State<SignUpForm> createState() => _SignUpFormState();
}

class _SignUpFormState extends State<SignUpForm> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;

  /// Whether the user has accepted the Terms of Service / Privacy Policy.
  /// Both sign-up buttons stay disabled until this is true.
  bool _acceptedTerms = false;

  @override
  void initState() {
    super.initState();
    // Rebuild so the live password-mismatch hint updates as the user types.
    _passwordController.addListener(_onPasswordFieldsChanged);
    _confirmPasswordController.addListener(_onPasswordFieldsChanged);
  }

  @override
  void dispose() {
    _passwordController.removeListener(_onPasswordFieldsChanged);
    _confirmPasswordController.removeListener(_onPasswordFieldsChanged);
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _onPasswordFieldsChanged() {
    if (mounted) setState(() {});
  }

  /// True once the user has typed both passwords and they don't match.
  bool get _passwordsMismatch =>
      _confirmPasswordController.text.isNotEmpty &&
      _passwordController.text.isNotEmpty &&
      _passwordController.text != _confirmPasswordController.text;

  Future<void> _handleSignUp() async {
    if (!_acceptedTerms) {
      UiUtils.showErrorSnackbar(
        context,
        'Please accept the Terms of Service and Privacy Policy to continue.',
      );
      return;
    }
    final email = _emailController.text.trim();
    if (email.isEmpty ||
        _passwordController.text.trim().isEmpty ||
        _nameController.text.trim().isEmpty) {
      UiUtils.showErrorSnackbar(
        context,
        'Please complete all required fields to create your account.',
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
    if (_passwordsMismatch) {
      UiUtils.showErrorSnackbar(context, 'Passwords do not match.');
      return;
    }
    final pw = _passwordController.text.trim();
    if (pw.length < 8 || !RegExp(r'[A-Z]').hasMatch(pw) || !RegExp(r'[0-9]').hasMatch(pw)) {
      UiUtils.showErrorSnackbar(
        context,
        'Password must be at least 8 characters with 1 uppercase letter and 1 number.',
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final userCred = await context.read<AuthService>().signUpWithEmail(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );

      if (userCred != null && _nameController.text.trim().isNotEmpty) {
        await userCred.user?.updateDisplayName(_nameController.text.trim());
      }

      // A verification email was sent inside AuthService.signUpWithEmail().
      // The auth state change makes MyApp rebuild with AuthWrapper as the
      // MaterialApp `home` route, but this SignUpPage was pushed on top of
      // the navigator — pop back to the root so AuthWrapper becomes visible
      // and routes the (still unverified) user to EmailVerificationPage.
      if (!mounted) return;
      UiUtils.showSuccessSnackbar(
        context,
        'Account created! Check your email to verify your account.',
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'weak-password':
          message =
              'The password is too simple. Try using at least 6 characters with symbols.';
          break;
        case 'email-already-in-use':
          message =
              'An account already exists for this email. Try logging in instead.';
          break;
        case 'invalid-email':
          message = 'Please provide a valid email address.';
          break;
        case 'operation-not-allowed':
          message =
              'Email sign-up is currently disabled. Please contact support.';
          break;
        default:
          message =
              'Registration failed. Please check your details and try again.';
      }
      if (mounted) {
        UiUtils.showErrorSnackbar(context, message, error: e.toString());
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
    if (!_acceptedTerms) {
      UiUtils.showErrorSnackbar(
        context,
        'Please accept the Terms of Service and Privacy Policy to continue.',
      );
      return;
    }
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
          'Account created with Google successfully!',
        );
        Navigator.pop(context); // Go back to login/home
      }
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'account-exists-with-different-credential':
          message = 'An account already exists with a different sign-in method. Please use email/password to sign in.';
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
        case 'missing-id-token':
          message = 'Google Sign-In failed: Missing authentication token. Please try again.';
          break;
        case 'google-sign-in-failed':
          message = 'Google Sign-In failed. Please try again.';
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
                    controller: _nameController,
                    labelText: 'Full Name',
                    hintText: 'John Doe',
                    prefixIcon: Icons.person_outline_rounded,
                  ).animate().fadeIn(delay: 700.ms).slideX(begin: -0.1),
                  const SizedBox(height: 16),
                  CustomTextField(
                    controller: _emailController,
                    labelText: 'Email Address',
                    hintText: 'your@email.com',
                    prefixIcon: Icons.alternate_email_rounded,
                    keyboardType: TextInputType.emailAddress,
                  ).animate().fadeIn(delay: 800.ms).slideX(begin: -0.1),
                  const SizedBox(height: 16),
                  CustomTextField(
                    controller: _passwordController,
                    labelText: 'Password',
                    hintText: '••••••••',
                    prefixIcon: Icons.lock_outline_rounded,
                    isPasswordField: true,
                  ).animate().fadeIn(delay: 900.ms).slideX(begin: -0.1),
                  const SizedBox(height: 16),
                  CustomTextField(
                    controller: _confirmPasswordController,
                    labelText: 'Confirm Password',
                    hintText: '••••••••',
                    prefixIcon: Icons.lock_outline_rounded,
                    isPasswordField: true,
                  ).animate().fadeIn(delay: 950.ms).slideX(begin: -0.1),
                  if (_passwordController.text.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Password Requirements:',
                            style: GoogleFonts.nunito(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildRequirementRow(
                            'At least 8 characters',
                            _passwordController.text.length >= 8,
                          ),
                          _buildRequirementRow(
                            'Contains uppercase letter',
                            RegExp(r'[A-Z]').hasMatch(_passwordController.text),
                          ),
                          _buildRequirementRow(
                            'Contains number',
                            RegExp(r'[0-9]').hasMatch(_passwordController.text),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_passwordsMismatch)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, left: 8),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_rounded,
                            color: Colors.redAccent,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Passwords do not match',
                            style: GoogleFonts.nunito(
                              fontSize: 12,
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    const SizedBox(height: 16),
                  _buildTermsRow().animate().fadeIn(delay: 1000.ms),
                  const SizedBox(height: 24),
                  CustomButton(
                        text: 'SIGN UP',
                        backgroundColor: const Color(0xFF2ECC71),
                        isLoading: _isLoading,
                        isEnabled: _acceptedTerms,
                        onPressed: _handleSignUp,
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
                          onPressed: _acceptedTerms
                              ? _handleGoogleSignIn
                              : null,
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

  /// Opens a legal document (ToS / Privacy Policy) as a full page.
  void _openLegalDocument(
    BuildContext context, {
    required LegalDocument document,
    required IconData icon,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LegalDocumentPage(document: document, icon: icon),
      ),
    );
  }

  /// "I agree to the Terms of Service and Privacy Policy" checkbox row.
  ///
  /// Tapping the box or the label toggles acceptance; tapping either document
  /// name opens the full legal page. Sign-up stays disabled until accepted.
  Widget _buildTermsRow() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseStyle = GoogleFonts.nunito(
      fontSize: 12.5,
      height: 1.4,
      color: isDark ? Colors.white70 : Colors.black54,
    );
    final linkStyle = GoogleFonts.nunito(
      fontSize: 12.5,
      height: 1.4,
      fontWeight: FontWeight.w800,
      color: const Color(0xFFF78B1E),
      decoration: TextDecoration.underline,
      decorationColor: const Color(0xFFF78B1E),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          checked: _acceptedTerms,
          label: 'Accept the Terms of Service and Privacy Policy',
          child: GestureDetector(
          key: const Key('accept_terms_checkbox'),
          onTap: () => setState(() => _acceptedTerms = !_acceptedTerms),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              color: _acceptedTerms
                  ? const Color(0xFF2ECC71)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _acceptedTerms
                    ? const Color(0xFF2ECC71)
                    : (isDark ? Colors.white38 : Colors.black38),
                width: 2,
              ),
            ),
            child: _acceptedTerms
                ? const Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: Colors.white,
                  )
                : null,
          ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          // Tapping anywhere on the label toggles acceptance; the document
          // name links override that and open the full legal pages.
          child: GestureDetector(
            onTap: () => setState(() => _acceptedTerms = !_acceptedTerms),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('I agree to the ', style: baseStyle),
                GestureDetector(
                  onTap: () => _openLegalDocument(
                    context,
                    document: LegalContent.termsOfService,
                    icon: Icons.gavel_rounded,
                  ),
                  child: Text('Terms of Service', style: linkStyle),
                ),
                Text(' and ', style: baseStyle),
                GestureDetector(
                  onTap: () => _openLegalDocument(
                    context,
                    document: LegalContent.privacyPolicy,
                    icon: Icons.privacy_tip_rounded,
                  ),
                  child: Text('Privacy Policy', style: linkStyle),
                ),
                Text('.', style: baseStyle),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRequirementRow(String text, bool isMet) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            isMet ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 16,
            color: isMet ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: GoogleFonts.nunito(
              fontSize: 12,
              color: isMet ? Colors.green : Theme.of(context).textTheme.bodySmall?.color,
              fontWeight: isMet ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
