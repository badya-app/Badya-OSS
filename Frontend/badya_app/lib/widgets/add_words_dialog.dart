import 'package:Badya/widgets/custom_dialog.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Dialog for adding multiple words (one per line) to a word list.
class AddWordsDialog extends StatefulWidget {
  const AddWordsDialog({super.key});

  @override
  State<AddWordsDialog> createState() => _AddWordsDialogState();
}

class _AddWordsDialogState extends State<AddWordsDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomDialog(
      title: 'Add Words',
      saveButtonText: 'Add All',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Enter words or sentences (one per line):',
            style: GoogleFonts.nunito(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            maxLines: 8,
            minLines: 3,
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
              hintText: 'Apple\nBanana\nI love coding',
              hintStyle: TextStyle(
                color: Theme.of(context).hintColor.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
      onCancel: () => Navigator.pop(context),
      onSave: () => Navigator.pop(context, _controller.text),
    );
  }
}
