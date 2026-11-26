import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:Badya/utils/language_service.dart';
import 'package:Badya/utils/logger.dart';

class TranslationDialog extends StatefulWidget {
  final String initialText;
  final String? sourceLanguage;
  final String? targetLanguage;

  const TranslationDialog({
    super.key,
    required this.initialText,
    this.sourceLanguage,
    this.targetLanguage,
  });

  static void show(
    BuildContext context,
    String text, {
    String? sourceLanguage,
    String? targetLanguage,
  }) {
    showDialog(
      context: context,
      builder: (context) => TranslationDialog(
        initialText: text,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
      ),
    );
  }

  @override
  State<TranslationDialog> createState() => _TranslationDialogState();
}

class _TranslationDialogState extends State<TranslationDialog> {
  late TextEditingController _controller;
  String _translatedText = '';
  String _lastTranslatedText = '';
  bool _isLoading = false;
  bool _hasAttemptedInitial = false;
  final LanguageService _languageService = LanguageService();
  late String _targetLanguage;
  String _lastTranslatedLanguage = '';
  final List<String> _availableLanguages = [
    'Arabic',
    'English',
    'French',
    'German',
    'Italian',
    'Japanese',
    'Chinese',
    'Russian',
    'Portuguese',
  ];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _targetLanguage = widget.targetLanguage ?? 'Arabic';

    // Ensure translation starts after the dialog is built with a slight delay
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_hasAttemptedInitial) {
        Logger.info('Starting initial translation for: ${widget.initialText}');
        _performTranslation();
        _hasAttemptedInitial = true;
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _performTranslation() async {
    final currentText = _controller.text.trim();
    if (currentText.isEmpty) {
      Logger.info('Translation skipped: empty text');
      return;
    }

    // Check if text has changed OR target language changed to avoid redundant API calls
    if (currentText == _lastTranslatedText && 
        _translatedText.isNotEmpty && 
        _targetLanguage == _lastTranslatedLanguage) {
      Logger.info('Translation skipped: text and language unchanged');
      return;
    }

    Logger.info('Performing translation for: $currentText');

    // Hide keyboard if it's open
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _languageService.translate(
        currentText,
        sourceLang: widget.sourceLanguage,
        targetLang: _targetLanguage,
      );
      Logger.info('Translation successful: $result');
      if (mounted) {
        setState(() {
          _translatedText = result;
          _lastTranslatedText = currentText;
          _lastTranslatedLanguage = _targetLanguage;
          _isLoading = false;
        });
      }
    } catch (e) {
      Logger.error('Translation failed in Dialog', e);
      if (mounted) {
        setState(() {
          _translatedText = 'Error: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Theme-aware colors from CustomDialog
    final backgroundColor = isDark
        ? Theme.of(context).cardTheme.color ?? const Color(0xFF2D3436)
        : const Color(0xfff9f2d8);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.2)
        : const Color(0xFF2D3436);
    final titleColor = isDark ? Colors.white : const Color(0xFF2D3436);
    final labelColor = isDark ? Colors.white70 : const Color(0xFF636E72);
    final boxBg = isDark ? Colors.black26 : Colors.white54;

    return Dialog(
      backgroundColor: backgroundColor,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: borderColor, width: isDark ? 1 : 3),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
          maxWidth: 500,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Translation',
                    style: GoogleFonts.merriweather(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: titleColor,
                    ),
                  ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.language_rounded, color: labelColor),
                    tooltip: 'Target Language',
                    initialValue: _targetLanguage,
                    color: backgroundColor,
                    elevation: 8,
                    offset: const Offset(0, 45),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: borderColor, width: 2),
                    ),
                    onSelected: (String lang) {
                      setState(() {
                        _targetLanguage = lang;
                      });
                      _performTranslation();
                    },
                    itemBuilder: (context) => _availableLanguages.map((lang) {
                      return PopupMenuItem<String>(
                        value: lang,
                        child: Row(
                          children: [
                            if (lang == _targetLanguage)
                              const Icon(Icons.check_rounded, 
                                   size: 18, 
                                   color: Color(0xFF4ECDC4)),
                            if (lang == _targetLanguage)
                              const SizedBox(width: 8),
                            Text(
                              lang,
                              style: GoogleFonts.nunito(
                                fontWeight: lang == _targetLanguage 
                                    ? FontWeight.bold 
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: labelColor),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Origin Section
                    _buildSectionLabel('Original Text', labelColor),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: boxBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: borderColor.withValues(alpha: 0.3),
                        ),
                      ),
                      child: TextField(
                        controller: _controller,
                        maxLines: null,
                        style: GoogleFonts.nunito(
                          fontSize: 16,
                          color: titleColor,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Enter text to translate...',
                          contentPadding: const EdgeInsets.all(16),
                          border: InputBorder.none,
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Divider / Half marker
                    Row(
                      children: [
                        Expanded(
                          child: Divider(
                            color: borderColor.withValues(alpha: 0.2),
                            thickness: 2,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Tooltip(
                            message: 'Refresh Translation',
                            child: InkWell(
                              onTap: _performTranslation,
                              borderRadius: BorderRadius.circular(30),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4ECDC4),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.white24
                                        : const Color(0xFF2D3436),
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Color(
                                        0xFF4ECDC4,
                                      ).withValues(alpha: 0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.swap_vert_rounded,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF2D3436),
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(
                            color: borderColor.withValues(alpha: 0.2),
                            thickness: 2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Translation Section
                    _buildSectionLabel('Translation', labelColor),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(minHeight: 100),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Color(0xFF4ECDC4).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Color(0xFF4ECDC4).withValues(alpha: 0.3),
                          width: 2,
                        ),
                      ),
                      child: Stack(
                        children: [
                          if (_isLoading)
                            const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF4ECDC4),
                              ),
                            )
                          else
                            SelectableText(
                              _translatedText,
                              style: GoogleFonts.nunito(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: titleColor,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label, Color color) {
    return Text(
      label.toUpperCase(),
      style: GoogleFonts.nunito(
        fontSize: 12,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.2,
        color: color,
      ),
    );
  }
}
