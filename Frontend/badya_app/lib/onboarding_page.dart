import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:Badya/main_shell_page.dart';
import 'package:Badya/services/firebase_storage_service.dart';
import 'package:Badya/config/local_mode.dart';
import 'package:Badya/utils/logger.dart';
import 'package:Badya/utils/constants.dart';
import 'package:Badya/utils/legal_content.dart';
import 'package:Badya/utils/profile_images.dart';
import 'package:Badya/utils/ui_utils.dart';
import 'package:image_picker/image_picker.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  int _currentStep = 0;
  final TextEditingController _displayNameController = TextEditingController();
  String? _photoUrl;
  bool _isUploading = false;
  bool _isCompleting = false;
  // Pre-select the native language from the device locale (a French user sees
  // French chosen), falling back to the app's previous default when the
  // device language isn't supported.
  String _nativeLanguage = resolveDefaultNativeLanguage();
  final List<String> _learningLanguages = [];
  final Map<String, String> _learningDialects = {};
  final TextEditingController _languageSearchController =
      TextEditingController();
  String _languageSearchQuery = '';

  // Full list of supported languages from constants.dart — keeps the flags
  // mapped correctly (e.g. 'Chinese, Mandarin' → CN) and in sync with the
  // rest of the app (manage_languages_page sorts the same way).
  late final List<String> _availableLanguages = languageCodes.keys.toList()
    ..sort(
      (a, b) => getLanguageDisplayName(a).compareTo(getLanguageDisplayName(b)),
    );

  List<String> get _filteredLanguages {
    final query = _languageSearchQuery.trim().toLowerCase();
    if (query.isEmpty) return _availableLanguages;
    return _availableLanguages.where((lang) {
      return lang.toLowerCase().contains(query) ||
          getLanguageDisplayName(lang).toLowerCase().contains(query);
    }).toList();
  }

  /// Picks the native-language default from the device's region/locale,
  /// defaulting to 'Arabic' when it isn't one of the supported languages.
  static String resolveDefaultNativeLanguage() {
    final code = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    return languageFromBcp47Code(code) ?? 'Arabic';
  }

  @override
  void initState() {
    super.initState();
    final user = LocalMode.enabled ? null : FirebaseAuth.instance.currentUser;
    if (user != null) {
      _displayNameController.text = user.displayName ?? '';
      _photoUrl = user.photoURL;
    }
    // Pick a random profile avatar and upload it as the initial photo
    _assignRandomAvatar();
  }

  void _assignRandomAvatar() {
    if (_photoUrl != null) return; // Already has a photo
    setState(() => _photoUrl = getRandomProfileImagePath());
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _languageSearchController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    try {
      final XFile? image = await picker.pickImage(
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
          setState(() {
            _photoUrl = url;
            _isUploading = false;
          });
        } else {
          setState(() => _isUploading = false);
        }
      }
    } catch (e) {
      Logger.error('Error picking image', e);
      setState(() => _isUploading = false);
    }
  }

  Future<void> _completeOnboarding() async {
    if (_isCompleting) return;
    setState(() => _isCompleting = true);

    final prefs = await SharedPreferences.getInstance();
    final user = LocalMode.enabled ? null : FirebaseAuth.instance.currentUser;
    final String uid = LocalMode.enabled
        ? LocalMode.guestUid
        : (user?.uid ?? 'default_user');

    final displayName = _displayNameController.text.trim();

    try {
      // Auth profile update and Firestore write are independent — run
      // them in parallel to cut the total wait time roughly in half.
      await Future.wait([
        // Firebase Auth profile (best-effort, non-critical)
        () async {
          try {
            if (displayName.isNotEmpty) {
              await user?.updateDisplayName(displayName);
            }
            if (_photoUrl != null) {
              await user?.updatePhotoURL(_photoUrl);
            }
          } catch (e) {
            Logger.error('Error updating Firebase Auth profile', e);
          }
        }(),
        // Firestore document (source of truth)
        if (!LocalMode.enabled)
          FirebaseFirestore.instance.collection('users').doc(uid).set({
          'display_name': displayName,
          'display_name_lowercase': displayName.toLowerCase(),
          'photo_url': _photoUrl,
          'native_language': _nativeLanguage,
          'current_language': _learningLanguages.isNotEmpty
              ? _learningLanguages.first
              : 'English',
          'my_languages': _learningLanguages.isEmpty
              ? ['English']
              : _learningLanguages,
          'learning_dialects': _learningDialects,
          'is_public': true,
          'profile_visibility': {
            'show_xp': true,
            'show_level': true,
            'show_streak': true,
            'show_coins': false,
            'show_achievements': true,
            'show_languages': true,
            'show_following': true,
            'show_stats': true,
          },
          'is_onboarded': true,
          // ToS / Privacy Policy acceptance — required at signup, recorded once
          // here so it survives the email-verification step for email accounts
          // and covers Google sign-ups too (both land on onboarding first).
          'tos_accepted_at': FieldValue.serverTimestamp(),
          'tos_version': LegalContent.version,
          'created_at': FieldValue.serverTimestamp(),
          'last_updated': FieldValue.serverTimestamp(),
          'total_xp': 0,
          'streak': 0,
        }, SetOptions(merge: true)).timeout(const Duration(seconds: 10)),
      ]);

      // Mark onboarded locally for fast startup on next launch.
      await prefs.setBool('is_onboarded_$uid', true);
      // Signal MainShellPage to claim the starter bonus and show the
      // celebration overlay on first launch after onboarding.
      await prefs.setBool('pending_starter_celebration', true);
    } catch (e) {
      Logger.error('Error saving user to Firestore', e);
      if (mounted) setState(() => _isCompleting = false);
      // If Firestore fails, we don't mark as onboarded to force retry.
      rethrow;
    }

    // Navigate to the main app — MainShellPage will claim the starter
    // bonus and show the celebration overlay on its own.
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MainShellPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildBackground(),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                _buildProgressBar(),
                Expanded(
                  child: _currentStep == 0
                      ? _buildProfileStep()
                      : (_currentStep == 1
                          ? _buildNativeLanguageStep()
                          : _buildLearningLanguagesStep()),
                ),
                _buildBottomNav(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF1E272E), const Color(0xFF0F1419)]
              : [const Color(0xFFF7F9FB), const Color(0xFFE3E9F1)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -100,
            left: -50,
            child: _buildBlob(
              Color(0xFFF78B1E).withValues(alpha: 0.1),
              300,
            ),
          ),
          Positioned(
            bottom: -50,
            right: -50,
            child: _buildBlob(
              Color(0xFF4ECDC4).withValues(alpha: 0.1),
              250,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlob(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        children: [
          Expanded(child: _buildProgressSegment(0)),
          const SizedBox(width: 12),
          Expanded(child: _buildProgressSegment(1)),
          const SizedBox(width: 12),
          Expanded(child: _buildProgressSegment(2)),
        ],
      ),
    );
  }

  Widget _buildProgressSegment(int index) {
    final isActive = _currentStep >= index;
    return AnimatedContainer(
      duration: 500.ms,
      height: 6,
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xFFF78B1E)
            : Colors.grey.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }

  Widget _buildProfileStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Let's set up your\nprofile",
            style: GoogleFonts.merriweather(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ).animate().fadeIn().slideX(),
          const SizedBox(height: 12),
          Text(
            "Tell us your name and add a photo so others can recognize you.",
            style: GoogleFonts.nunito(fontSize: 16, color: Colors.grey[600]),
          ).animate().fadeIn(delay: 200.ms).slideX(),
          const SizedBox(height: 40),
          Center(
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                GestureDetector(
                  onTap: _isUploading ? null : _pickImage,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.grey[200],
                      border: Border.all(
                        color: const Color(0xFFF78B1E),
                        width: 4,
                      ),                          image: DecorationImage(
                            image: resolveProfileImage(_photoUrl),
                            fit: BoxFit.cover,
                          ),
                    ),
                    child: _isUploading
                        ? const Center(child: CircularProgressIndicator())
                        : (_photoUrl == null
                            ? const Icon(Icons.person_rounded,
                                size: 60, color: Colors.grey)
                            : null),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF78B1E),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.camera_alt_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 400.ms).scale(),
          const SizedBox(height: 40),
          TextField(
            controller: _displayNameController,
            style: GoogleFonts.nunito(fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              labelText: 'Display Name',
              hintText: 'Enter your name',
              prefixIcon: const Icon(Icons.person_outline_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(color: Color(0xFFF78B1E), width: 2),
              ),
            ),
          ).animate().fadeIn(delay: 600.ms).slideY(begin: 0.2, end: 0),
        ],
      ),
    );
  }

  Widget _buildNativeLanguageStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "What's your native\nlanguage?",
            style: GoogleFonts.merriweather(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ).animate().fadeIn().slideX(),
          const SizedBox(height: 12),
          Text(
            "We'll use this to help you translate and learn faster.",
            style: GoogleFonts.nunito(fontSize: 16, color: Colors.grey[600]),
          ).animate().fadeIn(delay: 200.ms).slideX(),
          const SizedBox(height: 32),
          _buildLanguageSearchField(),
          const SizedBox(height: 16),
          if (_filteredLanguages.isEmpty)
            _buildNoLanguagesFound()
          else
            ..._filteredLanguages.map(
              (lang) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildLanguageRow(lang, true),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLearningLanguagesStep() {
    final filtered =
        _filteredLanguages.where((l) => l != _nativeLanguage).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "What do you want\nto learn?",
            style: GoogleFonts.merriweather(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ).animate().fadeIn().slideX(),
          const SizedBox(height: 12),
          Text(
            "Select one or more languages to master.",
            style: GoogleFonts.nunito(fontSize: 16, color: Colors.grey[600]),
          ).animate().fadeIn(delay: 200.ms).slideX(),
          const SizedBox(height: 32),
          _buildLanguageSearchField(),
          const SizedBox(height: 16),
          if (filtered.isEmpty)
            _buildNoLanguagesFound()
          else
            ...filtered.map(
              (lang) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildLanguageRow(lang, false),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLanguageRow(String lang, bool isNativeStep) {
    final isSelected = isNativeStep
        ? _nativeLanguage == lang
        : _learningLanguages.contains(lang);

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isNativeStep) {
            _nativeLanguage = lang;
          } else {
            if (_learningLanguages.contains(lang)) {
              _learningLanguages.remove(lang);
            } else {
              _learningLanguages.add(lang);
            }
          }
        });
      },
      child: AnimatedContainer(
        duration: 300.ms,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? Color(0xFFF78B1E).withValues(alpha: 0.1)
              : Colors.white.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFF78B1E)
                : Colors.grey.withValues(alpha: 0.2),
            width: 2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Color(0xFFF78B1E).withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: ClipOval(
                child: CountryFlag.fromCountryCode(languageCodes[lang] ?? 'US'),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                getLanguageDisplayName(lang),
                style: GoogleFonts.nunito(
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                  color: isSelected ? const Color(0xFFF78B1E) : Colors.black87,
                ),
              ),
            ),
            Icon(
              isSelected
                  ? Icons.check_circle_rounded
                  : Icons.circle_outlined,
              color: isSelected
                  ? const Color(0xFFF78B1E)
                  : Colors.grey.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 100.ms);
  }

  Widget _buildLanguageSearchField() {
    return TextField(
      controller: _languageSearchController,
      onChanged: (value) => setState(() => _languageSearchQuery = value),
      style: GoogleFonts.nunito(fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        hintText: 'Search languages',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _languageSearchQuery.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear_rounded),
                onPressed: () {
                  _languageSearchController.clear();
                  setState(() => _languageSearchQuery = '');
                },
              ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0xFFF78B1E), width: 2),
        ),
      ),
    );
  }

  Widget _buildNoLanguagesFound() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          'No languages found',
          style: GoogleFonts.nunito(fontSize: 16, color: Colors.grey[600]),
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_currentStep > 0)
            TextButton(
              onPressed: () => setState(() => _currentStep--),
              child: Text(
                'Back',
                style: GoogleFonts.nunito(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey,
                ),
              ),
            )
          else
            const SizedBox.shrink(),
          ElevatedButton(
            onPressed: _isCompleting
                ? null
                : () {
                    if (_currentStep < 2) {
                      if (_currentStep == 0 &&
                          _displayNameController.text.trim().isEmpty) {
                        UiUtils.showTopNotification(
                          context,
                          'Please enter your display name',
                          type: NotificationType.error,
                        );
                        return;
                      }
                      setState(() => _currentStep++);
                    } else {
                      if (_learningLanguages.isEmpty) {
                        UiUtils.showTopNotification(
                          context,
                          'Please select at least one language to learn',
                          type: NotificationType.error,
                        );
                      } else {
                        _completeOnboarding();
                      }
                    }
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF78B1E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 4,
            ),
            child: _isCompleting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    _currentStep == 0 ? 'Next' : 'Get Started',
                    style: GoogleFonts.nunito(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
