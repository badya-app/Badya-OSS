import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:Badya/services/notification_preferences_service.dart';
import 'package:Badya/services/engagement_notification_scheduler.dart';
import 'package:Badya/services/notification_service.dart';
import 'package:Badya/utils/ui_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationSettingsSheet extends StatefulWidget {
  final NotificationPreferencesService preferencesService;

  const NotificationSettingsSheet({
    super.key,
    required this.preferencesService,
  });

  @override
  State<NotificationSettingsSheet> createState() =>
      _NotificationSettingsSheetState();
}

class _NotificationSettingsSheetState extends State<NotificationSettingsSheet> {
  static const String _topicToggleKey = 'notification_toggle_topic_suggestions';
  static const String _motivationToggleKey = 'notification_toggle_motivation';
  static const String _videoReadyToggleKey = 'notification_toggle_video_ready';

  bool _topicSuggestions = true;
  bool _motivation = true;
  bool _videoReady = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _topicSuggestions = prefs.getBool(_topicToggleKey) ?? true;
      _motivation = prefs.getBool(_motivationToggleKey) ?? true;
      _videoReady = prefs.getBool(_videoReadyToggleKey) ?? true;
      _isLoading = false;
    });
  }

  Future<void> _onToggleChanged() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_topicToggleKey, _topicSuggestions);
    await prefs.setBool(_motivationToggleKey, _motivation);
    await prefs.setBool(_videoReadyToggleKey, _videoReady);

    final scheduler = EngagementNotificationScheduler(
      notificationService: NotificationService(),
      preferencesService: widget.preferencesService,
    );
    await scheduler.scheduleAllNotifications();

    if (mounted) {
      UiUtils.showTopNotification(context, 'Notification settings saved', type: NotificationType.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 300,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '🔔 Notification Preferences',
                    style: GoogleFonts.nunito(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildToggleTile(
                icon: Icons.menu_book_rounded,
                title: 'Topic Suggestions',
                subtitle: 'One topic daily from your recommended content',
                value: _topicSuggestions,
                onChanged: (v) {
                  setState(() => _topicSuggestions = v);
                  _onToggleChanged();
                },
              ),
              const SizedBox(height: 12),
              _buildToggleTile(
                icon: Icons.rocket_launch_rounded,
                title: 'Daily Motivation',
                subtitle: 'Encouraging messages to keep you learning',
                value: _motivation,
                onChanged: (v) {
                  setState(() => _motivation = v);
                  _onToggleChanged();
                },
              ),
              const SizedBox(height: 12),
              _buildToggleTile(
                icon: Icons.videocam_rounded,
                title: 'Video Ready',
                subtitle: 'Alert when long video generation completes',
                value: _videoReady,
                onChanged: (v) {
                  setState(() => _videoReady = v);
                  _onToggleChanged();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggleTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
        ),
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        secondary: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Theme.of(context).primaryColor, size: 20),
        ),
        title: Text(
          title,
          style: GoogleFonts.nunito(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: GoogleFonts.nunito(
            fontSize: 12,
            color: Theme.of(
              context,
            ).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
          ),
        ),
        value: value,
        activeThumbColor: Theme.of(context).primaryColor,
        onChanged: onChanged,
      ),
    );
  }
}
