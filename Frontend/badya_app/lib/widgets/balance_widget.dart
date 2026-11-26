import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/coin_service.dart';
import '../wallet_page.dart';

/// Widget to display coin balance in app header
/// Tapping navigates to wallet/store page
/// Task 4.2
class BalanceWidget extends StatefulWidget {
  final VoidCallback? onTap;

  const BalanceWidget({super.key, this.onTap});

  @override
  State<BalanceWidget> createState() => _BalanceWidgetState();
}

class _BalanceWidgetState extends State<BalanceWidget>
    with SingleTickerProviderStateMixin {
  final CoinService _coinService = CoinService();
  int _coinBalance = 0;
  int? _previousBalance;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.elasticOut),
    );
    _loadBalance();
    _listenToBalance();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadBalance() async {
    final balance = await _coinService.getCoinBalance();

    if (mounted) {
      setState(() {
        _coinBalance = balance;
      });
    }
  }

  void _listenToBalance() {
    _coinService.listenToBalance().listen((balance) {
      if (mounted) {
        // Animate on balance change
        if (_previousBalance != null && _previousBalance != balance) {
          _animationController.forward().then((_) {
            _animationController.reverse();
          });
        }
        setState(() {
          _previousBalance = _coinBalance;
          _coinBalance = balance;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap:
          widget.onTap ??
          () {
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const WalletPage()));
          },
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2D2D2D) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Color(
                0xFFFFD93D,
              ).withValues(alpha: isDark ? 0.4 : 0.8),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: (isDark ? Colors.black : const Color(0xFFFFD93D))
                    .withValues(alpha: isDark ? 0.2 : 0.1),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Coin icon with premium glow
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFFFFD93D).withValues(alpha: 0.3),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                  Image.asset(
                    'assets/images/coin.png',
                    width: 28, // Slightly more compact for app bar
                    height: 28,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(
                        Icons.monetization_on_rounded,
                        color: Color(0xFFFFD93D),
                        size: 24,
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(width: 10),
              // Balance text
              Text(
                _formatNumber(_coinBalance),
                style: GoogleFonts.nunito(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : const Color(0xFF2D3436),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatNumber(int number) {
    if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}k';
    }
    return number.toString();
  }
}
