import 'package:Badya/services/app_review_prompt_service.dart';
import 'package:Badya/utils/ui_utils.dart';
import 'package:Badya/widgets/custom_dialog.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Pre-prompt for Google Play reviews after the user's first XP.
class ReviewPromptDialog extends StatefulWidget {
  final AppReviewPromptService service;

  const ReviewPromptDialog({super.key, required this.service});

  static Future<void> show(
    BuildContext context, {
    AppReviewPromptService? service,
  }) {
    final svc = service ?? AppReviewPromptService.instance;
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ReviewPromptDialog(service: svc),
    );
  }

  @override
  State<ReviewPromptDialog> createState() => _ReviewPromptDialogState();
}

class _ReviewPromptDialogState extends State<ReviewPromptDialog> {
  int _stars = 0;
  bool _showFeedbackField = false;
  bool _isSubmitting = false;
  final TextEditingController _feedbackController = TextEditingController();

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _dismissWithoutReview() async {
    await widget.service.markCompleted();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _submit() async {
    if (_stars == 0 || _isSubmitting) return;

    if (_stars >= 4) {
      setState(() => _isSubmitting = true);
      await widget.service.markCompleted();
      if (mounted) Navigator.of(context).pop();
      await widget.service.requestStoreReview();
      return;
    }

    if (!_showFeedbackField) {
      setState(() => _showFeedbackField = true);
      return;
    }

    final text = _feedbackController.text.trim();
    if (text.isEmpty) {
      UiUtils.showTopNotification(
        context,
        'Please share a quick note so we can improve.',
        type: NotificationType.error,
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await widget.service.submitLowRatingFeedback(text);
      await widget.service.markCompleted();
      if (!mounted) return;
      Navigator.of(context).pop();
      UiUtils.showTopNotification(
        context,
        'Thank you for your feedback!',
        type: NotificationType.success,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      UiUtils.showTopNotification(
        context,
        'Could not send feedback. Please try again.',
        type: NotificationType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtitleColor = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.color
        ?.withValues(alpha: 0.7);

    final saveLabel = _stars == 0
        ? 'Continue'
        : _stars >= 4
            ? 'Rate'
            : _showFeedbackField
                ? 'Send'
                : 'Tell us more';

    return CustomDialog(
      title: 'Enjoying Badya?',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You\'re making real progress! A quick rating on Google Play helps other learners find us.',
            style: GoogleFonts.nunito(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: subtitleColor,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final starIndex = index + 1;
                  final filled = starIndex <= _stars;
                  return IconButton(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                    onPressed: _isSubmitting
                        ? null
                        : () => setState(() {
                              _stars = starIndex;
                              if (_stars >= 4) {
                                _showFeedbackField = false;
                              }
                            }),
                    icon: Icon(
                      filled ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 36,
                      color: filled
                          ? const Color(0xFFFFD93D)
                          : (isDark ? Colors.white38 : Colors.black26),
                    ),
                  );
                }),
              ),
            ),
          ),
          if (_showFeedbackField) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _feedbackController,
              maxLines: 3,
              maxLength: 2000,
              enabled: !_isSubmitting,
              style: GoogleFonts.nunito(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: 'What could we improve?',
                hintStyle: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: subtitleColor?.withValues(alpha: 0.6),
                ),
                filled: true,
                fillColor: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.color
                    ?.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                contentPadding: const EdgeInsets.all(16),
              ),
            ),
          ],
        ],
      ),
      cancelButtonText: 'Not now',
      saveButtonText: saveLabel,
      saveButtonColor: const Color(0xFF4ECDC4),
      isLoading: _isSubmitting,
      onCancel: _isSubmitting ? () {} : _dismissWithoutReview,
      onSave: _isSubmitting ? null : _submit,
      showSaveButton: _stars > 0,
    );
  }
}
