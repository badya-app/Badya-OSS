import 'package:Badya/widgets/custom_dialog.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Type of top notification for color/icon selection.
enum NotificationType { success, error, info }

class UiUtils {
  /// Simple, pragmatic email regex — matches the overwhelmingly common cases
  /// and catches obvious typos (missing @, missing domain, spaces, etc.).
  static final RegExp _emailRegExp = RegExp(
    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
  );

  /// Returns `true` when [text] looks like a network / connection error from
  /// Dart's http package, Firebase, or the platform socket layer.
  static bool _isNetworkError(String text) {
    final lower = text.toLowerCase();
    const keywords = [
      'network is unreachable',
      'newconnectionerror',
      'connection refused',
      'connection reset',
      'connection timed out',
      'connection closed',
      'connection abort',
      'connection broken',
      'socketexception',
      'sockethandshake',
      'handshakeexception',
      'clientexception',
      'timeoutexception',
      'failed host lookup',
      'errno = 65',
      'errno = 113',
      'errno = 101',
      'errno = 111',
      'google.auth.exceptions.transporterror',
      'xmlhttprequest error',
      'unable to resolve host',
    ];
    return keywords.any(lower.contains);
  }

  /// Basic email format check used by login / signup / forgot-password forms
  /// before hitting Firebase (review UX items #12/#13).
  static bool isValidEmail(String email) {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return false;
    return _emailRegExp.hasMatch(trimmed);
  }

  static void showErrorDialog(
    BuildContext context, {
    required String message,
    String? error,
    VoidCallback? onDismiss,
    String? stayButtonText,
    VoidCallback? onStay,
  }) {
    String displayTitle = 'Oops!';
    String displayMessage = message;
    String textToCheck = error ?? message;

    // Handle known errors with user-friendly messages
    if (_isNetworkError(textToCheck)) {
      displayTitle = 'Connection Unstable';
      displayMessage =
          'It looks like your connection is unstable or offline. Please check your internet connection and try again.';
    } else if (textToCheck.contains('Voice WebSocket closed')) {
      displayTitle = 'Connection Lost';
      displayMessage =
          'Voice chat connection was interrupted. Please try again.';
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => CustomDialog(
        title: displayTitle,
        content: Text(
          displayMessage,
          style: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        saveButtonText: 'Go Back',
        saveButtonColor: Colors.redAccent,
        cancelButtonText: stayButtonText ?? 'Stay Here',
        onCancel: () {
          Navigator.pop(context); // Dismiss dialog
          if (onStay != null) {
            onStay();
          }
        },
        onSave: () {
          Navigator.pop(context); // Dismiss dialog
          if (onDismiss != null) {
            onDismiss();
          }
        },
      ),
    );
  }

  static void showErrorSnackbar(
    BuildContext context,
    String message, {
    String? error,
  }) {
    String displayMessage = message;
    String textToCheck = error ?? message;

    if (_isNetworkError(textToCheck)) {
      displayMessage =
          'Connection Unstable: It looks like your connection dropped. Please check your internet.';
    } else if (textToCheck.contains('Voice WebSocket closed')) {
      displayMessage =
          'Connection Lost: Voice chat connection was interrupted.';
    }

    showTopNotification(context, displayMessage, type: NotificationType.error);
  }

  static void showSuccessSnackbar(BuildContext context, String message) {
    showTopNotification(context, message, type: NotificationType.success);
  }

  static void showInfoSnackbar(BuildContext context, String message) {
    showTopNotification(context, message, type: NotificationType.info);
  }

  static String formatTimeAgo(dynamic timestamp) {
    if (timestamp == null) return 'Recently';
    
    DateTime dateTime;
    if (timestamp is DateTime) {
      dateTime = timestamp;
    } else if (timestamp is int) {
      dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    } else {
      // Handle Firestore Timestamp if available (assuming it might be passed as an object with toDate())
      try {
        dateTime = (timestamp as dynamic).toDate();
      } catch (e) {
        return 'Recently';
      }
    }

    final duration = DateTime.now().difference(dateTime);

    if (duration.inMinutes < 1) {
      return 'just now';
    } else if (duration.inHours < 1) {
      return '${duration.inMinutes}min ago';
    } else if (duration.inDays < 1) {
      return '${duration.inHours}h ago';
    } else if (duration.inDays < 7) {
      return '${duration.inDays}d ago';
    } else if (duration.inDays < 30) {
      return '${duration.inDays ~/ 7}w ago';
    } else if (duration.inDays < 365) {
      return '${duration.inDays ~/ 30}mo ago';
    } else {
      return '${duration.inDays ~/ 365}y ago';
    }
  }

  static String formatDate(dynamic timestamp) {
    if (timestamp == null) return 'Unknown Date';
    
    DateTime dateTime;
    if (timestamp is DateTime) {
      dateTime = timestamp;
    } else if (timestamp is int) {
      dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    } else {
      try {
        dateTime = (timestamp as dynamic).toDate();
      } catch (e) {
        return 'Unknown Date';
      }
    }

    // Format like "Oct 12, 2023"
    return DateFormat('MMM d, yyyy').format(dateTime);
  }

  static OverlayEntry? _currentOverlay;

  static void showTopNotification(
    BuildContext context, 
    String message, {
    IconData? icon,
    NotificationType type = NotificationType.success,
  }) {
    if (_currentOverlay != null) {
      _currentOverlay!.remove();
      _currentOverlay = null;
    }

    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    // Select colors and icon based on type
    Color accentColor;
    IconData resolvedIcon;
    switch (type) {
      case NotificationType.success:
        accentColor = const Color(0xFF2ECC71);
        resolvedIcon = icon ?? Icons.check_circle_rounded;
      case NotificationType.error:
        accentColor = const Color(0xFFFF6B6B);
        resolvedIcon = icon ?? Icons.error_outline_rounded;
      case NotificationType.info:
        accentColor = const Color(0xFF4ECDC4);
        resolvedIcon = icon ?? Icons.info_outline_rounded;
    }

    _currentOverlay = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 12,
        left: 0,
        right: 0,
        child: Material(
          color: Colors.transparent,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F1113) : Colors.white,
                borderRadius: BorderRadius.circular(40),
                border: Border.all(
                  color: accentColor.withValues(alpha: isDark ? 0.35 : 0.4),
                  width: 1.5,
                ),
                boxShadow: isDark 
                  ? [
                      // Core glow
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.12),
                        blurRadius: 20,
                        spreadRadius: 1,
                      ),
                      // Outer bloom
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.08),
                        blurRadius: 35,
                        spreadRadius: 4,
                      ),
                      // Depth shadow
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 12,
                        offset: const Offset(0, 5),
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.15),
                        blurRadius: 15,
                        spreadRadius: 1,
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: isDark ? 0.15 : 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      resolvedIcon, 
                      color: accentColor, 
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      message,
                      style: GoogleFonts.nunito(
                        color: isDark ? Colors.white : const Color(0xFF2D3436),
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ).animate().moveY(begin: -40, end: 0, duration: 400.ms, curve: Curves.easeOutBack).fadeIn(duration: 300.ms),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_currentOverlay!);

    Future.delayed(const Duration(seconds: 3), () {
      if (_currentOverlay != null) {
        _currentOverlay!.remove();
        _currentOverlay = null;
      }
    });
  }
}
