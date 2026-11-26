import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/import_service.dart';
import '../services/language_manager.dart';
import '../utils/ui_utils.dart';
import 'custom_dialog.dart';
import 'tag_selector.dart';
import 'ai_generation_form.dart';
import 'segmentation_selector.dart';

class ImportDialog extends StatefulWidget {
  final String? preselectedSectionId;
  final String importType; // 'video', 'file', or 'all'
  final String? sharedUrl;
  final String? sharedFilePath;
  const ImportDialog({
    super.key,
    this.preselectedSectionId,
    this.importType = 'all',
    this.sharedUrl,
    this.sharedFilePath,
  });

  @override
  State<ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<ImportDialog>
    with SingleTickerProviderStateMixin {
  final _titleController = TextEditingController();
  final _urlController = TextEditingController();
  final _fileController = TextEditingController();
  final _rawTextController = TextEditingController();
  bool _isLoading = false;
  bool _isFetchingMetadata = false;
  final ImportService _importService = ImportService();
  List<String> _tags = [];
  String _selectedLanguage = 'English';
  bool _isPublic = true;
  Map<String, String>? _videoMetadata;
  Timer? _debounce;

  late FocusNode _titleFocusNode;
  late FocusNode _urlFocusNode;
  late FocusNode _fileFocusNode;

  String? _titleError;
  String? _urlError;
  String? _fileError;
  String? _rawTextError;

  int _currentStep = 0;
  String? _sourceType; // 'video', 'file', 'text', 'url', 'ai'
  final bool _runSync = true;

  String _segmentBy = 'none'; // 'none', 'minutes', 'words'
  final _segmentValueController = TextEditingController(text: '10');

  bool get _hasRequiredInput {
    switch (_sourceType) {
      case 'video':
        if (_urlController.text.trim().isEmpty) return false;
        if (_titleController.text.trim().isEmpty) return false;
        return _segmentValueValid;
      case 'url':
        if (_urlController.text.trim().isEmpty) return false;
        if (_titleController.text.trim().isEmpty) return false;
        return _segmentValueValid;
      case 'file':
        if (_fileController.text.trim().isEmpty) return false;
        if (_titleController.text.trim().isEmpty) return false;
        return _segmentValueValid;
      case 'text':
        return _titleController.text.trim().isNotEmpty &&
            _rawTextController.text.trim().isNotEmpty;
      default:
        return false;
    }
  }

  bool get _segmentValueValid {
    if (_segmentBy != 'minutes' && _segmentBy != 'words') return true;
    final value = int.tryParse(_segmentValueController.text);
    return value != null && value > 0;
  }

  @override
  void initState() {
    super.initState();

    // If a specific type is requested (from Subjects or specific pages), skip Step 0
    if (widget.importType == 'video' || widget.importType == 'file') {
      _sourceType = widget.importType;
      _currentStep = 1;
    }

    // Initialize language from LanguageManager
    try {
      final langMgr = context.read<LanguageManager>();
      _selectedLanguage = langMgr.currentLanguage;
    } catch (_) {
      _selectedLanguage = 'English';
    }

    _urlController.addListener(_onUrlChanged);

    // Handle shared data from other apps
    if (widget.sharedUrl != null && widget.sharedUrl!.isNotEmpty) {
      final url = widget.sharedUrl!.trim();
      final isYouTube = url.contains('youtube.com') || url.contains('youtu.be');
      _sourceType = isYouTube ? 'video' : 'url';
      _currentStep = 1;
      _urlController.text = url;
      _onUrlChanged();
    } else if (widget.sharedFilePath != null &&
        widget.sharedFilePath!.isNotEmpty) {
      _sourceType = 'file';
      _currentStep = 1;
      _fileController.text = widget.sharedFilePath!;
      _titleController.text = _cleanFileName(
        widget.sharedFilePath!.split('/').last,
      );
    }

    _titleFocusNode = FocusNode();
    _urlFocusNode = FocusNode();
    _fileFocusNode = FocusNode();

    _titleController.addListener(() => setState(() {}));
    _urlController.addListener(() => setState(() {}));
    _fileController.addListener(() => setState(() {}));
    _rawTextController.addListener(() => setState(() {}));
    _segmentValueController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _urlController.dispose();
    _fileController.dispose();
    _rawTextController.dispose();
    _segmentValueController.dispose();
    _debounce?.cancel();
    _titleFocusNode.dispose();
    _urlFocusNode.dispose();
    _fileFocusNode.dispose();
    super.dispose();
  }

  void _onUrlChanged() {
    if (_sourceType != 'video') {
      setState(() => _videoMetadata = null);
      return;
    }
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (_urlController.text.isNotEmpty) {
        _fetchVideoMetadata(_urlController.text);
      } else {
        setState(() => _videoMetadata = null);
      }
    });
  }

  Future<void> _fetchVideoMetadata(String url) async {
    if (mounted) setState(() => _isFetchingMetadata = true);
    final videoId = _extractVideoId(url);
    if (videoId == null) {
      if (mounted) {
        setState(() {
          _videoMetadata = null;
          _isFetchingMetadata = false;
        });
      }
      return;
    }

    try {
      final response = await http.get(
        Uri.parse('https://www.youtube.com/oembed?url=$url&format=json'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _videoMetadata = {
              'title': data['title'] ?? 'YouTube Video',
              'thumbnail': 'https://img.youtube.com/vi/$videoId/mqdefault.jpg',
            };
            _isFetchingMetadata = false;
          });
          if (_titleController.text.isEmpty) {
            _titleController.text = data['title'] ?? '';
          }
        }
      } else if (mounted) {
        setState(() {
          _videoMetadata = {
            'title': 'YouTube Video',
            'thumbnail': 'https://img.youtube.com/vi/$videoId/mqdefault.jpg',
          };
          _isFetchingMetadata = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _videoMetadata = {
            'title': 'YouTube Video',
            'thumbnail': 'https://img.youtube.com/vi/$videoId/mqdefault.jpg',
          };
          _isFetchingMetadata = false;
        });
      }
    }
  }

  String? _extractVideoId(String url) {
    if (!url.contains('youtube.com') && !url.contains('youtu.be')) return null;
    RegExp regExp = RegExp(
      r'.*(?:(?:youtu\.be\/|v\/|vi\/|u\/\w\/|embed\/|shorts\/)|(?:(?:watch)?\?v(?:i)?=|\&v(?:i)?=))([^#\&\?]*).*',
      caseSensitive: false,
      multiLine: false,
    );
    final match = regExp.firstMatch(url);
    if (match != null && match.groupCount >= 1) return match.group(1);
    return null;
  }

  bool _isValidUrl(String url) {
    String processed = url.trim();
    if (!processed.contains('://')) processed = 'https://$processed';
    final uri = Uri.tryParse(processed);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'txt'],
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _fileController.text = result.files.single.path!;
          if (_titleController.text.isEmpty) {
            _titleController.text = _cleanFileName(result.files.single.name);
          }
        });
        if (mounted) FocusScope.of(context).unfocus();
      }
    } catch (e) {
      if (mounted) {
        UiUtils.showErrorSnackbar(context, 'Error picking file: $e');
      }
    }
  }

  /// Extract a clean, readable title from a filename.
  /// "The_Obesity_Code_OceanofPDF.com.pdf" → "The Obesity Code"
  String _cleanFileName(String fileName) {
    // Strip only the last extension (.pdf, .txt)
    final lastDot = fileName.lastIndexOf('.');
    String name = lastDot > 0 ? fileName.substring(0, lastDot) : fileName;

    // Replace underscores and hyphens with spaces
    name = name.replaceAll('_', ' ').replaceAll('-', ' ');

    // Remove common junk patterns from download sites
    final junkPatterns = [
      RegExp(r'\s*OceanofPDF\.?c?o?m?\s*', caseSensitive: false),
      RegExp(r'\s*z-?lib\.?o?r?g?\s*', caseSensitive: false),
      RegExp(r'\s*pdfdrive\.?c?o?m?\s*', caseSensitive: false),
      RegExp(r'\s*libgen\.?[a-z]*\s*', caseSensitive: false),
      RegExp(r'\s*\(.*?lib.*?\)\s*', caseSensitive: false),
      RegExp(r'\s*\(.*?\.com\)\s*', caseSensitive: false),
      RegExp(r'\s*\(.*?\.org\)\s*', caseSensitive: false),
    ];
    for (final pattern in junkPatterns) {
      name = name.replaceAll(pattern, ' ');
    }

    // Collapse multiple spaces and trim
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();

    return name.isNotEmpty ? name : 'Imported File';
  }

  Future<void> _handleSave() async {
    bool hasError = false;
    if (_titleController.text.trim().isEmpty) {
      setState(() => _titleError = 'Please enter a title');
      hasError = true;
    }
    if (hasError) return;

    if (_segmentBy == 'chapters') {
      // No threshold needed — chapters define their own boundaries
    } else if (_segmentBy == 'minutes' || _segmentBy == 'words') {
      final sv = int.tryParse(_segmentValueController.text);
      if (sv == null || sv <= 0) {
        setState(() => _isLoading = false);
        if (mounted) {
          UiUtils.showErrorSnackbar(
            context,
            _segmentBy == 'minutes'
                ? 'Please enter a valid number of minutes'
                : 'Please enter a valid number of words',
          );
        }
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      if (_sourceType == 'video') {
        await _importService.createImport(
          title: _titleController.text,
          sourceUrl: _urlController.text,
          runSync: _runSync,
          segmentBy: _segmentBy,
          segmentValue: int.tryParse(_segmentValueController.text),
          tags: _tags,
          language: _selectedLanguage,
          isPublic: _isPublic,
        );
      } else if (_sourceType == 'url') {
        final urlText = _urlController.text.trim();
        if (urlText.isEmpty) {
          setState(() => _urlError = 'Please enter a URL');
          setState(() => _isLoading = false);
          return;
        }
        await _importService.createImport(
          title: _titleController.text,
          sourceUrl: urlText,
          sourceType: 'url',
          runSync: _runSync,
          segmentBy: _segmentBy,
          segmentValue: int.tryParse(_segmentValueController.text),
          tags: _tags,
          language: _selectedLanguage,
          isPublic: _isPublic,
        );
      } else if (_sourceType == 'text') {
        if (_rawTextController.text.trim().isEmpty) {
          setState(() => _rawTextError = 'Please enter some text');
          setState(() => _isLoading = false);
          return;
        }
        await _importService.createImport(
          title: _titleController.text,
          rawText: _rawTextController.text,
          runSync: _runSync,
          tags: _tags,
          language: _selectedLanguage,
          isPublic: _isPublic,
        );
      } else {
        // File import
        await _importService.createImport(
          title: _titleController.text,
          filePath: _fileController.text,
          runSync: _runSync,
          segmentBy: _segmentBy,
          segmentValue: int.tryParse(_segmentValueController.text),
          tags: _tags,
          language: _selectedLanguage,
          isPublic: _isPublic,
        );
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        final err = e.toString().toLowerCase();
        if (err.contains('rate_limit_exceeded') ||
            err.contains('too many requests')) {
          _showRateLimitDialog();
        } else if (err.contains('connection refused') ||
            err.contains('sockethandshake') ||
            err.contains('handshakeexception') ||
            err.contains('socketexception')) {
          _showServerUnavailableDialog();
        } else {
          _showErrorDialog(e.toString());
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
        if (_currentStep == 0) {
          _sourceType = null;
        }
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  void _showRateLimitDialog() {
    showDialog(
      context: context,
      builder: (ctx) => CustomDialog(
        title: 'Daily Limit Reached',
        showCancelButton: false,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.timer_off_rounded,
                size: 40,
                color: Colors.orangeAccent,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'You have reached your daily import limit.',
              style: GoogleFonts.nunito(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'You can import up to 5 items per minute and 20 per day. '
              'Please wait and try again later.',
              style: GoogleFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white54
                    : Colors.black45,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        saveButtonText: 'OK',
        saveButtonColor: Colors.orangeAccent,
        onSave: () => Navigator.pop(ctx),
        onCancel: () => Navigator.pop(ctx),
      ),
    );
  }

  void _showServerUnavailableDialog() {
    showDialog(
      context: context,
      builder: (ctx) => CustomDialog(
        title: 'Service Unavailable',
        showCancelButton: false,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                size: 40,
                color: Colors.redAccent,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'We could not reach the import service.',
              style: GoogleFonts.nunito(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Please check your connection and try again later.',
              style: GoogleFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white54
                    : Colors.black45,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        saveButtonText: 'OK',
        saveButtonColor: Colors.redAccent,
        onSave: () => Navigator.pop(ctx),
        onCancel: () => Navigator.pop(ctx),
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => CustomDialog(
        title: 'Import Error',
        showCancelButton: false,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                size: 40,
                color: Colors.redAccent,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              style: GoogleFonts.nunito(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        saveButtonText: 'OK',
        saveButtonColor: Colors.redAccent,
        onSave: () => Navigator.pop(ctx),
        onCancel: () => Navigator.pop(ctx),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color tealColor = const Color(0xFF4ECDC4);

    return CustomDialog(
      title: 'Import Content',
      onCancel: () => Navigator.of(context).pop(),
      showSaveButton: false,
      showActions: false,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStepIndicator(),
            const SizedBox(height: 24),

            if (_currentStep == 0) _buildStep0(),
            if (_currentStep == 1) _buildStep1(),

            if (!(_currentStep == 1 && _sourceType == 'ai')) ...[
              const SizedBox(height: 32),
              LayoutBuilder(
                builder: (context, constraints) {
                  final useStack = constraints.maxWidth < 300;
                  final List<Widget> buttons = [
                    // Primary action (Import) first
                    if (_currentStep == 1 && _sourceType != 'ai') ...[
                      Expanded(
                        flex: useStack ? 0 : 1,
                        child: ElevatedButton(
                          onPressed:
                              (_isLoading ||
                                  _isFetchingMetadata ||
                                  !_hasRequiredInput)
                              ? null
                              : _handleSave,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: tealColor,
                            disabledBackgroundColor: tealColor.withValues(
                              alpha: 0.25,
                            ),
                            foregroundColor: Colors.white,
                            disabledForegroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(56),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: (_isLoading || _isFetchingMetadata)
                              ? const SizedBox(height: 20, child: _AnimatedDots())
                              : FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    'Import',
                                    style: GoogleFonts.nunito(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      SizedBox(
                        width: useStack ? 0 : 16,
                        height: useStack ? 12 : 0,
                      ),
                    ],
                    // Back/Cancel after
                    Expanded(
                      flex: useStack ? 0 : 1,
                      child: OutlinedButton(
                        onPressed: _prevStep,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          side: BorderSide(
                            color: isDark ? Colors.white10 : Colors.black12,
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _currentStep == 1 ? 'Back' : 'Cancel',
                            style: GoogleFonts.nunito(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ];

                  return useStack
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: buttons
                              .map((e) => e is Expanded ? e.child : e)
                              .toList(),
                        )
                      : Row(children: buttons);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalSteps = 2; // Selection then Input/Details

    return Row(
      children: List.generate(totalSteps, (index) {
        final isActive = index <= _currentStep;
        return Expanded(
          child: Container(
            height: 4,
            margin: EdgeInsets.only(right: index == totalSteps - 1 ? 0 : 4),
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFF4ECDC4)
                  : (isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.05)),
              borderRadius: BorderRadius.circular(2),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: Color(0xFF4ECDC4).withValues(alpha: 0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildStep0() {
    return Column(
      children: [
        _buildSourceCard(
          type: 'video',
          title: 'YouTube Link',
          subtitle: 'Auto-segmented with transcripts',
          icon: Icons.smart_display_rounded,
        ),
        const SizedBox(height: 12),
        _buildSourceCard(
          type: 'url',
          title: 'Web Article',
          subtitle: 'Extract text from any webpage',
          icon: Icons.language_rounded,
        ),
        const SizedBox(height: 12),
        _buildSourceCard(
          type: 'file',
          title: 'File Upload',
          subtitle: 'PDF or TXT from your device',
          icon: Icons.upload_file_rounded,
        ),
        const SizedBox(height: 12),
        _buildSourceCard(
          type: 'text',
          title: 'Paste Text',
          subtitle: 'Paste raw text directly',
          icon: Icons.sticky_note_2_rounded,
        ),
        const SizedBox(height: 12),
        _buildSourceCard(
          type: 'ai',
          title: 'AI',
          subtitle: 'Generate lessons with AI',
          icon: Icons.auto_awesome_rounded,
        ),
      ],
    );
  }

  Widget _buildStep1() {
    bool showDetails = false;
    if (_sourceType == 'video' && _videoMetadata != null) showDetails = true;
    if (_sourceType == 'url' && _isValidUrl(_urlController.text)) {
      showDetails = true;
    }
    if (_sourceType == 'file' && _fileController.text.isNotEmpty) {
      showDetails = true;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_sourceType == 'ai')
          AIGenerationForm(
            language: _selectedLanguage,
            tags: _tags,
            onCancel: () => _prevStep(),
          )
        else ...[
          // Type-specific input (URL, file path, or text content)
          if (_sourceType == 'video')
            _buildModernTextField(
              label: 'YouTube URL',
              controller: _urlController,
              focusNode: _urlFocusNode,
              hint: 'Paste video link here...',
              errorText: _urlError,
            )
          else if (_sourceType == 'url')
            _buildModernTextField(
              label: 'Web Article URL',
              controller: _urlController,
              focusNode: _urlFocusNode,
              hint: 'https://example.com/article...',
              errorText: _urlError,
            )
          else if (_sourceType == 'file')
            _buildModernTextField(
              label: 'File Path',
              controller: _fileController,
              focusNode: _fileFocusNode,
              hint: 'Select PDF or TXT file...',
              errorText: _fileError,
              onTap: _pickFile,
              suffixIcon: Icons.folder_open_rounded,
            ),

          // Title — always shown for all non-AI import types
          const SizedBox(height: 24),
          _buildModernTextField(
            label: 'Display Title',
            controller: _titleController,
            focusNode: _titleFocusNode,
            hint: 'Enter a recognizable title...',
            errorText: _titleError,
          ),
          const SizedBox(height: 16),

          // Tags & Language — always shown for all non-AI import types
          _buildTagsAndLanguageSection(),

          // Type-specific content below tags
          if (_sourceType == 'text') ...[
            const SizedBox(height: 16),
            _buildModernTextField(
              label: 'Text Content',
              controller: _rawTextController,
              hint: 'Paste your text content here...',
              errorText: _rawTextError,
              maxLines: 10,
            ),
          ],

          // ─── Visibility toggle ────────────────────────────────────
          const SizedBox(height: 20),
          _buildVisibilityToggle(),

          if (showDetails && _sourceType != 'text') ...[
            const SizedBox(height: 24),
            Divider(
              color:
                  (Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black)
                      .withValues(alpha: 0.05),
              height: 1,
            ),
            if (_sourceType == 'video' && _videoMetadata != null) ...[
              const SizedBox(height: 24),
              _buildModernPreviewCard(),
            ],
            if (_sourceType == 'url') ...[const SizedBox(height: 12)],
            const SizedBox(height: 24),
            _buildSegmentationSelector(),
          ],
        ],
      ],
    );
  }

  Widget _buildVisibilityToggle() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tealColor = const Color(0xFF4ECDC4);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          'Public',
          style: GoogleFonts.nunito(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        activeTrackColor: tealColor,
        value: _isPublic,
        onChanged: (v) => setState(() => _isPublic = v),
      ),
    );
  }

  Widget _buildSegmentationSelector() {
    return SegmentationSelector(
      sourceType: _sourceType ?? 'video',
      hasChapters: _sourceType == 'video',
      initialSegmentBy: _segmentBy,
      initialSegmentValue: int.tryParse(_segmentValueController.text) ?? 10,
      onChanged: (selection) {
        setState(() {
          _segmentBy = selection.segmentBy;
          if (selection.segmentValue != null) {
            _segmentValueController.text = selection.segmentValue.toString();
          }
        });
      },
    );
  }

  Widget _buildSourceCard({
    required String type,
    required String title,
    String? subtitle,
    required IconData icon,
  }) {
    final isSelected = _sourceType == type;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color tealColor = const Color(0xFF4ECDC4);

    return GestureDetector(
      onTap: () {
        if (_sourceType != type) {
          setState(() {
            _sourceType = type;
            _currentStep = 1;
            // Clear controllers and metadata when switching types
            _titleController.clear();
            _urlController.clear();
            _fileController.clear();
            _rawTextController.clear();
            _videoMetadata = null;
            _urlError = null;
            _fileError = null;
            _rawTextError = null;
            _titleError = null;
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: isSelected ? 0.05 : 0.02)
              : Colors.black.withValues(alpha: isSelected ? 0.02 : 0.01),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? tealColor
                : (isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.05)),
            width: isSelected ? 2 : 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: tealColor.withValues(alpha: isSelected ? 0.15 : 0.05),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: isSelected
                    ? tealColor
                    : (isDark ? Colors.white38 : Colors.black38),
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.nunito(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: isDark
                          ? (isSelected ? Colors.white : Colors.white70)
                          : (isSelected ? Colors.black : Colors.black87),
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white24 : Colors.black26,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernTextField({
    required String label,
    required TextEditingController controller,
    FocusNode? focusNode,
    String? hint,
    String? errorText,
    VoidCallback? onTap,
    IconData? suffixIcon,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty) ...[
          Text(
            label,
            style: GoogleFonts.nunito(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: controller,
          focusNode: focusNode,
          readOnly: onTap != null,
          onTap: onTap,
          onChanged: onChanged,
          style: GoogleFonts.nunito(
            color: isDark ? Colors.white70 : Colors.black87,
            fontWeight: FontWeight.w700,
          ),
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.nunito(
              color: isDark ? Colors.white12 : Colors.black26,
              fontWeight: FontWeight.w600,
            ),
            errorText: errorText,
            suffixIcon: suffixIcon != null
                ? Icon(suffixIcon, color: const Color(0xFF4ECDC4))
                : null,
            filled: true,
            fillColor: isDark
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.black.withValues(alpha: 0.03),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.05),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(
                color: Color(0xFF4ECDC4),
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTagsAndLanguageSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tealColor = const Color(0xFF4ECDC4);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Language picker
        Text(
          'Language',
          style: GoogleFonts.nunito(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.05),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedLanguage,
              isExpanded: true,
              borderRadius: BorderRadius.circular(20),
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: tealColor.withValues(alpha: 0.8),
                size: 24,
              ),
              dropdownColor: isDark ? const Color(0xFF1E272E) : Colors.white,
              items:
                  (() {
                        try {
                          final langMgr = context.read<LanguageManager>();
                          return langMgr.myLanguages;
                        } catch (_) {
                          return <String>[
                            'English',
                            'Spanish',
                            'French',
                            'German',
                            'Italian',
                            'Portuguese',
                            'Russian',
                            'Japanese',
                            'Korean',
                            'Chinese',
                            'Arabic',
                            'Hindi',
                          ];
                        }
                      })()
                      .map(
                        (lang) => DropdownMenuItem(
                          value: lang,
                          child: Row(
                            children: [
                              Icon(
                                Icons.language_rounded,
                                color: tealColor.withValues(alpha: 0.7),
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                lang,
                                style: GoogleFonts.nunito(
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedLanguage = value);
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Tags
        Text(
          'Tags',
          style: GoogleFonts.nunito(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
        const SizedBox(height: 8),
        TagSelector(
          initialTags: _tags,
          onTagsChanged: (tags) {
            setState(() => _tags = tags);
          },
          hintText: 'Add tags to organize your content...',
        ),
        const SizedBox(height: 8),
        Text(
          'Tags help you find and filter your content.',
          style: GoogleFonts.nunito(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white24 : Colors.black26,
          ),
        ),
      ],
    );
  }

  Widget _buildModernPreviewCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.black.withValues(alpha: 0.3)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              _videoMetadata!['thumbnail']!,
              width: 80,
              height: 45,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Preview Loaded',
                  style: GoogleFonts.nunito(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF4ECDC4),
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  _videoMetadata!['title']!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedDots extends StatefulWidget {
  const _AnimatedDots();
  @override
  State<_AnimatedDots> createState() => _AnimatedDotsState();
}

class _AnimatedDotsState extends State<_AnimatedDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            // Sequential jumping effect: phase shift based on index
            final jump = math.sin(
              (_controller.value * 2 * math.pi) - (index * 1.2),
            );
            // Only jump upwards (negative y)
            final verticalOffset = jump < 0 ? jump * 6 : 0.0;

            return Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              child: Transform.translate(
                offset: Offset(0, verticalOffset),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
