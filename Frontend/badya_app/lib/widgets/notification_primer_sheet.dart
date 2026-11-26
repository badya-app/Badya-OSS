import 'package:Badya/services/notification_service.dart';
import 'package:Badya/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationPrimerSheet extends StatefulWidget {
  const NotificationPrimerSheet({super.key});

  @override
  State<NotificationPrimerSheet> createState() =>
      _NotificationPrimerSheetState();
}

class _NotificationPrimerSheetState extends State<NotificationPrimerSheet> {
  static const String _primerShownKey = 'has_shown_notification_primer';
  bool _isGranting = false;

  Future<void> _markShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_primerShownKey, true);
  }

  Future<void> _onAllow() async {
    setState(() => _isGranting = true);
    // Mark that the user consented to notifications BEFORE requesting
    // the OS permission. FCMService uses this flag to decide whether
    // it should request OS permission on init (prevents the OS dialog
    // from appearing after the user tapped "Not Now").
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_allowed', true);
    try {
      await NotificationService().requestNotificationPermission();
    } catch (e) {
      Logger.error('Failed to request notification permission', e);
    }
    await _markShown();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _onNotNow() async {
    await _markShown();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 32,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).primaryColor,
                      Theme.of(context).primaryColor.withValues(alpha: 0.7),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(
                  Icons.notifications_active_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Never Miss a Lesson',
                style: GoogleFonts.nunito(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Stay on track with gentle reminders to keep your streak alive and reach your learning goals.',
                textAlign: TextAlign.center,
                style: GoogleFonts.nunito(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              _buildBenefitRow(
                Icons.local_fire_department_rounded,
                'Protect your streak with daily reminders',
              ),
              const SizedBox(height: 12),
              _buildBenefitRow(
                Icons.schedule_rounded,
                'Pick your preferred notification times',
              ),
              const SizedBox(height: 12),
              _buildBenefitRow(
                Icons.bar_chart_rounded,
                'Track progress without opening the app',
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _isGranting ? null : _onAllow,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 4,
                    textStyle: GoogleFonts.nunito(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: _isGranting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Allow Notifications'),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _isGranting ? null : _onNotNow,
                style: TextButton.styleFrom(
                  foregroundColor: isDark
                      ? Colors.grey.shade400
                      : Colors.grey.shade600,
                ),
                child: Text(
                  'Not Now',
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBenefitRow(IconData icon, String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).primaryColor),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.nunito(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
            ),
          ),
        ),
      ],
    );
  }
}
