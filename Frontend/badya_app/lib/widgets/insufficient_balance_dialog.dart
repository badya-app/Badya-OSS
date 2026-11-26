import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/transaction_model.dart';

/// Dialog shown when user tries to access content without enough coins
/// Task 4.7
class InsufficientBalanceDialog extends StatelessWidget {
  final ContentType contentType;
  final String contentTitle;
  final int actualCost;
  final int currentBalance;
  final VoidCallback onBuyCoins;
  final VoidCallback onViewStore;
  final VoidCallback onCancel;

  InsufficientBalanceDialog({
    super.key,
    required this.contentType,
    required this.contentTitle,
    required this.currentBalance,
    required this.onBuyCoins,
    required this.onViewStore,
    required this.onCancel,
    int? actualCost,
  }) : actualCost = actualCost ?? contentType.coinCost;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cost = actualCost;

    final backgroundColor = isDark
        ? theme.cardTheme.color ?? const Color(0xFF2D2D2D)
        : const Color(0xFFFDF4DD);
    final borderColor =
        isDark ? Colors.white.withValues(alpha: 0.2) : const Color(0xFF2D3436);

    return Dialog(
      backgroundColor: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: borderColor, width: isDark ? 1 : 3),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Warning icon
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Color(0xFFFF6B6B).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.account_balance_wallet_outlined,
                color: Color(0xFFFF6B6B),
                size: 40,
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Text(
              'Insufficient Balance',
              style: GoogleFonts.merriweather(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: theme.textTheme.bodyLarge?.color,
              ),
            ),
            const SizedBox(height: 16),

            // Content info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Color(0xFF2D3436).withValues(alpha: 0.1),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        _getContentIcon(contentType),
                        color: const Color(0xFF4ECDC4),
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          contentTitle,
                          style: GoogleFonts.nunito(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: theme.textTheme.bodyLarge?.color,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Required:',
                        style: GoogleFonts.nunito(
                          fontSize: 14,
                          color: theme.textTheme.bodyMedium?.color,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'assets/images/coin.png',
                            width: 24,
                            height: 24,
                            errorBuilder: (context, error, stackTrace) {
                              return const SizedBox.shrink();
                            },
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$cost',
                            style: GoogleFonts.nunito(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFFFF6B6B),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Your balance:',
                        style: GoogleFonts.nunito(
                          fontSize: 14,
                          color: theme.textTheme.bodyMedium?.color,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'assets/images/coin.png',
                            width: 24,
                            height: 24,
                            errorBuilder: (context, error, stackTrace) {
                              return const SizedBox.shrink();
                            },
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$currentBalance',
                            style: GoogleFonts.nunito(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: theme.textTheme.bodyLarge?.color,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Message
            Text(
              'Purchase coins to unlock this content.',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 14,
                color: theme.textTheme.bodyMedium?.color,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),

            // View store button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onViewStore,
                icon: const Icon(Icons.storefront_rounded, size: 20),
                label: Text(
                  'View Store',
                  style: GoogleFonts.nunito(fontWeight: FontWeight.w700),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF4ECDC4),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: Color(0xFF4ECDC4), width: 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Cancel
            TextButton(
              onPressed: onCancel,
              child: Text(
                'Cancel',
                style: GoogleFonts.nunito(
                  color: theme.textTheme.bodyMedium?.color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getContentIcon(ContentType type) {
    switch (type) {
      case ContentType.wordSmith:
        return Icons.menu_book_rounded;
      case ContentType.storyWeaver:
        return Icons.auto_stories_rounded;
      case ContentType.echoChamber:
        return Icons.play_circle_rounded;
      case ContentType.roleMaster:
        return Icons.theater_comedy_rounded;
      case ContentType.thumbnail:
        return Icons.image_rounded;
    }
  }
}

/// Helper function to show the insufficient balance dialog
Future<void> showInsufficientBalanceDialog({
  required BuildContext context,
  required ContentType contentType,
  required String contentTitle,
  required int currentBalance,
  required VoidCallback onBuyCoins,
  required VoidCallback onViewStore,
  int? actualCost,
}) {
  return showDialog(
    context: context,
    builder: (context) => InsufficientBalanceDialog(
      contentType: contentType,
      contentTitle: contentTitle,
      currentBalance: currentBalance,
      actualCost: actualCost,
      onBuyCoins: () {
        Navigator.pop(context);
        onBuyCoins();
      },
      onViewStore: () {
        Navigator.pop(context);
        onViewStore();
      },
      onCancel: () => Navigator.pop(context),
    ),
  );
}




