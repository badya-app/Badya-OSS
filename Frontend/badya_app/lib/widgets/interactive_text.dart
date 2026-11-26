import 'package:Badya/widgets/custom_selection_toolbar.dart';
import 'package:flutter/material.dart';

class InteractiveText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const InteractiveText({super.key, required this.text, this.style});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SelectableText(
      text,
      style: style ?? theme.textTheme.bodyLarge?.copyWith(height: 1.5),
      contextMenuBuilder: (context, editableTextState) {
        return CustomSelectionToolbar(
          anchors: editableTextState.contextMenuAnchors,
          buttonItems: editableTextState.contextMenuButtonItems,
          onHide: () => editableTextState.hideToolbar(),
          onCustomAction: (action) {
            final selection = editableTextState.textEditingValue.selection;
            final text = editableTextState.textEditingValue.text;
            final selectedText = selection.textInside(text);
            _handleAction(context, action, selectedText, editableTextState);
          },
        );
      },
    );
  }

  void _handleAction(
    BuildContext context,
    String action,
    String text,
    EditableTextState editableTextState,
  ) async {
    editableTextState.hideToolbar();
    await CustomSelectionToolbar.handleAction(context, action, text);
  }
}
