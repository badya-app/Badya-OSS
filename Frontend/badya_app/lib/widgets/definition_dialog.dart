import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:Badya/utils/language_service.dart';
import 'package:Badya/services/user_preferences_service.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class DefinitionDialog extends StatefulWidget {
  final String text;
  final String? sourceLanguage;
  final String? targetLanguage;

  final String? sessionId;
  final String? userId;

  const DefinitionDialog({
    super.key,
    required this.text,
    this.sourceLanguage,
    this.targetLanguage,
    this.sessionId,
    this.userId,
  });

  static void show(
    BuildContext context,
    String text, {
    String? sourceLanguage,
    String? targetLanguage,
    String? sessionId,
    String? userId,
  }) {
    showDialog(
      context: context,
      builder: (context) => DefinitionDialog(
        text: text,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
        sessionId: sessionId,
        userId: userId,
      ),
    );
  }

  @override
  State<DefinitionDialog> createState() => _DefinitionDialogState();
}

class _DefinitionDialogState extends State<DefinitionDialog> {
  final LanguageService _languageService = LanguageService();
  final UserPreferencesService _prefs = UserPreferencesService();
  Stream<String>? _definitionStream;
  String _currentDefinition = '';
  bool _isUsingAgent = false;

  @override
  void initState() {
    super.initState();
    _startDefinition();
  }

  Future<void> _startDefinition() async {
    final nativeLang = widget.targetLanguage ?? await _prefs.getNativeLanguage();
    final learningLang = widget.sourceLanguage ?? await _prefs.getCurrentLanguage();
    
    // We try to use the definition agent if we can get a session
    // In a dialog context, we might not have a session ID passed in, 
    // so we rely on LanguageService to handle the fallback or session creation.
    
    setState(() {
      _definitionStream = _languageService.define(
        widget.text,
        sessionId: widget.sessionId,
        userId: widget.userId,
        targetLanguage: nativeLang,
        sourceLanguage: learningLang,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark
        ? Theme.of(context).cardTheme.color ?? const Color(0xFF2D3436)
        : const Color(0xfff9f2d8);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.2)
        : const Color(0xFF2D3436);
    final titleColor = isDark ? Colors.white : const Color(0xFF2D3436);
    final labelColor = isDark ? Colors.white70 : const Color(0xFF636E72);

    return Dialog(
      backgroundColor: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: borderColor, width: isDark ? 1 : 3),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
          maxWidth: 450,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Definition',
                    style: GoogleFonts.merriweather(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: titleColor,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: labelColor),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.text,
                      style: GoogleFonts.nunito(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1ABC9C),
                      ),
                    ),
                    const SizedBox(height: 16),
                    StreamBuilder<String>(
                      stream: _definitionStream,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(20.0),
                              child: CircularProgressIndicator(
                                color: Color(0xFF1ABC9C),
                                strokeWidth: 2,
                              ),
                            ),
                          );
                        }

                        if (snapshot.hasError) {
                          return Text(
                            'Error loading definition: ${snapshot.error}',
                            style: GoogleFonts.nunito(color: Colors.red),
                          );
                        }

                        final content = snapshot.data ?? '';
                        if (content.isEmpty && snapshot.connectionState == ConnectionState.done) {
                          return Text(
                            'No definition found.',
                            style: GoogleFonts.nunito(color: labelColor),
                          );
                        }

                        return MarkdownBody(
                          data: content,
                          styleSheet: MarkdownStyleSheet(
                            p: GoogleFonts.nunito(
                              fontSize: 16,
                              color: titleColor,
                              height: 1.5,
                            ),
                            strong: GoogleFonts.nunito(
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF1ABC9C),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
