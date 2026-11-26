import 'package:Badya/services/user_preferences_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Settings page for controlling profile visibility to other users.
class PrivacyVisibilitySettingsPage extends StatefulWidget {
  final UserPreferencesService? prefs;
  const PrivacyVisibilitySettingsPage({super.key, this.prefs});

  @override
  State<PrivacyVisibilitySettingsPage> createState() =>
      _PrivacyVisibilitySettingsPageState();
}

class _PrivacyVisibilitySettingsPageState
    extends State<PrivacyVisibilitySettingsPage> {
  late final UserPreferencesService _prefs;
  Map<String, bool> _visibility = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _prefs = widget.prefs ?? UserPreferencesService();
    _loadVisibility();
  }

  Future<void> _loadVisibility() async {
    final visibility = await _prefs.getProfileVisibility();
    if (!mounted) return;
    setState(() {
      _visibility = Map<String, bool>.from(visibility);
      _isLoading = false;
    });
  }

  Future<void> _updateVisibility(String key, bool value) async {
    setState(() {
      _visibility[key] = value;
    });
    await _prefs.updateProfileVisibility(_visibility);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Privacy & Visibility',
          style: GoogleFonts.nunito(fontWeight: FontWeight.w800),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              key: const ValueKey('visibility_settings_list'),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Control what others can see on your profile',
                    style: GoogleFonts.nunito(
                      fontSize: 14,
                      color: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.color
                          ?.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildVisibilityToggle(
                    'Show XP & Progress Bar',
                    'show_xp',
                    Icons.trending_up_rounded,
                    const Color(0xFFFF6B6B),
                  ),
                  _buildVisibilityToggle(
                    'Show Level Badge',
                    'show_level',
                    Icons.stars_rounded,
                    const Color(0xFF4ECDC4),
                  ),
                  _buildVisibilityToggle(
                    'Show Streak & Calendar',
                    'show_streak',
                    Icons.local_fire_department_rounded,
                    const Color(0xFFFFD93D),
                  ),
                  _buildVisibilityToggle(
                    'Show Coins',
                    'show_coins',
                    Icons.monetization_on_rounded,
                    const Color(0xFFFFC460),
                  ),
                  _buildVisibilityToggle(
                    'Show Achievements',
                    'show_achievements',
                    Icons.emoji_events_rounded,
                    const Color(0xFF6C5CE7),
                  ),
                  _buildVisibilityToggle(
                    'Show Languages',
                    'show_languages',
                    Icons.language_rounded,
                    const Color(0xFF4ECDC4),
                  ),
                  _buildVisibilityToggle(
                    'Show Following/Followers',
                    'show_following',
                    Icons.people_rounded,
                    const Color(0xFF00B894),
                  ),
                  _buildVisibilityToggle(
                    'Show Stats Row',
                    'show_stats',
                    Icons.bar_chart_rounded,
                    const Color(0xFF6C5CE7),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .primaryColor
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: Theme.of(context).primaryColor,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Your own profile always shows all information. These settings only affect what other users see.',
                            style: GoogleFonts.nunito(
                              fontSize: 12,
                              color: Theme.of(context).primaryColor,
                            ),
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

  Widget _buildVisibilityToggle(
    String label,
    String key,
    IconData icon,
    Color color,
  ) {
    final value = _visibility[key] ?? true;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          label,
          style: GoogleFonts.nunito(fontWeight: FontWeight.w700),
        ),
        trailing: Switch(
          value: value,
          onChanged: (newValue) => _updateVisibility(key, newValue),
          activeTrackColor: color,
        ),
      ),
    );
  }
}




