import 'package:Badya/widgets/custom_dialog.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Dialog for renaming a word with duplicate-check validation.
class EditWordDialog extends StatefulWidget {
  final String originalWord;
  final Set<String> existingWords;

  const EditWordDialog({
    super.key,
    required this.originalWord,
    required this.existingWords,
  });

  @override
  State<EditWordDialog> createState() => _EditWordDialogState();
}

class _EditWordDialogState extends State<EditWordDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.originalWord);
    _controller.addListener(_validate);
  }

  @override
  void dispose() {
    _controller.removeListener(_validate);
    _controller.dispose();
    super.dispose();
  }

  void _validate() {
    final text = _controller.text.trim();
    String? err;
    if (text.isEmpty) {
      err = 'Word cannot be empty';
    } else if (text != widget.originalWord &&
        widget.existingWords.any(
          (w) => w.toLowerCase() == text.toLowerCase(),
        )) {
      err = 'This word already exists';
    }
    if (err != _error) setState(() => _error = err);
  }

  @override
  Widget build(BuildContext context) {
    return CustomDialog(
      title: 'Edit Word',
      saveButtonText: 'Save',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Rename "${widget.originalWord}"',
            style: GoogleFonts.nunito(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            style: GoogleFonts.nunito(),
            decoration: InputDecoration(
              filled: true,
              fillColor: Theme.of(context).brightness == Brightness.dark
                  ? Colors.black26
                  : Colors.grey.shade100,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              errorText: _error,
              errorStyle: GoogleFonts.nunito(fontSize: 12),
            ),
          ),
        ],
      ),
      onCancel: () => Navigator.pop(context),
      onSave: () {
        final text = _controller.text.trim();
        if (text.isEmpty) return;
        if (text != widget.originalWord &&
            widget.existingWords.any(
              (w) => w.toLowerCase() == text.toLowerCase(),
            )) {
          return;
        }
        Navigator.pop(context, text);
      },
    );
  }
}
