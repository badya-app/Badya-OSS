import 'package:flutter/material.dart';
import 'package:Badya/services/streak_reminder_manager.dart';
import 'package:Badya/utils/logger.dart';
import 'package:Badya/utils/ui_utils.dart';

/// Widget to configure streak reminder times
class StreakReminderConfigWidget extends StatefulWidget {
  final StreakReminderManager reminderManager;
  final VoidCallback? onConfigSaved;
  final bool readOnly;

  const StreakReminderConfigWidget({
    super.key,
    required this.reminderManager,
    this.onConfigSaved,
    this.readOnly = false,
  });

  @override
  State<StreakReminderConfigWidget> createState() =>
      _StreakReminderConfigWidgetState();
}

class _StreakReminderConfigWidgetState extends State<StreakReminderConfigWidget> {
  late ReminderConfig _config;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final config = await widget.reminderManager.getReminderConfig();
      setState(() {
        _config = config;
        _isLoading = false;
      });
    } catch (e) {
      Logger.error('Error loading config', e);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickTime() async {
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: _config.reminderTime,
    );
    if (pickedTime != null) {
      setState(() {
        _config = ReminderConfig(
          enabled: _config.enabled,
          reminderTime: pickedTime,
          message: _config.message,
        );
      });
    }
  }

  Future<void> _saveConfig() async {
    try {
      await widget.reminderManager.saveReminderConfig(_config);
      if (mounted) {
        UiUtils.showTopNotification(context, 'Streak reminder time updated!', type: NotificationType.success);
      }
      widget.onConfigSaved?.call();
    } catch (e) {
      if (mounted) {
        UiUtils.showErrorSnackbar(context, 'Error saving config: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with enable/disable toggle
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '🔥 Streak Reminder',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Switch(
                value: _config.enabled,
                activeThumbColor: Theme.of(context).primaryColor,
                onChanged: widget.readOnly
                    ? null
                    : (value) {
                        setState(() {
                          _config = ReminderConfig(
                            enabled: value,
                            reminderTime: _config.reminderTime,
                            message: _config.message,
                          );
                        });
                      },
              ),
            ],
          ),
        ),
        if (_config.enabled) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              widget.readOnly
                  ? 'The reminder is set to a fixed daily time.'
                  : 'Receive a daily reminder to maintain your streak',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
          ),
          const SizedBox(height: 16),
          // Single Reminder
          _buildReminderTimeTile(
            context,
            time: _config.reminderTime,
            description: 'Daily streak reminder',
          ),
          const SizedBox(height: 24),
          // Save button
          if (!widget.readOnly)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('Save Reminder Time'),
                  onPressed: _saveConfig,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
        ] else
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Streak reminders are disabled',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildReminderTimeTile(
    BuildContext context, {
    required TimeOfDay time,
    required String description,
  }) {
    final formattedTime = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
            child: Icon(
              Icons.notifications_active,
              color: Theme.of(context).primaryColor,
            ),
          ),
          title: const Text('Daily Reminder'),
          subtitle: Text(description),
          trailing: Chip(
            label: Text(
              formattedTime,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
          ),
          onTap: widget.readOnly ? null : () => _pickTime(),
        ),
      ),
    );
  }
}
