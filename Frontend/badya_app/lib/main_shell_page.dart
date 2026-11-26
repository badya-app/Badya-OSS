import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:Badya/home_page.dart';
import 'package:Badya/library_page.dart';
import 'package:Badya/language_profile_page.dart';
import 'package:Badya/leaderboard_page.dart';
import 'package:Badya/profile_page.dart';
import 'package:Badya/models/transaction_model.dart';
import 'package:Badya/services/coin_service.dart';
import 'package:Badya/services/language_manager.dart';
import 'package:Badya/utils/logger.dart';
import 'package:Badya/widgets/app_bottom_navigation_bar.dart';
import 'package:Badya/widgets/coin_celebration_overlay.dart';
import 'package:Badya/widgets/import_dialog.dart';

class MainShellPage extends StatefulWidget {
  const MainShellPage({super.key});

  @override
  State<MainShellPage> createState() => _MainShellPageState();
}

class _MainShellPageState extends State<MainShellPage> {
  int _currentIndex = 0;
  int _photoVersion = 0;
  StreamSubscription? _shareMediaSubscription;
  bool _handlingShare = false;
  final Map<int, Widget> _tabCache = {};
  String? _lastLanguage;

  void _onProfilePhotoChanged() {
    setState(() => _photoVersion++);
  }

  @override
  void initState() {
    super.initState();
    _initShareListeners();
    _tryClaimStarterBonus();
  }

  @override
  void dispose() {
    _shareMediaSubscription?.cancel();
    super.dispose();
  }

  void _onItemTapped(int index) {
    if (index == _currentIndex) return;
    setState(() => _currentIndex = index);
  }

  void _initShareListeners() {
    _shareMediaSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(
          _handleSharedFiles,
          onError: (err) {
            Logger.error('Share intent error', err);
          },
        );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ReceiveSharingIntent.instance.getInitialMedia().then(_handleSharedFiles);
    });
  }

  /// Checks for a pending starter bonus from onboarding, claims it, and
  /// shows the celebration overlay. Self-contained — the onboarding page
  /// only sets a SharedPreferences flag; all logic lives here.
  Future<void> _tryClaimStarterBonus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getBool('pending_starter_celebration') ?? false;
      if (!pending) return;

      // Clear the flag immediately so it never fires twice.
      await prefs.setBool('pending_starter_celebration', false);

      // Wait for the first frame so we have a valid BuildContext for the
      // celebration overlay.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;

        final bonusResult = await CoinService()
            .claimStarterBonus()
            .timeout(const Duration(seconds: 15), onTimeout: () {
              Logger.warn('Starter bonus claim timed out — proceeding without celebration');
              return BonusResult(
                success: false,
                message: 'Timed out',
                alreadyClaimed: false,
              );
            });

        if (bonusResult.success && mounted) {
          await CoinCelebrationOverlay.show(
            context,
            coinsAwarded: bonusResult.coinsAwarded ?? 150,
            description: 'Welcome Bonus!',
          );
          Logger.info('Starter bonus claimed: ${bonusResult.coinsAwarded} coins');
        } else if (!bonusResult.alreadyClaimed) {
          Logger.warn('Failed to claim starter bonus: ${bonusResult.message}');
        }
      });
    } catch (e) {
      Logger.error('Error checking starter bonus', e);
    }
  }

  void _handleSharedFiles(List<SharedMediaFile> files) {
    if (files.isEmpty || _handlingShare) return;
    _handlingShare = true;
    final file = files.first;
    if (file.type == SharedMediaType.url || file.type == SharedMediaType.text) {
      _openImportDialog(text: file.path);
    } else if (file.type == SharedMediaType.file) {
      _openImportDialog(filePath: file.path);
    }
  }

  Future<void> _openImportDialog({String? text, String? filePath}) async {
    if (!mounted) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => ImportDialog(
        importType: 'all',
        sharedUrl: text,
        sharedFilePath: filePath,
      ),
    );
    _handlingShare = false;
    if (result == true) {
      ReceiveSharingIntent.instance.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = context.watch<LanguageManager>().currentLanguage;

    // Invalidate the cached LanguageProfilePage when the language changes
    // so it reconstructs with the new language parameter.
    if (_lastLanguage != null && _lastLanguage != language) {
      _tabCache.remove(2);
    }
    _lastLanguage = language;

    return Stack(
      children: [
        _buildTab(_currentIndex, language),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: AppBottomNavigationBar(
            currentIndex: _currentIndex,
            onItemTapped: _onItemTapped,
            photoVersion: _photoVersion,
          ),
        ),
      ],
    );
  }

  Widget _buildTab(int index, dynamic language) {
    return _tabCache.putIfAbsent(index, () {
      switch (index) {
        case 0:
          return HomePage(onNavigateToLibrary: () => _onItemTapped(1));
        case 1:
          return const LibraryPage();
        case 2:
          return LanguageProfilePage(language: language);
        case 3:
          return const LeaderboardPage();
        case 4:
          return ProfilePage(onPhotoChanged: _onProfilePhotoChanged);
        default:
          return HomePage(onNavigateToLibrary: () => _onItemTapped(1));
      }
    });
  }
}
