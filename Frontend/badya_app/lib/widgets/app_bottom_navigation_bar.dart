import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:Badya/services/user_preferences_service.dart';
import 'package:Badya/utils/profile_images.dart';

class AppBottomNavigationBar extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onItemTapped;
  final int photoVersion;

  const AppBottomNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onItemTapped,
    this.photoVersion = 0,
  });

  @override
  State<AppBottomNavigationBar> createState() => _AppBottomNavigationBarState();
}

class _AppBottomNavigationBarState extends State<AppBottomNavigationBar> {
  String? _profileImagePath;

  @override
  void initState() {
    super.initState();
    _loadProfileImage();
  }

  @override
  void didUpdateWidget(AppBottomNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload photo when the photo version changes (triggered by profile page)
    if (widget.photoVersion != oldWidget.photoVersion) {
      _loadProfileImage();
    }
  }

  Future<void> _loadProfileImage() async {
    final service = UserPreferencesService();
    final photoUrl = await service.getPhotoUrl();
    if (mounted) {
      setState(() {
        _profileImagePath = photoUrl;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 0, 15, 5),
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.black.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(35),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.white.withValues(alpha: 0.5),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(35),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(
                  index: 0,
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  label: 'Home',
                  isSelected: widget.currentIndex == 0,
                ),
                _buildNavItem(
                  index: 1,
                  icon: Icons.local_library_outlined,
                  activeIcon: Icons.local_library_rounded,
                  label: 'Library',
                  isSelected: widget.currentIndex == 1,
                ),
                _buildNavItem(
                  index: 2,
                  icon: Icons.language_outlined,
                  activeIcon: Icons.language_rounded,
                  label: 'Language',
                  isSelected: widget.currentIndex == 2,
                ),
                _buildNavItem(
                  index: 3,
                  icon: Icons.leaderboard_outlined,
                  activeIcon: Icons.leaderboard_rounded,
                  label: 'Leaderboard',
                  isSelected: widget.currentIndex == 3,
                ),
                _buildNavItem(
                  index: 4,
                  icon: Icons.person_outline_rounded,
                  activeIcon: Icons.person_rounded,
                  label: 'Profile',
                  isSelected: widget.currentIndex == 4,
                  isProfile: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required bool isSelected,
    bool isProfile = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final activeColor =
        theme.bottomNavigationBarTheme.selectedItemColor ??
        const Color(0xFFFF6B6B);
    final inactiveColor = isDark ? Colors.white54 : Colors.black45;

    Widget iconWidget;
    if (isProfile) {
      iconWidget = Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? activeColor : Colors.transparent,
            width: 2,
          ),
          image: DecorationImage(
            image: resolveProfileImage(_profileImagePath),
            fit: BoxFit.cover,
          ),
        ),
      );
    } else {
      iconWidget = Icon(
        isSelected ? activeIcon : icon,
        color: isSelected ? activeColor : inactiveColor,
        size: 28,
      );
    }

    return GestureDetector(
      onTap: () => widget.onItemTapped(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconWidget,
            if (isSelected)
              Container(
                margin: const EdgeInsets.only(top: 4),
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: activeColor,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
