import 'dart:async';
import 'package:Badya/blocked_users_page.dart';
import 'package:Badya/language_profile_page.dart';
import 'package:Badya/legal_document_page.dart';
import 'package:Badya/manage_languages_page.dart';
import 'package:Badya/services/firebase_storage_service.dart';
import 'package:Badya/services/auth_service.dart';
import 'package:Badya/services/user_preferences_service.dart';
import 'package:Badya/services/language_manager.dart';
import 'package:Badya/services/notification_preferences_service.dart';
import 'package:Badya/services/notification_service.dart';
import 'package:Badya/widgets/notification_settings_sheet.dart';
import 'package:Badya/utils/constants.dart';
import 'package:Badya/utils/legal_content.dart';
import 'package:Badya/utils/level_service.dart';
import 'package:Badya/config/local_mode.dart';
import 'package:Badya/utils/logger.dart';
import 'package:Badya/utils/profile_images.dart';
import 'package:Badya/utils/theme_service.dart';
import 'package:Badya/forgot_password_page.dart';
import 'package:Badya/utils/ui_utils.dart';

import 'package:Badya/widgets/section_header.dart';
import 'package:Badya/widgets/consistency_calendar.dart';
import 'package:Badya/widgets/custom_dialog.dart';
import 'package:Badya/widgets/avatar_picker_sheet.dart';
import 'package:country_flags/country_flags.dart';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:Badya/utils/score_service.dart';
import 'level_path_page.dart';

class ProfilePage extends StatefulWidget {
  final VoidCallback? onPhotoChanged;

  const ProfilePage({super.key, this.onPhotoChanged});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  List<String> _myLanguages = ['English'];
  String? _photoUrl;
  bool _isUploading = false;
  int _totalXp = 0;
  int _streak = 0;
  int _level = 1;
  String? _displayName;
  final ImagePicker _picker = ImagePicker();
  Map<String, int> _languageScores = {};
  /// Real activity days (day-of-month) for the displayed month, from
  /// `daily_activity` — drives the ConsistencyCalendar.
  Set<int> _activeDays = {};
  /// Months with at least one qualifying activity day (for arrow gating).
  Set<DateTime> _availableMonths = {};

  /// Live XP/streak subscription — updates total XP, level, streak, and
  /// per-language scores the moment a write lands on the user document.
  StreamSubscription<
    ({int totalXp, int streak, Map<String, int> languageXp})
  >? _xpSub;

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _skillRingsKey = GlobalKey();
  bool _hasAnimatedRings = false;
  final TextEditingController _feedbackController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfileData();
    _scrollController.addListener(_onScroll);
    // Update XP-derived stats instantly when a write lands on the user
    // document (e.g. the unscramble game awarding XP) — no manual refresh.
    _xpSub = ScoreService.xpSnapshotStream().listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _totalXp = snapshot.totalXp;
        _level = LevelService.levelForXp(snapshot.totalXp);
        _streak = snapshot.streak;
        _languageScores = {
          for (final lang in _myLanguages)
            lang: snapshot.languageXp[lang] ?? 0,
        };
      });
    });
  }

  /// Track the last-seen language list from LanguageManager so we can
  /// detect changes without re-calling _loadProfileData from inside build.
  List<String>? _lastSeenManagerLanguages;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final managerLanguages = context.read<LanguageManager>().myLanguages;
    // Sync local _myLanguages when LanguageManager changes (e.g. account
    // switch or language added/removed elsewhere). Only reload scores —
    // avoid a full _loadProfileData to prevent the infinite rebuild loop
    // that previously locked scrolling.
    if (_lastSeenManagerLanguages == null ||
        !_listEquals(_lastSeenManagerLanguages!, managerLanguages)) {
      _lastSeenManagerLanguages = List.from(managerLanguages);
      if (!_listEquals(_myLanguages, managerLanguages)) {
        setState(() {
          _myLanguages = [...managerLanguages];
        });
        _reloadScoresForLanguages();
      }
    }
  }

  /// Lightweight reload: fetch scores for the current language list without
  /// touching photo / display name / streak (those are already loaded by
  /// _loadProfileData and don't change on language switches).
  Future<void> _reloadScoresForLanguages() async {
    Map<String, int> scores = {};
    for (var lang in _myLanguages) {
      scores[lang] = await ScoreService.getScore(lang);
    }
    if (!mounted) return;
    setState(() {
      _languageScores = scores;
    });
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    return a.every((lang) => b.contains(lang));
  }

  /// Re-fetch activity days when the user navigates to a different month
  /// in the ConsistencyCalendar.
  Future<void> _onCalendarMonthChanged(DateTime month) async {
    final activeDays = await ScoreService.getActiveActivityDaysForCurrentMonth(
      null,
      month.year,
      month.month,
    );
    if (!mounted) return;
    setState(() {
      _activeDays = activeDays;
    });
  }

  @override
  void dispose() {
    _xpSub?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _feedbackController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_hasAnimatedRings) return;

    final context = _skillRingsKey.currentContext;
    if (context == null) return;

    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !mounted) return;

    final position = renderBox.localToGlobal(Offset.zero);
    final screenHeight = MediaQuery.of(this.context).size.height;

    // Trigger animation when the section is 70% visible
    if (position.dy < screenHeight * 0.7 &&
        position.dy > -renderBox.size.height) {
      if (mounted) {
        setState(() {
          _hasAnimatedRings = true;
        });
      }
    }
  }

  Future<void> _loadProfileData() async {
    final preferences = UserPreferencesService();
    final languages = await preferences.getMyLanguages();
    // Show the stored streak immediately; the background refresh below
    // recomputes from daily_activity (grace period) so a missed day clears
    // it without blocking the profile load.
    final streak = await ScoreService.getStreak();
    final activeDays =
        await ScoreService.getActiveActivityDaysForCurrentMonth();
    final availableMonths = await ScoreService.getAvailableMonths();
    final displayName = await preferences.getDisplayName();
    final photoUrl = await preferences.getPhotoUrl();

    final userId = LocalMode.enabled
        ? LocalMode.guestUid
        : FirebaseAuth.instance.currentUser?.uid;

    Map<String, int> scores = {};

    for (var lang in languages) {
      scores[lang] = await ScoreService.getScore(lang);
    }

    final totalXp = await ScoreService.getTotalXP();
    final level = LevelService.levelForXp(totalXp);

    if (!mounted) return;

    // Check if languages changed
    final languagesChanged =
        _myLanguages.length != languages.length ||
        !_myLanguages.every((lang) => languages.contains(lang));

    setState(() {
      _photoUrl = photoUrl;
      _myLanguages = languages;
      _streak = streak;
      _activeDays = activeDays;
      _availableMonths = availableMonths;
      _totalXp = totalXp;
      _level = level;
      _displayName = displayName;
      _languageScores = scores;
    });

    // Recompute the streak in the background and update in place when done.
    unawaited(ScoreService.refreshStreak().then((fresh) {
      if (mounted && fresh != _streak) {
        setState(() => _streak = fresh);
      }
    }));

    // Reset scroll and animation only if languages actually changed
    if (languagesChanged) {
      _hasAnimatedRings = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    }
  }

  void _showEditDisplayNameDialog() {
    final controller = TextEditingController(text: _displayName);
    showDialog(
      context: context,
      builder: (context) => CustomDialog(
        title: 'Edit Display Name',
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Display Name',
            hintText: 'Enter your name',
          ),
          autofocus: true,
        ),
        cancelButtonText: 'Cancel',
        saveButtonText: 'Save',
        onCancel: () => Navigator.pop(context),
        onSave: () async {
          final newName = controller.text.trim();
          if (newName.isEmpty) return;

          // Apply the local change, then dismiss immediately. The Firestore write
          // (now with a 10s timeout) runs in the background so the dialog never
          // hangs on a bad connection. Any failure is logged and silently ignored
          // — the local state already reflects the choice.
          setState(() => _displayName = newName);
          if (!mounted) return;
          Navigator.pop(context);

          try {
            await UserPreferencesService().updateDisplayName(newName);
          } catch (_) {
            // Offline / network error — local state already applied.
          }
        },
      ),
    );
  }

  Future<void> _onEditProfileImage() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardTheme.color,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Profile Photo',
              style: GoogleFonts.nunito(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Theme.of(context).textTheme.titleLarge?.color,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Color(0xFF9B59B6).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.face_rounded, color: Color(0xFF9B59B6)),
              ),
              title: Text(
                'Choose Avatar',
                style: GoogleFonts.nunito(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                'Pick from our avatar collection',
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  color: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickAvatar();
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Color(0xFF4ECDC4).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.photo_library_rounded,
                  color: Color(0xFF4ECDC4),
                ),
              ),
              title: Text(
                'Upload from Gallery',
                style: GoogleFonts.nunito(fontWeight: FontWeight.w700),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickImage();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 75,
      );
      if (image != null) {
        setState(() => _isUploading = true);
        final storage = FirebaseStorageService();
        final url = await storage.uploadFile(image.path, 'profile_photos');
        if (url != null) {
          final preferences = UserPreferencesService();
          await preferences.updatePhotoUrl(url);
          setState(() {
            _photoUrl = url;
            _isUploading = false;
          });
          widget.onPhotoChanged?.call();
        } else {
          setState(() => _isUploading = false);
        }
      }
    } catch (e) {
      Logger.error('Error picking image', e);
      setState(() => _isUploading = false);
    }
  }

  Future<void> _pickAvatar() async {
    final assetPath = await showAvatarPickerSheet(context);
    if (assetPath != null && mounted) {
      setState(() => _photoUrl = assetPath);
      final preferences = UserPreferencesService();
      await preferences.updatePhotoUrl(assetPath);
      widget.onPhotoChanged?.call();
    }
  }

  Future<void> _handleLogout() async {
    // Review issue #8 — confirmation dialog with the signed-in email to
    // prevent accidental logouts.
    final user = context.read<AuthService>().currentUser;
    final userEmail = user?.email;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.logout_rounded, color: Color(0xFFE57373)),
            const SizedBox(width: 8),
            Text(
              'Log Out',
              style: GoogleFonts.nunito(fontWeight: FontWeight.w900, fontSize: 20),
            ),
          ],
        ),
        content: Text(
          userEmail != null && userEmail.isNotEmpty
              ? 'Are you sure you want to log out of $userEmail?'
              : 'Are you sure you want to log out?',
          style: GoogleFonts.nunito(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Log Out',
              style: TextStyle(
                color: const Color(0xFFE57373),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Review issue #7 — clean up notifications on logout: cancel scheduled
    // local reminders so they don't fire for a signed-out device. Best-effort:
    // a notification cleanup failure must never block the logout itself.
    try {
      await NotificationService().cancelAllNotifications();
    } catch (e) {
      Logger.warn('Failed to cancel notifications on logout: $e');
    }

    try {
      await context.read<AuthService>().signOut();
      // AuthWrapper in main.dart handles navigation
    } catch (e) {
      if (mounted) {
        UiUtils.showErrorSnackbar(context, 'Logout failed: ${e.toString()}');
      }
    }
  }

  void _showChangePasswordDialog() {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool showCurrentPassword = false;
    bool showNewPassword = false;
    bool showConfirmPassword = false;
    String? passwordStrength;
    String? errorMessage;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          void updatePasswordStrength(String password) {
            setState(() {
              if (password.isEmpty) {
                passwordStrength = null;
              } else if (password.length < 8) {
                passwordStrength = 'Weak';
              } else if (password.length < 12 ||
                  !RegExp(r'[A-Z]').hasMatch(password) ||
                  !RegExp(r'[0-9]').hasMatch(password)) {
                passwordStrength = 'Fair';
              } else {
                passwordStrength = 'Strong';
              }
            });
          }

          Color getStrengthColor() {
            switch (passwordStrength) {
              case 'Weak':
                return Colors.red;
              case 'Fair':
                return Colors.orange;
              case 'Strong':
                return Colors.green;
              default:
                return Colors.grey;
            }
          }

          bool isFormValid() {
            final pw = newPasswordController.text;
            return currentPasswordController.text.isNotEmpty &&
                pw.isNotEmpty &&
                confirmPasswordController.text.isNotEmpty &&
                pw == confirmPasswordController.text &&
                pw.length >= 8 &&
                RegExp(r'[A-Z]').hasMatch(pw) &&
                RegExp(r'[0-9]').hasMatch(pw);
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              'Change Password',
              style: GoogleFonts.nunito(
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Error message if exists
                  if (errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red, width: 1),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_rounded,
                            color: Colors.red,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errorMessage!,
                              style: GoogleFonts.nunito(
                                fontSize: 12,
                                color: Colors.red,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    'For your security, please enter your current password and choose a strong new password.',
                    style: GoogleFonts.nunito(
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Current Password Field
                  TextField(
                    controller: currentPasswordController,
                    obscureText: !showCurrentPassword,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Current Password',
                      hintText: 'Enter your current password',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          showCurrentPassword
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                          size: 20,
                        ),
                        onPressed: () {
                          setState(
                            () => showCurrentPassword = !showCurrentPassword,
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () {
                        Navigator.pop(context);
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
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // New Password Field
                  TextField(
                    controller: newPasswordController,
                    obscureText: !showNewPassword,
                    onChanged: updatePasswordStrength,
                    decoration: InputDecoration(
                      labelText: 'New Password',
                      hintText: 'At least 8 characters',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          showNewPassword
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                          size: 20,
                        ),
                        onPressed: () {
                          setState(() => showNewPassword = !showNewPassword);
                        },
                      ),
                    ),
                  ),
                  if (passwordStrength != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: passwordStrength == 'Strong'
                                  ? 1.0
                                  : passwordStrength == 'Fair'
                                  ? 0.66
                                  : 0.33,
                              minHeight: 4,
                              backgroundColor: Colors.grey[300],
                              valueColor: AlwaysStoppedAnimation(
                                getStrengthColor(),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          passwordStrength!,
                          style: GoogleFonts.nunito(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: getStrengthColor(),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  // Confirm Password Field
                  TextField(
                    controller: confirmPasswordController,
                    obscureText: !showConfirmPassword,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Confirm New Password',
                      hintText: 'Re-enter your new password',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          showConfirmPassword
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                          size: 20,
                        ),
                        onPressed: () {
                          setState(
                            () => showConfirmPassword = !showConfirmPassword,
                          );
                        },
                      ),
                      errorText:
                          newPasswordController.text.isNotEmpty &&
                              confirmPasswordController.text.isNotEmpty &&
                              newPasswordController.text !=
                                  confirmPasswordController.text
                          ? 'Passwords do not match'
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Password Requirements
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).primaryColor.withValues(alpha: 0.1),
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
                          newPasswordController.text.length >= 8,
                        ),
                        _buildRequirementRow(
                          'Contains uppercase letter',
                          RegExp(r'[A-Z]').hasMatch(newPasswordController.text),
                        ),
                        _buildRequirementRow(
                          'Contains number',
                          RegExp(r'[0-9]').hasMatch(newPasswordController.text),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: isFormValid()
                    ? () async {
                        try {
                          final user = context.read<AuthService>().currentUser;
                          if (user?.email == null) {
                            setState(() {
                              errorMessage = 'User email not found';
                            });
                            return;
                          }

                          // Check if new password is same as current password
                          if (currentPasswordController.text.trim() ==
                              newPasswordController.text.trim()) {
                            setState(() {
                              errorMessage =
                                  'New password must be different from current password';
                            });
                            return;
                          }

                          // Check if user has email/password provider
                          bool hasEmailProvider = false;
                          for (var provider in user!.providerData) {
                            if (provider.providerId == 'password') {
                              hasEmailProvider = true;
                              break;
                            }
                          }

                          if (!hasEmailProvider) {
                            setState(() {
                              errorMessage =
                                  'Google Sign-In accounts cannot change password here. Your password is managed by Google Account.';
                            });
                            return;
                          }

                          // Reauthenticate with current password
                          final credential = EmailAuthProvider.credential(
                            email: user.email!,
                            password: currentPasswordController.text.trim(),
                          );
                          await user.reauthenticateWithCredential(credential);

                          // Update to new password
                          await user.updatePassword(
                            newPasswordController.text.trim(),
                          );

                          if (context.mounted) {
                            Navigator.pop(context);
                            UiUtils.showTopNotification(
                              this.context,
                              'Password changed successfully!',
                            );
                          }
                        } on FirebaseAuthException catch (e) {
                          String errorMsg = 'Failed to change password';
                          if (e.code == 'wrong-password' ||
                              e.code == 'invalid-credential') {
                            errorMsg = 'Current password is incorrect';
                          } else if (e.code == 'weak-password') {
                            errorMsg = 'New password is too weak';
                          } else {
                            errorMsg = e.message ?? errorMsg;
                          }

                          setState(() {
                            errorMessage = errorMsg;
                          });
                        } catch (e) {
                          setState(() {
                            errorMessage = 'Error: ${e.toString()}';
                          });
                        }
                      }
                    : null,
                child: Text(
                  'Update',
                  style: TextStyle(
                    color: isFormValid()
                        ? const Color(0xFF6C5CE7)
                        : Colors.grey,
                  ),
                ),
              ),
            ],
          );
        },
      ),
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
              color: isMet
                  ? Colors.green
                  : Theme.of(context).textTheme.bodySmall?.color,
              fontWeight: isMet ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  void _showThemeSelectionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardTheme.color,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select Theme',
                style: GoogleFonts.nunito(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Theme.of(context).textTheme.titleLarge?.color,
                ),
              ),
              const SizedBox(height: 16),
              _buildThemeOption(context, 'System Default', ThemeMode.system),
              _buildThemeOption(context, 'Light Mode', ThemeMode.light),
              _buildThemeOption(context, 'Dark Mode', ThemeMode.dark),
            ],
          ),
        );
      },
    );
  }

  void _showNotificationSettingsSheet(BuildContext context) {
    final preferencesService = NotificationPreferencesService();

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardTheme.color,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (context) =>
          NotificationSettingsSheet(preferencesService: preferencesService),
    );
  }

  Widget _buildAlwaysActiveItem(IconData icon, String title, String subtitle) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Theme.of(context).primaryColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.nunito(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              Text(
                subtitle,
                style: GoogleFonts.nunito(
                  fontSize: 11,
                  color: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildThemeOption(BuildContext context, String title, ThemeMode mode) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.themeMode,
      builder: (context, currentMode, _) {
        final isSelected = currentMode == mode;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            title,
            style: GoogleFonts.nunito(
              fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
              fontSize: 18,
              color: isSelected
                  ? Theme.of(context).primaryColor
                  : Theme.of(context).textTheme.bodyLarge?.color,
            ),
          ),
          trailing: isSelected
              ? Icon(
                  Icons.check_circle_rounded,
                  color: Theme.of(context).primaryColor,
                )
              : null,
          onTap: () {
            ThemeService.saveTheme(mode);
            Navigator.pop(context);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final userName = user?.displayName ?? user?.email?.split('@')[0] ?? 'User';
    final effectiveName = _displayName?.isNotEmpty == true
        ? _displayName!
        : userName;

    final xpProgress = LevelService.xpProgress(_totalXp);
    final int xpForCurrent = xpProgress.xpForCurrentLevel;
    final int xpForNext = xpProgress.xpForNextLevel;
    final int xpToNext = xpProgress.xpToNextLevel;
    final double progressFraction = xpForNext == xpForCurrent
        ? 1
        : ((_totalXp - xpForCurrent) / (xpForNext - xpForCurrent)).clamp(0, 1);

    // Own profile: always show everything regardless of visibility flags.
    // Visibility controls are used when OTHER users view this profile,
    // which will be handled by a dedicated public-profile view.
    return Scaffold(
      extendBody: true,
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
        child: Column(
          children: [
            const SizedBox(height: 50),
            // Profile Card
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFF4ECDC4).withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
                border: Border.all(
                  color: Color(0xFF4ECDC4).withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      GestureDetector(
                        onTap: _isUploading ? null : _onEditProfileImage,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFFFF9F0),
                            border: Border.all(
                              color: const Color(0xFFFF6B6B),
                              width: 4,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Color(0xFFFF6B6B).withValues(alpha: 0.2),
                                blurRadius: 15,
                                offset: const Offset(0, 5),
                              ),
                            ],
                            image: DecorationImage(
                              image: resolveProfileImage(_photoUrl),
                              fit: BoxFit.cover,
                            ),
                          ),
                          child: _isUploading
                              ? const Center(child: CircularProgressIndicator())
                              : null,
                        ),
                      ),
                      if (!_isUploading)
                        GestureDetector(
                              onTap: _onEditProfileImage,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(
                                  color: Color(0xFF4ECDC4),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.edit_rounded,
                                  size: 20,
                                  color: Colors.white,
                                ),
                              ),
                            )
                            .animate(onPlay: (c) => c.repeat(reverse: true))
                            .scale(
                              begin: const Offset(0.9, 0.9),
                              end: const Offset(1.1, 1.1),
                            ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        effectiveName,
                        style: GoogleFonts.nunito(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: Theme.of(context).textTheme.titleLarge?.color,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _showEditDisplayNameDialog,
                        child: Icon(
                          Icons.edit_rounded,
                          size: 20,
                          color: const Color(0xFF4ECDC4),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (user?.email != null)
                        Text(
                          user!.email!,
                          style: GoogleFonts.nunito(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).textTheme.bodyMedium?.color
                                ?.withValues(alpha: 0.8),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildStatItem(
                        'XP',
                        _totalXp.toString(),
                        const Color(0xFFFF6B6B),
                      ),
                      Container(
                        height: 40,
                        width: 2,
                        color: Theme.of(
                          context,
                        ).dividerColor.withValues(alpha: 0.1),
                      ),
                      _buildStatItem(
                        'Streak 🔥',
                        '$_streak',
                        const Color(0xFFFFD93D),
                      ),
                      Container(
                        height: 40,
                        width: 2,
                        color: Theme.of(
                          context,
                        ).dividerColor.withValues(alpha: 0.1),
                      ),
                      _buildStatItem(
                        'Level',
                        '$_level',
                        const Color(0xFF4ECDC4),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => LevelPathPage(totalXp: _totalXp),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // XP progress bar
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Level $_level',
                            style: GoogleFonts.nunito(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Theme.of(
                                context,
                              ).textTheme.bodyLarge?.color,
                            ),
                          ),
                          Text(
                            '${_totalXp - xpForCurrent} / ${xpForNext - xpForCurrent} XP',
                            style: GoogleFonts.nunito(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.color
                                  ?.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: LinearProgressIndicator(
                          value: progressFraction,
                          minHeight: 8,
                          backgroundColor: Theme.of(
                            context,
                          ).dividerColor.withValues(alpha: 0.2),
                          valueColor: const AlwaysStoppedAnimation(
                            Color(0xFFFF6B6B),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$xpToNext XP to next level',
                        style: GoogleFonts.nunito(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.color?.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ).animate().fadeIn().slideY(begin: 0.1, curve: Curves.easeOutBack),

            const SizedBox(height: 32),

            // Consistency Calendar
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: ConsistencyCalendar(
                  activeDays: _activeDays,
                  availableMonths: _availableMonths,
                  onMonthChanged: _onCalendarMonthChanged,
                ),
              ),
            ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1),

            const SizedBox(height: 32),

            // Languages Section
            const SectionHeader(title: 'Languages'),
            const SizedBox(height: 20),
            // Language sync is handled by didChangeDependencies — no
            // Consumer needed here (previously caused an infinite rebuild
            // loop that locked scrolling on account switch).
            SizedBox(
                  height: 140,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _myLanguages.length,
                    itemBuilder: (context, index) {
                      final language = _myLanguages[index];
                      final score = _languageScores[language] ?? 0;
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  LanguageProfilePage(language: language),
                            ),
                          );
                        },
                        child:
                            Container(
                                  width: 120,
                                  margin: const EdgeInsets.only(right: 16),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).cardTheme.color,
                                    borderRadius: BorderRadius.circular(24),
                                    border: Border.all(
                                      color: Theme.of(
                                        context,
                                      ).dividerColor.withValues(alpha: 0.1),
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.04,
                                        ),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Color(
                                              0xFF4ECDC4,
                                            ).withValues(alpha: 0.5),
                                            width: 2,
                                          ),
                                        ),
                                        child: ClipOval(
                                          child: CountryFlag.fromCountryCode(
                                            languageCodes[language] ?? 'US',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        language,
                                        style: GoogleFonts.nunito(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                          color: Theme.of(
                                            context,
                                          ).textTheme.bodyLarge?.color,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '$score XP',
                                        style: GoogleFonts.nunito(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                          color: const Color(0xFFFF6B6B),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                                .animate()
                                .fadeIn(delay: (index * 100).ms)
                                .scale(begin: const Offset(0.9, 0.9)),
                      );
                    },
                  ),
                ),

            const SizedBox(height: 32),

            // Settings Section
            const SectionHeader(title: 'Settings'),
            const SizedBox(height: 16),
            _buildSettingsTile(
              Icons.palette_rounded,
              'App Theme',
              const Color(0xFF6C5CE7),
              onTap: () => _showThemeSelectionSheet(context),
            ),
            _buildSettingsTile(
              Icons.language_rounded,
              'Language Settings',
              const Color(0xFF4ECDC4),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ManageLanguagesPage(),
                  ),
                );
                _loadProfileData();
              },
            ),
            _buildSettingsTile(
              Icons.notifications_rounded,
              'Study Reminders',
              const Color(0xFFFFD93D),
              onTap: () {
                _showNotificationSettingsSheet(context);
              },
            ),
            _buildSettingsTile(
              Icons.lock_rounded,
              'Privacy & Security',
              const Color(0xFF4ECDC4),
              onTap: () {
                _showPrivacySheet(context);
              },
            ),
            _buildSettingsTile(
              Icons.feedback_rounded,
              'Send Feedback',
              const Color(0xFFFF6B6B),
              onTap: _sendFeedback,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _handleLogout,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFE57373),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  backgroundColor: Color(0xFFE57373).withValues(alpha: 0.1),
                ),
                child: Text(
                  'Log Out',
                  style: GoogleFonts.nunito(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    Color color, {
    VoidCallback? onTap,
  }) {
    final content = Column(
      children: [
        Text(
          value,
          style: GoogleFonts.nunito(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.nunito(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).textTheme.bodyMedium?.color,
          ),
        ),
      ],
    );

    if (onTap == null) return content;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: content,
      ),
    );
  }

  void _showPrivacySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardTheme.color,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Privacy & Security',
                style: GoogleFonts.nunito(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 24),
              _buildSettingsTile(
                Icons.key_rounded,
                'Change Password',
                const Color(0xFF6C5CE7),
                onTap: () {
                  Navigator.pop(context);
                  Future.delayed(
                    const Duration(milliseconds: 300),
                    () => _showChangePasswordDialog(),
                  );
                },
              ),
              _buildSettingsTile(
                Icons.delete_forever_rounded,
                'Delete Account',
                const Color(0xFFE57373),
                onTap: () {
                  Navigator.pop(context);
                  Future.delayed(
                    const Duration(milliseconds: 300),
                    () => _showDeleteAccountDialog(),
                  );
                },
              ),

              _buildSettingsTile(
                Icons.block_rounded,
                'Blocked Users',
                const Color(0xFFE57373),
                onTap: () {
                  // Capture the navigator before popping — `context` here belongs
                  // to the sheet and is disposed once it closes, so it can't be
                  // used to push after the delay below.
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  Future.delayed(
                    const Duration(milliseconds: 300),
                    () {
                      navigator.push(
                        MaterialPageRoute(
                          builder: (_) => const BlockedUsersPage(),
                        ),
                      );
                    },
                  );
                },
              ),
              _buildSettingsTile(
                Icons.gavel_rounded,
                'Terms of Service',
                const Color(0xFF6C5CE7),
                onTap: () => _openLegalDocument(
                  context,
                  LegalContent.termsOfService,
                  Icons.gavel_rounded,
                ),
              ),
              _buildSettingsTile(
                Icons.privacy_tip_rounded,
                'Privacy Policy',
                const Color(0xFF4ECDC4),
                onTap: () => _openLegalDocument(
                  context,
                  LegalContent.privacyPolicy,
                  Icons.privacy_tip_rounded,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Pushes a full-page legal document (ToS / Privacy Policy).
  void _openLegalDocument(
    BuildContext context,
    LegalDocument document,
    IconData icon,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LegalDocumentPage(document: document, icon: icon),
      ),
    );
  }

  /// Confirmation dialog for permanent account deletion.
  ///
  /// Requires the user to type their email address and (for email/password
  /// accounts) their password. The password is only used to reauthenticate
  /// via [AuthService.deleteAccount] — it is never stored. All server-side
  /// data removal happens in the `deleteUserAccount` Cloud Function.
  void _showDeleteAccountDialog() {
    final authService = context.read<AuthService>();
    final user = authService.currentUser;
    final userEmail = user?.email?.trim().toLowerCase() ?? '';
    final hasEmailProvider =
        user?.providerData.any((p) => p.providerId == 'password') ?? false;

    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    bool isDeleting = false;
    String? errorMessage;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          bool isFormValid() {
            final emailMatches =
                emailController.text.trim().toLowerCase() == userEmail &&
                userEmail.isNotEmpty;
            final passwordOk =
                !hasEmailProvider || passwordController.text.isNotEmpty;
            return emailMatches && passwordOk;
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFE57373),
                ),
                const SizedBox(width: 8),
                Text(
                  'Delete Account',
                  style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Color(0xFFE57373).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Color(0xFFE57373).withValues(alpha: 0.5),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      'This will permanently delete your account and ALL your '
                      'data — progress, coins, imports, and content. This '
                      'action cannot be undone.',
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFE57373),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red, width: 1),
                      ),
                      child: Text(
                        errorMessage!,
                        style: GoogleFonts.nunito(
                          fontSize: 12,
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    'Type your email to confirm:',
                    style: GoogleFonts.nunito(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Email',
                      hintText: user?.email ?? '',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      errorText: emailController.text.isNotEmpty &&
                              emailController.text.trim().toLowerCase() !=
                                  userEmail
                          ? 'Email does not match your account'
                          : null,
                    ),
                  ),
                  if (hasEmailProvider) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Enter your password to confirm:',
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'Need help? Contact badyaapp@gmail.com',
                    style: GoogleFonts.nunito(
                      fontSize: 11,
                      color: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isDeleting
                    ? null
                    : () {
                        Navigator.pop(dialogContext);
                      },
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: isDeleting || !isFormValid()
                    ? null
                    : () async {
                        setState(() {
                          isDeleting = true;
                          errorMessage = null;
                        });
                        try {
                          await authService.deleteAccount(
                            password: hasEmailProvider
                                ? passwordController.text.trim()
                                : null,
                          );
                          // AuthWrapper in main.dart routes back to login
                          // automatically via the auth state stream — the
                          // whole subtree (incl. this dialog) unmounts, so
                          // show the confirmation through the root navigator.
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop();
                          }
                          final rootContext =
                              NotificationService.navigatorKey.currentContext;
                          if (rootContext != null) {
                            UiUtils.showTopNotification(
                              rootContext,
                              'Account deleted successfully',
                              type: NotificationType.success,
                            );
                          }
                          // Return to the root route (AuthWrapper), which reactively
                          // switches to LoginPage now that the user is deleted/signed out.
                          NotificationService.navigatorKey.currentState
                              ?.popUntil((route) => route.isFirst);
                        } on FirebaseAuthException catch (e) {
                          setState(() {
                            isDeleting = false;
                            errorMessage = _mapDeleteAccountError(e);
                          });
                        } catch (e) {
                          setState(() {
                            isDeleting = false;
                            errorMessage =
                                'Could not delete account: ${e.toString()}';
                          });
                        }
                      },
                child: isDeleting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        'Delete Account',
                        style: TextStyle(
                          color: isFormValid()
                              ? const Color(0xFFE57373)
                              : Colors.grey,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _mapDeleteAccountError(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect password. Please try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again.';
      case 'user-not-found':
      case 'user-disabled':
        return 'This account no longer exists.';
      case 'requires-recent-login':
        return 'Please sign in again before deleting your account.';
      case 'network-request-failed':
        return 'Network error. Please check your connection and try again.';
      default:
        return e.message ?? 'Account deletion failed. Please try again.';
    }
  }



  Future<void> _sendFeedback() async {
    _feedbackController.clear();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return CustomDialog(
          title: 'Send Feedback',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your feedback helps us make Badya better for everyone.',
                style: GoogleFonts.nunito(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(dialogContext)
                      .textTheme
                      .bodyMedium
                      ?.color
                      ?.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _feedbackController,
                maxLines: 4,
                // Mirrors the `feedback.description` size cap in
                // firestore.rules — keep in sync so the rules never reject
                // text a user can actually type.
                maxLength: 2000,
                style: GoogleFonts.nunito(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'How can we improve?',
                  hintStyle: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(dialogContext)
                        .textTheme
                        .bodyMedium
                        ?.color
                        ?.withValues(alpha: 0.4),
                  ),
                  filled: true,
                  fillColor: Theme.of(dialogContext)
                      .textTheme
                      .bodyMedium
                      ?.color
                      ?.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: Theme.of(dialogContext)
                          .dividerColor
                          .withValues(alpha: 0.2),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: Theme.of(dialogContext)
                          .dividerColor
                          .withValues(alpha: 0.2),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(
                      color: Color(0xFFFF6B6B),
                      width: 1.5,
                    ),
                  ),
                  contentPadding: const EdgeInsets.all(16),
                  counterStyle: GoogleFonts.nunito(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(dialogContext)
                        .textTheme
                        .bodyMedium
                        ?.color
                        ?.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ),
          cancelButtonText: 'Cancel',
          saveButtonText: 'Send',
          saveButtonColor: const Color(0xFFFF6B6B),
          onCancel: () {
            Navigator.of(dialogContext).pop();
          },
          onSave: () async {
            final text = _feedbackController.text.trim();
            if (text.isEmpty) {
              UiUtils.showTopNotification(
                context,
                'Please enter some feedback before sending.',
                type: NotificationType.error,
              );
              return;
            }

            Navigator.of(dialogContext).pop();

            try {
              await UserPreferencesService().submitIssueReport(
                'App feedback',
                text,
              );

              if (!mounted) return;
              UiUtils.showTopNotification(
                context,
                'Thank you for your feedback!',
                type: NotificationType.success,
              );
            } catch (e) {
              if (!mounted) return;
              UiUtils.showTopNotification(
                context,
                'Could not send your feedback. Please check your internet connection and try again.',
                type: NotificationType.error,
              );
            }
          },
        );
      },
    );
  }

  Widget _buildSettingsTile(
    IconData icon,
    String title,
    Color color, {
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(
          title,
          style: GoogleFonts.nunito(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
        trailing:
            trailing ??
            const Icon(Icons.chevron_right_rounded, color: Color(0xFFB2BEC3)),
        onTap: onTap,
      ),
    );
  }
}
