import 'dart:async';
import 'package:Badya/utils/ui_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'models/transaction_model.dart';
import 'services/coin_service.dart';
import 'services/iap_service.dart';
import 'widgets/coin_celebration_overlay.dart';
import 'widgets/smooth_refresh.dart';

/// Wallet/Store page for purchasing coins and managing subscriptions
/// Task 4.3 - 4.6
class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage>
    with SingleTickerProviderStateMixin {
  bool _initialAnimationDone = false;

  final CoinService _coinService = CoinService();
  final IAPService _iapService = IAPService();

  int _coinBalance = 0;
  bool _isSubscriber = false;
  String _currentTier = 'free';
  DateTime? _periodEnd;
  bool _autoRenewing = true;
  // 0 = Monthly Subscription (default), 1 = One-Time
  int _selectedBillingMode = 0;

  List<CoinTransaction> _transactions = [];
  bool _loadingTransactions = false;
  DocumentSnapshot? _lastTransactionDoc;
  bool _hasMoreTransactions = true;

  String _selectedPackageId = '';
  bool _purchasing = false;
  Timer? _purchaseWatchdogTimer;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initIAP();
    _loadUserData();
    _loadTransactions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialAnimationDone = true;
    });
  }

  @override
  void dispose() {
    _iapService.onPurchaseComplete = null;
    _iapService.onPurchaseError = null;
    _purchaseWatchdogTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _initIAP() async {
    await _iapService.initialize();
    _iapService.onPurchaseComplete = (result) {
      _stopPurchaseWatchdog();
      if (mounted) {
        setState(() {
          _purchasing = false;
          _selectedPackageId = '';
        });
        _handlePurchaseComplete(result);
      }
    };
    _iapService.onPurchaseError = (error) {
      _stopPurchaseWatchdog();
      if (mounted) {
        setState(() {
          _purchasing = false;
          _selectedPackageId = '';
        });
        UiUtils.showErrorSnackbar(context, 'Purchase failed: $error');
      }
    };
  }

  void _startPurchaseWatchdog() {
    _purchaseWatchdogTimer?.cancel();
    _purchaseWatchdogTimer = Timer(const Duration(seconds: 45), () {
      if (mounted && _purchasing) {
        setState(() {
          _purchasing = false;
          _selectedPackageId = '';
        });
        UiUtils.showErrorSnackbar(
          context,
          'Purchase timed out. If you were charged, your balance will update automatically.',
        );
      }
    });
  }

  void _stopPurchaseWatchdog() {
    _purchaseWatchdogTimer?.cancel();
    _purchaseWatchdogTimer = null;
  }

  void _handlePurchaseComplete(IAPResult result) {
    _stopPurchaseWatchdog();
    if (mounted) {
      setState(() {
        _purchasing = false;
        _selectedPackageId = '';
      });
    }
    if (result.success && result.coinsAdded != null && result.coinsAdded! > 0) {
      // Show celebration overlay for successful coin purchase or subscription
      CoinCelebrationOverlay.show(
        context,
        coinsAwarded: result.coinsAdded!,
        description: result.isSubscription
            ? 'Subscription Activated!'
            : 'Purchase Successful!',
        showGiftBox: false,
      );
      _loadUserData();
    } else if (result.isPending) {
      // User used a slow test card or asynchronous payment method
      UiUtils.showInfoSnackbar(
        context,
        result.message.isNotEmpty
            ? result.message
            : 'Payment is pending. Your coins will be added once payment completes.',
      );
    } else if (!result.success) {
      // Show error snackbar for failed purchases
      UiUtils.showErrorSnackbar(context, result.message);
    } else {
      // Fallback: just reload data
      _loadUserData();
    }
  }

  Future<void> _loadUserData() async {
    final balance = await _coinService.getCoinBalance();
    final subInfo = await _coinService.getSubscriptionInfo();

    // Sync subscription status with backend to catch any RTDN events
    // that occurred while the app was closed
    final syncResult = await _iapService.syncSubscription();
    
    // Re-fetch if sync found a renewal
    final finalBalance = syncResult.success && (syncResult.coinsAdded ?? 0) > 0
        ? await _coinService.getCoinBalance()
        : balance;
    final finalSubInfo = syncResult.success && (syncResult.coinsAdded ?? 0) > 0
        ? await _coinService.getSubscriptionInfo()
        : subInfo;

    if (mounted) {
      setState(() {
        _coinBalance = finalBalance;
        _isSubscriber = finalSubInfo.isSubscriber;
        _currentTier = finalSubInfo.tier;
        _periodEnd = finalSubInfo.periodEnd;
        _autoRenewing = finalSubInfo.autoRenewing;
      });
    }
  }

  Future<void> _loadTransactions({bool loadMore = false}) async {
    if (_loadingTransactions || (!loadMore && _transactions.isNotEmpty)) return;

    setState(() => _loadingTransactions = true);

    try {
      final (transactions, lastDoc) = await _coinService.getTransactions(
        limit: 20,
        startAfter: loadMore ? _lastTransactionDoc : null,
      );

      if (mounted) {
        setState(() {
          if (loadMore) {
            _transactions.addAll(transactions);
          } else {
            _transactions = transactions;
          }
          _lastTransactionDoc = lastDoc;
          _hasMoreTransactions = transactions.length == 20;
          _loadingTransactions = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingTransactions = false);
      }
    }
  }

  void _showPurchaseBottomSheet(CoinPackage package) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handlebar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: (isDark ? Colors.white : Colors.black).withValues(
                  alpha: 0.1,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 40),

            // Visual Centerpiece
            Container(
              height: 180,
              width: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFFFFD93D).withValues(alpha: 0.3),
                    blurRadius: 50,
                    spreadRadius: 15,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFFFD93D).withValues(alpha: 0.1),
                        ),
                      )
                      .animate(
                            onPlay: (controller) =>
                                controller.repeat(reverse: true),
                          )
                      .scale(
                        begin: const Offset(0.8, 0.8),
                        end: const Offset(1.2, 1.2),
                        duration: 2000.ms,
                        curve: Curves.easeInOutSine,
                      ),
                  Image.asset(
                        'assets/images/coin.png',
                        width: 120,
                        height: 120,
                        errorBuilder: (context, error, stackTrace) =>
                            const Text('🪙', style: TextStyle(fontSize: 80)),
                      )
                      .animate(
                            onPlay: (controller) =>
                                controller.repeat(reverse: true),
                          )
                      .shimmer(
                        duration: 3000.ms,
                        color: Colors.white.withValues(alpha: 0.3),
                      )
                      .moveY(
                        begin: -5,
                        end: 5,
                        duration: 1500.ms,
                        curve: Curves.easeInOutSine,
                      ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            Text(
              '${package.coins}',
              style: GoogleFonts.merriweather(
                fontSize: 48,
                fontWeight: FontWeight.w900,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),

            const SizedBox(height: 48),

            // Simplified Action Button
            SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _purchaseCoinPackage(package.productId);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF4ECDC4),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '',
                          style: GoogleFonts.nunito(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '\$${package.price.toStringAsFixed(2)}',
                          style: GoogleFonts.nunito(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .animate()
                .slideY(
                  begin: 0.2,
                  end: 0,
                  curve: Curves.easeOutBack,
                  duration: 500.ms,
                )
                .fadeIn(),

            const SizedBox(height: 16),

            // Secure Payment Notice
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 16,
                  color: Colors.green.shade400,
                ),
                const SizedBox(width: 8),
                Text(
                  'Secure Payment via Google Play',
                  style: GoogleFonts.nunito(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.textTheme.bodyMedium?.color?.withValues(
                      alpha: 0.5,
                    ),
                  ),
                ),
              ],
            ),

            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  void _showSubscriptionBottomSheet(SubscriptionPackage package) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handlebar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: (isDark ? Colors.white : Colors.black).withValues(
                  alpha: 0.1,
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 40),

            // Visual Centerpiece (same design as one-time purchase sheet)
            Container(
              height: 180,
              width: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFFFFD93D).withValues(alpha: 0.3),
                    blurRadius: 50,
                    spreadRadius: 15,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFFFD93D).withValues(alpha: 0.1),
                        ),
                      )
                      .animate(
                            onPlay: (controller) =>
                                controller.repeat(reverse: true),
                          )
                      .scale(
                        begin: const Offset(0.8, 0.8),
                        end: const Offset(1.2, 1.2),
                        duration: 2000.ms,
                        curve: Curves.easeInOutSine,
                      ),
                  Image.asset(
                        'assets/images/coin.png',
                        width: 120,
                        height: 120,
                        errorBuilder: (context, error, stackTrace) =>
                            const Text('🪙', style: TextStyle(fontSize: 80)),
                      )
                      .animate(
                            onPlay: (controller) =>
                                controller.repeat(reverse: true),
                          )
                      .shimmer(
                        duration: 3000.ms,
                        color: Colors.white.withValues(alpha: 0.3),
                      )
                      .moveY(
                        begin: -5,
                        end: 5,
                        duration: 1500.ms,
                        curve: Curves.easeInOutSine,
                      ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            Text(
              '${package.coinsPerMonth}',
              style: GoogleFonts.merriweather(
                fontSize: 48,
                fontWeight: FontWeight.w900,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),

            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF6B6B), Color(0xFFFF8E8E)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'EVERY MONTH',
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 1,
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Terms Notice Required by Google Play
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '• Billed monthly at \$${package.price.toStringAsFixed(2)}/mo — renews automatically each month.\n'
                '• Coins are added directly to your treasury every renewal.',
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  height: 1.5,
                  color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Simplified Action Button (same style as one-time purchase sheet)
            SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _purchaseSubscription(package.productId);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF4ECDC4),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '',
                          style: GoogleFonts.nunito(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '\$${package.price.toStringAsFixed(2)}/mo',
                          style: GoogleFonts.nunito(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .animate()
                .slideY(
                  begin: 0.2,
                  end: 0,
                  curve: Curves.easeOutBack,
                  duration: 500.ms,
                )
                .fadeIn(),

            const SizedBox(height: 16),

            // Secure Payment Notice
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 16,
                  color: Colors.green.shade400,
                ),
                const SizedBox(width: 8),
                Text(
                  'Secure Payment via Google Play',
                  style: GoogleFonts.nunito(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.textTheme.bodyMedium?.color?.withValues(
                      alpha: 0.5,
                    ),
                  ),
                ),
              ],
            ),

            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  Future<void> _purchaseCoinPackage(String productId) async {
    if (_purchasing) return;
    setState(() {
      _purchasing = true;
      _selectedPackageId = productId;
    });
    _startPurchaseWatchdog();

    try {
      await _iapService.purchaseCoinPackage(productId);
    } catch (e) {
      _stopPurchaseWatchdog();
      if (mounted) {
        setState(() {
          _purchasing = false;
          _selectedPackageId = '';
        });
        UiUtils.showErrorSnackbar(context, 'Purchase failed: $e');
      }
    }
  }

  Future<void> _purchaseSubscription(String productId) async {
    if (_purchasing) return;
    setState(() {
      _purchasing = true;
      _selectedPackageId = productId;
    });
    _startPurchaseWatchdog();

    try {
      await _iapService.buySubscription(productId);
    } catch (e) {
      _stopPurchaseWatchdog();
      if (mounted) {
        setState(() {
          _purchasing = false;
          _selectedPackageId = '';
        });
        UiUtils.showErrorSnackbar(context, 'Subscription failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_rounded,
            color: theme.appBarTheme.iconTheme?.color,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Treasury',
          style: GoogleFonts.merriweather(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: theme.appBarTheme.titleTextStyle?.color,
          ),
        ),
        centerTitle: true,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [theme.scaffoldBackgroundColor, const Color(0xFF1A1A1A)]
                : [theme.scaffoldBackgroundColor, const Color(0xFFF8F9FA)],
          ),
        ),
        // NestedScrollView coordinates the header (balance card + pinned
        // tab bar) with the tab content so a drag that starts in a tab
        // continues pulling the header back open once the tab reaches its
        // top — instead of stopping at the tab's edge like separate
        // scrollables do.
        child: BadyaRefreshIndicator(
          onRefresh: () async {
            setState(() {
              _lastTransactionDoc = null;
              _hasMoreTransactions = true;
              _transactions.clear();
            });
            await Future.wait([
              _loadUserData(),
              _loadTransactions(),
            ]);
          },
          child: NestedScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: ClampingScrollPhysics(),
            ),
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              // Balance Header
              SliverToBoxAdapter(child: _buildBalanceHeader(theme, isDark)),

              // Tab Bar
              SliverPersistentHeader(
                pinned: true,
                delegate: _SliverTabBarDelegate(
                  Container(
                    height: 60,
                    color: theme.scaffoldBackgroundColor,
                    child: TabBar(
                      controller: _tabController,
                      labelColor: Colors.white,
                      unselectedLabelColor: theme.textTheme.bodyMedium?.color,
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(
                        borderRadius: BorderRadius.circular(50),
                        color: const Color(0xFFFF6B6B),
                      ),
                      dividerColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      labelStyle: GoogleFonts.nunito(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                      unselectedLabelStyle: GoogleFonts.nunito(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                      tabs: const [
                        Tab(icon: Icon(Icons.shopping_bag_rounded)),
                        Tab(icon: Icon(Icons.history_rounded)),
                      ],
                    ),
                  ),
                  backgroundColor: theme.scaffoldBackgroundColor.withValues(
                    alpha: 0.95,
                  ),
                ),
              ),
            ],

            // Tab Content
            body: TabBarView(
              controller: _tabController,
              children: [
                _buildCoinPackagesTab(theme, isDark),
                _buildTransactionHistoryTab(theme, isDark),
              ],
            ),
          ),
        ),
    ),
  );
}

  Widget _buildBalanceHeader(ThemeData theme, bool isDark) {
    final header = Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF2D2D2D), const Color(0xFF1A1A1A)]
              : [const Color(0xFFFFD93D), const Color(0xFFFFA502)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : const Color(0xFFFFD93D)).withValues(
              alpha: 0.3,
            ),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color.fromARGB(
                              255,
                              244,
                              228,
                              5,
                            ).withValues(alpha: 0.1),
                            blurRadius: 15,
                            spreadRadius: 2,
                          ),
                        ],
                      ),                          child: Image.asset(
                            'assets/images/coin.png',
                            width: 46,
                            height: 46,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            Icons.monetization_on_rounded,
                            color: isDark
                                ? const Color(0xFFFFD93D)
                                : Colors.white,
                            size: 56,
                          );
                        },
                      ),
                    )
                    .animate(
                            onPlay: (controller) =>
                                controller.repeat(reverse: true),
                          )
                    .shimmer(
                      duration: 2000.ms,
                      color: Colors.white.withValues(alpha: 0.3),
                    )
                    .scale(
                      duration: 1000.ms,
                      begin: const Offset(1, 1),
                      end: const Offset(1.1, 1.1),
                      curve: Curves.easeInOutSine,
                    )
                    .then()
                    .scale(
                      duration: 1000.ms,
                      begin: const Offset(1.1, 1.1),
                      end: const Offset(1, 1),
                      curve: Curves.easeInOutSine,
                    ),
                const SizedBox(width: 20),
                Text(
                  _coinBalance.toString(),
                  style: GoogleFonts.nunito(
                    fontSize: 56,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : const Color(0xFF2D3436),
                    letterSpacing: -1,
                  ),
                ),
              ],
            ),
          ),
          if (_isSubscriber) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.stars_rounded, color: Colors.white, size: 22),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Active Plan: $_currentTier Coins / month',
                          style: GoogleFonts.nunito(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (_periodEnd != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _autoRenewing
                          ? 'Renews on ${DateFormat('MMM d, y').format(_periodEnd!)}'
                          : 'Canceled — Access ends on ${DateFormat('MMM d, y').format(_periodEnd!)}',
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _autoRenewing
                            ? (isDark
                                ? Colors.white70
                                : const Color(0xFF2D3436).withValues(alpha: 0.8))
                            : const Color(0xFFFF7675),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => _iapService.launchSubscriptionManagement(
                      productId: 'com.badya.sub_coins_$_currentTier',
                    ),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.settings_outlined,
                            size: 14,
                            color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFF2D3436),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Manage Subscription',
                            style: GoogleFonts.nunito(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFF2D3436),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
    if (!_initialAnimationDone) {
      return header
          .animate()
          .fadeIn(duration: 400.ms)
          .slideY(begin: -0.2, end: 0);
    }
    return header;
  }

  Widget _buildCoinPackagesTab(ThemeData theme, bool isDark) {
    return ListView(
      // Always scrollable so RefreshIndicator can trigger from inside the
      // NestedScrollView body, and drags chain to the header at the edges.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      children: [
        // Billing Mode Toggle (Monthly Subscription vs One-Time)
        _buildBillingModeToggle(theme, isDark),
        const SizedBox(height: 24),

        if (_selectedBillingMode == 0) ...[
          // Monthly Subscription Plans (default) — same grid design as one-time
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.68,
              crossAxisSpacing: 20,
              mainAxisSpacing: 24,
            ),
            itemCount: SubscriptionPackage.packages.length,
            itemBuilder: (context, index) {
              final subPackage = SubscriptionPackage.packages[index];
              return _buildSubscriptionPackageCard(
                subPackage,
                theme,
                isDark,
                index,
              );
            },
          ),
        ] else ...[
          // One-Time Coin Packages Grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.68,
              crossAxisSpacing: 20,
              mainAxisSpacing: 24,
            ),
            itemCount: CoinPackage.packages.length,
            itemBuilder: (context, index) {
              final package = CoinPackage.packages[index];
              return _buildCoinPackageCard(package, theme, isDark, index);
            },
          ),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildBillingModeToggle(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE8ECEF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // Monthly Subscription (first / default option)
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedBillingMode = 0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _selectedBillingMode == 0
                      ? const Color(0xFF6C5CE7)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: _selectedBillingMode == 0
                      ? [
                          BoxShadow(
                            color: const Color(0xFF6C5CE7).withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    'Monthly Sub',
                    style: GoogleFonts.nunito(
                      fontSize: 14,
                      fontWeight: _selectedBillingMode == 0
                          ? FontWeight.w900
                          : FontWeight.w600,
                      color: _selectedBillingMode == 0
                          ? Colors.white
                          : (isDark ? Colors.white54 : Colors.black45),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // One-Time
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedBillingMode = 1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _selectedBillingMode == 1
                      ? const Color(0xFF4ECDC4) 
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: _selectedBillingMode == 1
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    'One-Time',
                    style: GoogleFonts.nunito(
                      fontSize: 14,
                      fontWeight: _selectedBillingMode == 1
                          ? FontWeight.w900
                          : FontWeight.w600,
                      color: _selectedBillingMode == 1
                          ? (isDark ? Colors.white : const Color(0xFF2D3436))
                          : (isDark ? Colors.white54 : Colors.black45),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionPackageCard(
    SubscriptionPackage package,
    ThemeData theme,
    bool isDark,
    int index,
  ) {
    final isCurrent = _isSubscriber && _currentTier == package.tier;
    final isPurchasingThis =
        _purchasing && _selectedPackageId == package.productId;

    final card = GestureDetector(
      onTap: _purchasing ? null : () => _showSubscriptionBottomSheet(package),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Fancy Main Card — gradient border + purple glow
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF6C5CE7), Color(0xFFA29BFE), Color(0xFF4ECDC4)],
              ),
              borderRadius: BorderRadius.circular(34),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6C5CE7).withValues(alpha: isDark ? 0.4 : 0.3),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isDark
                      ? [const Color(0xFF2A2540), const Color(0xFF1A1826)]
                      : [Colors.white, const Color(0xFFF3F0FF)],
                ),
                borderRadius: BorderRadius.circular(32),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: Stack(
                  children: [
                    // Purple radial glow at top
                    Positioned(
                      top: -30,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 130,
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            colors: [
                              const Color(0xFF6C5CE7).withValues(alpha: 0.25),
                              const Color(0xFF6C5CE7).withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Gold glow behind coin
                    Positioned(
                      top: 4,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          width: 110,
                          height: 110,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                const Color(0xFFFFD93D).withValues(alpha: 0.35),
                                const Color(0xFFFFD93D).withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Card Content
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Spacer(flex: 2),
                          // Coin Image — glowing, shimmering, gently floating
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFFD93D).withValues(alpha: 0.45),
                                  blurRadius: 24,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Image.asset(
                                  'assets/images/coin.png',
                                  width: 46,
                                  height: 46,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Text(
                                        '🪙',
                                        style: TextStyle(fontSize: 40),
                                      ),
                                )
                                // reverse: true ping-pongs the controller so
                                // the coin eases back up instead of snapping
                                // from end to begin on loop restart.
                                .animate(
                                  onPlay: (controller) =>
                                      controller.repeat(reverse: true),
                                )
                                .shimmer(
                                  duration: 2500.ms,
                                  color: Colors.white.withValues(alpha: 0.45),
                                )
                                .moveY(
                                  begin: -3,
                                  end: 3,
                                  duration: 1800.ms,
                                  curve: Curves.easeInOutSine,
                                ),
                          ),
                          const SizedBox(height: 8),
                          // Amount (coins per month)
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              package.coinsPerMonth.toString(),
                              style: GoogleFonts.nunito(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                color: isDark ? Colors.white : const Color(0xFF6C5CE7),
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Recurring badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF6C5CE7), Color(0xFFA29BFE)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF6C5CE7).withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Text(
                              '/ month',
                              style: GoogleFonts.nunito(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const Spacer(flex: 3),
                          // Price Tag — purple gradient with glow
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF6C5CE7), Color(0xFF8075E5)],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF6C5CE7).withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Center(
                              child: isPurchasingThis
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      '\$${package.price.toStringAsFixed(2)}',
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
                  ],
                ),
              ),
            ),
          ),

          // "CURRENT PLAN" Banner (same style as BEST VALUE banner)
          if (isCurrent)
            Positioned(
              top: 0,
              left: 24,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFF00B894),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                ),
                child: Text(
                  'CURRENT PLAN',
                  style: GoogleFonts.nunito(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    if (!_initialAnimationDone) {
      return card
          .animate(delay: (100 * index).ms)
          .fadeIn()
          .slideY(begin: 0.1, end: 0);
    }
    return card;
  }

  Widget _buildCoinPackageCard(
    CoinPackage package,
    ThemeData theme,
    bool isDark,
    int index,
  ) {
    final isPopular = package.bonusPercent >= 25;
    final isPurchasingThis =
        _purchasing && _selectedPackageId == package.productId;

    final card = GestureDetector(
      onTap: _purchasing ? null : () => _showPurchaseBottomSheet(package),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Main Card — solid border in the same color as the price tag;
          // Container insets the body by the border width automatically.
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? [const Color(0xFF353535), const Color(0xFF1A1A1A)]
                    : [Colors.white, const Color(0xFFF1F2F6)],
              ),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: const Color(0xFF4ECDC4), width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              // 30 = outer radius 32 − border 2, keeps corners concentric
              borderRadius: BorderRadius.circular(30),
              child: Stack(
                children: [
                  // Radial Glow behind coin
                  Positioned(
                    top: -20,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 120,
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [
                            Color(0xFFFFD93D).withValues(alpha: 0.15),
                            Color(0xFFFFD93D).withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Card Content
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Spacer(flex: 2),
                        // Coin Image with its own glow
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Color(0xFFFFD93D).withValues(alpha: 0.2),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/images/coin.png',
                            width: 56, // Slightly smaller
                            height: 56,
                            errorBuilder: (context, error, stackTrace) =>
                                const Text(
                                  '🪙',
                                  style: TextStyle(fontSize: 40),
                                ),
                          ),
                        ),
                        const SizedBox(height: 8), // Tighter spacing
                        // Amount
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            package.coins.toString(),
                            style: GoogleFonts.nunito(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: theme.textTheme.bodyLarge?.color,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                        const Spacer(flex: 3),
                        // Price Tag
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: Color(0xFF4ECDC4),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: isPurchasingThis
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFFFFD93D),
                                    ),
                                  )
                                : Text(
                                    '\$${package.price.toStringAsFixed(2)}',
                                    style: GoogleFonts.nunito(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: theme.textTheme.bodyLarge?.color,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // "BEST VALUE" Banner
          if (isPopular)
            Positioned(
              top: 0,
              left: 24,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFD93D),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                ),
                child: Text(
                  'BEST VALUE',
                  style: GoogleFonts.nunito(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF2D3436),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    if (!_initialAnimationDone) {
      return card
          .animate(delay: (100 * index).ms)
          .fadeIn()
          .slideY(begin: 0.1, end: 0);
    }
    return card;
  }

  Widget _buildTransactionHistoryTab(ThemeData theme, bool isDark) {
    if (_transactions.isEmpty && !_loadingTransactions) {
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.receipt_long_rounded,
                    size: 64,
                    color: theme.textTheme.bodyMedium?.color,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No transactions yet',
                    style: GoogleFonts.nunito(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: theme.textTheme.bodyMedium?.color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Group transactions into month sections. The list is sorted
    // newest-first, so one pass yields sections in order — each month gets a
    // header entry (transaction == null) followed by its transactions.
    final items = <({String month, CoinTransaction? transaction})>[];
    String? lastMonth;
    for (final transaction in _transactions) {
      final month = DateFormat('MMMM yyyy').format(transaction.createdAt);
      if (month != lastMonth) {
        items.add((month: month, transaction: null));
        lastMonth = month;
      }
      items.add((month: month, transaction: transaction));
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollEndNotification &&
            notification.metrics.pixels >=
                notification.metrics.maxScrollExtent - 200 &&
            _hasMoreTransactions &&
            !_loadingTransactions) {
          _loadTransactions(loadMore: true);
        }
        return false;
      },
      child: ListView.builder(
        // Always scrollable so RefreshIndicator can trigger from inside the
        // NestedScrollView body, and drags chain to the header at the edges.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: items.length + (_loadingTransactions ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= items.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            );
          }

          final item = items[index];
          if (item.transaction == null) {
            return _buildMonthHeader(item.month, theme);
          }
          return _buildTransactionCard(
            item.transaction!,
            theme,
            isDark,
            index,
          );
        },
      ),
    );
  }

  Widget _buildMonthHeader(String monthLabel, ThemeData theme) {
    final textColor = theme.textTheme.bodyMedium?.color;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12, left: 4, right: 4),
      child: Row(
        children: [
          Text(
            monthLabel.toUpperCase(),
            style: GoogleFonts.nunito(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              color: textColor?.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(height: 1, color: textColor?.withValues(alpha: 0.12)),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionCard(
    CoinTransaction transaction,
    ThemeData theme,
    bool isDark,
    int index,
  ) {
    final isPositive =
        transaction.type == TransactionType.purchase ||
        transaction.type == TransactionType.bonus ||
        transaction.type == TransactionType.sale ||
        transaction.type == TransactionType.subscription;

    final card = Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D2D2D) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Color(0xFF2D3436).withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        children: [
          // Type icon
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _getTransactionColor(
                transaction.type,
              ).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _getTransactionIcon(transaction.type),
              color: _getTransactionColor(transaction.type),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          // Description
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.description,
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: theme.textTheme.bodyLarge?.color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('MMM d, y • h:mm a').format(transaction.createdAt),
                  style: GoogleFonts.nunito(
                    fontSize: 12,
                    color: theme.textTheme.bodyMedium?.color,
                  ),
                ),
              ],
            ),
          ),
          // Amount
          Text(
            '${isPositive ? '+' : '-'}${transaction.amount}',
            style: GoogleFonts.nunito(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: isPositive
                  ? const Color(0xFF4ECDC4)
                  : const Color(0xFFFF6B6B),
            ),
          ),
        ],
      ),
    );
    if (!_initialAnimationDone) {
      return card
          .animate(delay: (50 * index).ms)
          .fadeIn()
          .slideX(begin: 0.05, end: 0);
    }
    return card;
  }

  IconData _getTransactionIcon(TransactionType type) {
    switch (type) {
      case TransactionType.purchase:
        return Icons.shopping_cart_rounded;
      case TransactionType.bonus:
        return Icons.card_giftcard_rounded;
      case TransactionType.spend:
        return Icons.remove_circle_rounded;
      case TransactionType.sale:
        return Icons.sell_rounded;
      case TransactionType.subscription:
        return Icons.autorenew_rounded;
    }
  }

  Color _getTransactionColor(TransactionType type) {
    switch (type) {
      case TransactionType.purchase:
        return const Color(0xFFFFD93D);
      case TransactionType.bonus:
        return const Color(0xFF4ECDC4);
      case TransactionType.spend:
        return const Color(0xFFFF6B6B);
      case TransactionType.sale:
        return const Color(0xFF2ECC71);
      case TransactionType.subscription:
        return const Color(0xFF6C5CE7);
    }
  }
}

/// Delegate for pinned tab bar
class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final Color backgroundColor;

  _SliverTabBarDelegate(this.child, {required this.backgroundColor});

  @override
  double get minExtent => 60;
  @override
  double get maxExtent => 60;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(color: backgroundColor, child: child);
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return child != oldDelegate.child ||
        backgroundColor != oldDelegate.backgroundColor;
  }
}
