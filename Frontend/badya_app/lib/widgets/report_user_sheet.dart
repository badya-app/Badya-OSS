import 'package:Badya/services/report_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Bottom sheet for reporting a user to the moderation team.
///
/// The user picks a reason from the predefined list (the Firestore rules only
/// accept these), optionally adds details, and submits. Duplicate and
/// rate-limit errors from [ReportService] are surfaced inline.
class ReportUserSheet extends StatefulWidget {
  final String reportedUid;
  final String? reportedDisplayName;
  final ReportService? reportService;

  const ReportUserSheet({
    super.key,
    required this.reportedUid,
    this.reportedDisplayName,
    this.reportService,
  });

  /// Show the sheet and resolve `true` when a report was submitted.
  static Future<bool> show(
    BuildContext context, {
    required String reportedUid,
    String? reportedDisplayName,
    ReportService? reportService,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Theme.of(context).cardTheme.color,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (context) => ReportUserSheet(
        reportedUid: reportedUid,
        reportedDisplayName: reportedDisplayName,
        reportService: reportService,
      ),
    );
    return result ?? false;
  }

  @override
  State<ReportUserSheet> createState() => _ReportUserSheetState();
}

class _ReportUserSheetState extends State<ReportUserSheet> {
  late final ReportService _reportService;
  final TextEditingController _detailsController = TextEditingController();
  ReportReason? _selectedReason;
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reportService = widget.reportService ?? ReportService();
  }

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  bool get _canSubmit => _selectedReason != null && !_isSubmitting;

  Future<void> _submit() async {
    if (_selectedReason == null || _isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    final uid = _resolveCurrentUid();
    if (uid == null) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _error = 'You must be signed in to report a user.';
        });
      }
      return;
    }

    try {
      final ok = await _reportService.submitUserReport(
        reporterUid: uid,
        reportedUid: widget.reportedUid,
        reason: _selectedReason!.value,
        details: _detailsController.text,
      );
      if (!ok) {
        // Not written (e.g. empty reportedUid) — don't report success.
        if (mounted) {
          setState(() {
            _isSubmitting = false;
            _error = 'This user cannot be reported.';
          });
        }
        return;
      }
      if (mounted) Navigator.pop(context, true);
    } on ReportSubmissionException catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _error = 'Could not submit your report. Please try again.';
        });
      }
    }
  }

  String? _resolveCurrentUid() {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      // Firebase not initialized (e.g. widget tests) — cannot report.
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.reportedDisplayName?.isNotEmpty == true
        ? widget.reportedDisplayName
        : null;

    return Padding(
      // Keep the sheet above the keyboard when the details field is focused.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE57373).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.flag_rounded,
                    color: Color(0xFFE57373),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Report user',
                    style: GoogleFonts.nunito(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Theme.of(context).textTheme.titleLarge?.color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              displayName == null
                  ? 'Why are you reporting this user? Reports are reviewed by '
                        'our team.'
                  : 'Why are you reporting $displayName? Reports are reviewed '
                        'by our team.',
              style: GoogleFonts.nunito(
                fontSize: 13,
                height: 1.4,
                color: Theme.of(
                  context,
                ).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            // Reason picker
            ...ReportReason.all.map((reason) {
              final selected = _selectedReason?.value == reason.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _isSubmitting
                      ? null
                      : () => setState(() => _selectedReason = reason),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFFE57373).withValues(alpha: 0.1)
                          : Theme.of(
                              context,
                            ).dividerColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFFE57373)
                            : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selected
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_off_rounded,
                          size: 20,
                          color: selected
                              ? const Color(0xFFE57373)
                              : Theme.of(
                                  context,
                                ).textTheme.bodyMedium?.color?.withValues(
                                  alpha: 0.4,
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            reason.label,
                            style: GoogleFonts.nunito(
                              fontSize: 14,
                              fontWeight: selected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.color,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 12),
            // Optional details
            TextField(
              controller: _detailsController,
              enabled: !_isSubmitting,
              maxLines: 3,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: 'Add details (optional)',
                hintText: 'Tell us more about what happened…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE57373).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_rounded,
                      color: Color(0xFFE57373),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: GoogleFonts.nunito(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFE57373),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _canSubmit ? _submit : null,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE57373),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Submit report',
                        style: GoogleFonts.nunito(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
