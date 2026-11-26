import 'dart:ui';
import 'package:Badya/utils/constants.dart';
import 'package:Badya/widgets/custom_dialog.dart';
import 'package:Badya/services/language_manager.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class ManageLanguagesPage extends StatefulWidget {
  const ManageLanguagesPage({super.key});

  @override
  State<ManageLanguagesPage> createState() => _ManageLanguagesPageState();
}

class _ManageLanguagesPageState extends State<ManageLanguagesPage> {
  String _currentLanguage = 'English';
  String _nativeLanguage = 'Arabic';
  List<String> _myLanguages = ['English'];

  late final List<String> _availableLanguages = languageCodes.keys.toList()
    ..sort(
      (a, b) => getLanguageDisplayName(a).compareTo(getLanguageDisplayName(b)),
    );

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Sync with LanguageManager to ensure we have the latest values
    final languageManager = context.read<LanguageManager>();
    setState(() {
      _currentLanguage = languageManager.currentLanguage;
      _nativeLanguage = languageManager.nativeLanguage;
      _myLanguages = List<String>.from(languageManager.myLanguages);
    });
  }

  Future<void> _loadPreferences() async {
    final languageManager = context.read<LanguageManager>();

    setState(() {
      _currentLanguage = languageManager.currentLanguage;
      _nativeLanguage = languageManager.nativeLanguage;
      _myLanguages = List<String>.from(languageManager.myLanguages);
    });
  }

  void _addLanguage(String language) {
    if (!_myLanguages.contains(language)) {
      final languageManager = context.read<LanguageManager>();
      languageManager.addLanguage(language);
      setState(() {
        _myLanguages.add(language);
      });
    }
  }

  void _removeLanguage(String language) {
    if (_myLanguages.length > 1) {
      showDialog(
        context: context,
        builder: (context) => CustomDialog(
          title: 'Remove Language',
          content: Text(
            'Are you sure you want to remove $language? Your progress will stay safe, but hidden from the dashboard.',
            style: GoogleFonts.nunito(fontSize: 16),
          ),
          onCancel: () => Navigator.pop(context),
          onSave: () async {
            // Read dependencies and check whether the removed language is active
            // before popping so we don't access a deactivated dialog BuildContext.
            final languageManager = context.read<LanguageManager>();
            final wasCurrentLanguage = _currentLanguage == language;

            // Close dialog immediately so UI never hangs offline.
            Navigator.pop(context);
            if (!mounted) return;

            setState(() {
              _myLanguages.remove(language);
              if (wasCurrentLanguage && _myLanguages.isNotEmpty) {
                _currentLanguage = _myLanguages.first;
              }
            });

            try {
              await languageManager.removeLanguage(language);
            } catch (_) {
              // Offline / network error — local state already applied.
            }
          },
          saveButtonText: 'Remove',
          saveButtonColor: const Color(0xFFFF6B6B),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: isDark ? Colors.white : const Color(0xFF2D3436),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          Positioned(
            top: -100,
            right: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Color(
                      0xFF4ECDC4,
                    ).withValues(alpha: isDark ? 0.15 : 0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          SingleChildScrollView(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 70,
              left: 24,
              right: 24,
              bottom: 40,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Native Language',
                  style: GoogleFonts.merriweather(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Theme.of(context).textTheme.titleLarge?.color,
                  ),
                ),
                const SizedBox(height: 16),
                _buildIdentityPassport(),
                const SizedBox(height: 48),

                Row(
                  children: [
                    Text(
                      'Languages',
                      style: GoogleFonts.merriweather(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Theme.of(context).textTheme.titleLarge?.color,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Color(0xFF4ECDC4).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_myLanguages.length}',
                        style: GoogleFonts.nunito(
                          fontSize: 16,
                          color: const Color(0xFF4ECDC4),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                ..._myLanguages.map((lang) => _buildLanguageCard(lang)),

                const SizedBox(height: 24),
                _buildAddLanguageButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentityPassport() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D3436) : const Color(0xFFF9F9F9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Color(0xFFB2BEC3).withValues(alpha: 0.2),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Color(0xFF4ECDC4).withValues(alpha: 0.5),
                    width: 2,
                  ),
                ),
                child: ClipOval(
                  child: CountryFlag.fromCountryCode(
                    languageCodes[_nativeLanguage] ?? 'US',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      getLanguageDisplayName(_nativeLanguage),
                      style: GoogleFonts.merriweather(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Theme.of(context).textTheme.titleLarge?.color,
                      ),
                    ),
                    Text(
                      'Native',
                      style: GoogleFonts.nunito(
                        color: const Color(0xFF4ECDC4),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _selectNativeLanguage,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Color(0xFF4ECDC4).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.sync_rounded,
                    color: Color(0xFF4ECDC4),
                    size: 18,
                  ),
                ),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageCard(String language) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).cardTheme.color?.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Color(0xFFB2BEC3).withValues(alpha: 0.2),
                    width: 2,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Color(
                              0xFFB2BEC3,
                            ).withValues(alpha: 0.4),
                            width: 2,
                          ),
                        ),
                        child: ClipOval(
                          child: CountryFlag.fromCountryCode(
                            languageCodes[language] ?? 'US',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          getLanguageDisplayName(language),
                          maxLines: 2,
                          softWrap: true,
                          overflow: TextOverflow.visible,
                          style: GoogleFonts.merriweather(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Theme.of(
                              context,
                            ).textTheme.titleMedium?.color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => _removeLanguage(language),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Color(0xFFE57373).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            color: Color(0xFFE57373),
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn().slideX(begin: 0.1);
  }

  Widget _buildAddLanguageButton() {
    return InkWell(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SelectionPage(
              title: 'Add Language',
              availableLanguages: _availableLanguages
                  .where((l) => !_myLanguages.contains(l))
                  .toList(),
            ),
          ),
        );
        if (result != null && result is Map) {
          _addLanguage(result['language']);
        }
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Color(0xFF4ECDC4).withValues(alpha: 0.08),
          border: Border.all(
            color: Color(0xFF4ECDC4).withValues(alpha: 0.2),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add_rounded, color: Color(0xFF4ECDC4), size: 20),
            const SizedBox(width: 8),
            Text(
              'ADD LANGUAGE',
              style: GoogleFonts.nunito(
                fontSize: 13,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF4ECDC4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _selectNativeLanguage() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SelectionPage(
          title: 'Native Language',
          availableLanguages: _availableLanguages,
          selectedLanguage: _nativeLanguage,
        ),
      ),
    );
    if (result != null && result is Map) {
      setState(() => _nativeLanguage = result['language']);
      // TODO: Add updateNativeLanguage method to LanguageManager if needed
    }
  }
}

class SelectionPage extends StatefulWidget {
  final String title;
  final List<String> availableLanguages;
  final String? selectedLanguage;

  const SelectionPage({
    super.key,
    required this.title,
    required this.availableLanguages,
    this.selectedLanguage,
  });

  @override
  State<SelectionPage> createState() => _SelectionPageState();
}

class _SelectionPageState extends State<SelectionPage> {
  String? _tempSelected;

  @override
  void initState() {
    super.initState();
    _tempSelected = widget.selectedLanguage;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 120,
                floating: false,
                pinned: true,
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  expandedTitleScale: 1.15,
                  titlePadding: const EdgeInsets.only(left: 60, bottom: 16),
                  title: Text(
                    widget.title,
                    style: GoogleFonts.merriweather(
                      fontWeight: FontWeight.w900,
                      color: Theme.of(context).textTheme.titleLarge?.color,
                    ),
                  ),
                ),
              ),

              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final lang = widget.availableLanguages[index];
                    final isSelected = lang == _tempSelected;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _tempSelected = lang;
                          });
                          Navigator.pop(context, {'language': lang});
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Color(
                                    0xFF4ECDC4,
                                  ).withValues(alpha: 0.1)
                                : Theme.of(context).cardTheme.color,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF4ECDC4)
                                  : Color(
                                      0xFFB2BEC3,
                                    ).withValues(alpha: 0.15),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected
                                        ? const Color(0xFF4ECDC4)
                                        : Color(
                                            0xFFB2BEC3,
                                          ).withValues(alpha: 0.3),
                                    width: 1.5,
                                  ),
                                ),
                                child: ClipOval(
                                  child: CountryFlag.fromCountryCode(
                                    languageCodes[lang] ?? 'US',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  getLanguageDisplayName(lang),
                                  maxLines: 2,
                                  softWrap: true,
                                  overflow: TextOverflow.visible,
                                  style: GoogleFonts.merriweather(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: isSelected
                                        ? const Color(0xFF4ECDC4)
                                        : null,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              if (isSelected)
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: Color(0xFF4ECDC4),
                                )
                              else
                                const Icon(
                                  Icons.add_circle_outline_rounded,
                                  color: Color(0xFFB2BEC3),
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }, childCount: widget.availableLanguages.length),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        ],
      ),
    );
  }
}
