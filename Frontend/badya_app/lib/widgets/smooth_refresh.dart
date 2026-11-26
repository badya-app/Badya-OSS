import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// App-wide signature coral accent color.
const Color _kBrandCoral = Color(0xFFFF6B6B);

/// Distance in logical pixels user must pull down to arm the refresh.
const double _kTriggerDistance = 85.0;

/// Max visual pull displacement (exponentially damped).
const double _kMaxVisualDampedOffset = 56.0;

/// A buttery-smooth, professional pull-to-refresh indicator.
///
/// Features:
/// - Floating overlay pill/badge that NEVER pushes or drags the page content down.
/// - Elastic exponential rubber-band resistance that tracks the finger smoothly.
/// - Fluid scale, rotation, and arc filling as you drag.
/// - Tactile haptic feedback when armed.
/// - Works reliably with both [CustomScrollView] and [NestedScrollView] (including TabBarViews).
/// - Bulletproof state machine: handles pointer cancel/up, scroll-end, and safety timeouts
///   so the indicator CAN NEVER GET STUCK.
class BadyaRefreshIndicator extends StatefulWidget {
  final Widget child;
  final Future<void> Function() onRefresh;

  /// Custom top offset where the indicator begins.
  /// If null, defaults to `MediaQuery.of(context).padding.top + 8.0`.
  final double? edgeOffset;

  /// Additional offset to displace the indicator downwards.
  final double displacement;

  const BadyaRefreshIndicator({
    super.key,
    required this.child,
    required this.onRefresh,
    this.edgeOffset,
    this.displacement = 0.0,
  });

  @override
  State<BadyaRefreshIndicator> createState() => _BadyaRefreshIndicatorState();
}

class _BadyaRefreshIndicatorState extends State<BadyaRefreshIndicator>
    with TickerProviderStateMixin {
  double _rawDragDistance = 0.0;
  bool _isDragging = false;
  bool _isRefreshing = false;
  bool _hasHapticed = false;
  int? _activeDepth;

  late AnimationController _springBackController;
  Animation<double>? _springBackAnimation;

  late AnimationController _dismissScaleController;
  late Animation<double> _dismissScaleAnimation;
  late Animation<double> _dismissFadeAnimation;

  Timer? _safetyTimeoutTimer;

  @override
  void initState() {
    super.initState();

    _springBackController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );

    _dismissScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );

    _dismissScaleAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _dismissScaleController,
        curve: Curves.easeInBack,
      ),
    );

    _dismissFadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _dismissScaleController,
        curve: Curves.easeIn,
      ),
    );
  }

  @override
  void dispose() {
    _safetyTimeoutTimer?.cancel();
    _springBackController.dispose();
    _dismissScaleController.dispose();
    super.dispose();
  }

  double get _progress =>
      (_rawDragDistance / _kTriggerDistance).clamp(0.0, 1.0);

  /// Exponential rubber-band damping curve for an organic, elastic touch feel.
  double get _dampedOffset {
    if (_rawDragDistance <= 0.0) return 0.0;
    return _kMaxVisualDampedOffset *
        (1.0 - math.exp(-_rawDragDistance / 65.0));
  }

  void _updateDrag(double newDistance) {
    if (_isRefreshing) return;

    final clampedDistance = newDistance.clamp(0.0, 220.0);
    final previousProgress = _progress;

    setState(() {
      _rawDragDistance = clampedDistance;
    });

    // Provide a crisp, subtle haptic pulse exactly when crossing the trigger threshold.
    if (_progress >= 1.0 && previousProgress < 1.0 && !_hasHapticed) {
      _hasHapticed = true;
      HapticFeedback.mediumImpact();
    } else if (_progress < 0.75 && _hasHapticed) {
      // Reset haptic so user can re-trigger if pulling again without letting go.
      _hasHapticed = false;
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    // Only handle vertical scrolling
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }

    if (_isRefreshing) {
      return false;
    }

    if (notification is OverscrollNotification) {
      // overscroll < 0 indicates dragging downward past top boundary
      if (notification.overscroll < 0) {
        if (!_isDragging) {
          _isDragging = true;
          _activeDepth = notification.depth;
        }
        if (notification.depth == _activeDepth) {
          _updateDrag(_rawDragDistance + (-notification.overscroll));
        }
      }
    } else if (notification is ScrollUpdateNotification) {
      if (_isDragging && notification.depth == _activeDepth) {
        // If user drags back up while overscrolled, scrollDelta will be > 0
        if (notification.scrollDelta != null &&
            notification.scrollDelta! > 0) {
          _updateDrag(_rawDragDistance - notification.scrollDelta!);
        }
      }
    } else if (notification is ScrollEndNotification) {
      if (_isDragging && notification.depth == _activeDepth) {
        _handleDragEnd();
      }
    } else if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.idle && _isDragging) {
        _handleDragEnd();
      }
    }

    return false;
  }

  void _onPointerUpOrCancel(PointerEvent event) {
    if (_isDragging && !_isRefreshing) {
      _handleDragEnd();
    }
  }

  void _handleDragEnd() {
    if (_isRefreshing) return;

    if (_rawDragDistance >= _kTriggerDistance) {
      _triggerRefresh();
    } else {
      _animateBackToZero();
    }
  }

  void _animateBackToZero() {
    _isDragging = false;
    _activeDepth = null;
    _hasHapticed = false;

    if (_rawDragDistance == 0.0) return;

    final startDistance = _rawDragDistance;
    _springBackAnimation = Tween<double>(
      begin: startDistance,
      end: 0.0,
    ).animate(
      CurvedAnimation(
        parent: _springBackController,
        curve: Curves.easeOutCubic,
      ),
    )..addListener(() {
        if (mounted) {
          setState(() {
            _rawDragDistance = _springBackAnimation!.value;
          });
        }
      });

    _springBackController.forward(from: 0.0);
  }

  Future<void> _triggerRefresh() async {
    _isDragging = false;
    _activeDepth = null;
    _hasHapticed = false;

    setState(() {
      _isRefreshing = true;
    });

    // Settle to resting position smoothly
    final startDistance = _rawDragDistance;
    final restingDistance = _kTriggerDistance;
    _springBackAnimation = Tween<double>(
      begin: startDistance,
      end: restingDistance,
    ).animate(
      CurvedAnimation(
        parent: _springBackController,
        curve: Curves.easeOutBack,
      ),
    )..addListener(() {
        if (mounted) {
          setState(() {
            _rawDragDistance = _springBackAnimation!.value;
          });
        }
      });
    _springBackController.forward(from: 0.0);

    // Safety timeout: dismiss if refresh hangs for > 15s
    _safetyTimeoutTimer?.cancel();
    _safetyTimeoutTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && _isRefreshing) {
        _finishRefresh();
      }
    });

    try {
      await widget.onRefresh();
    } catch (_) {
      // Ignored: errors should be handled by onRefresh caller
    } finally {
      if (mounted) {
        _finishRefresh();
      }
    }
  }

  Future<void> _finishRefresh() async {
    _safetyTimeoutTimer?.cancel();
    if (!_isRefreshing) return;

    // Pop-out scale & fade exit animation
    await _dismissScaleController.forward(from: 0.0);

    if (mounted) {
      setState(() {
        _isRefreshing = false;
        _rawDragDistance = 0.0;
        _isDragging = false;
        _activeDepth = null;
      });
      _dismissScaleController.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final topPadding = widget.edgeOffset ??
        (MediaQuery.of(context).padding.top + 8.0 + widget.displacement);

    final showIndicator = _rawDragDistance > 0.0 || _isRefreshing;
    final progress = _progress;
    final currentOffset = _dampedOffset;

    return Stack(
      children: [
        // Content wrapped with touch and scroll listeners
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerUp: _onPointerUpOrCancel,
          onPointerCancel: _onPointerUpOrCancel,
          child: NotificationListener<ScrollNotification>(
            onNotification: _handleScrollNotification,
            child: widget.child,
          ),
        ),

        // Floating pill indicator overlay
        if (showIndicator)
          Positioned(
            top: topPadding + currentOffset,
            left: 0,
            right: 0,
            child: Center(
              child: AnimatedBuilder(
                animation: _dismissScaleController,
                builder: (context, child) {
                  double scale;
                  double opacity;

                  if (_dismissScaleController.isAnimating ||
                      _dismissScaleController.isCompleted) {
                    scale = _dismissScaleAnimation.value;
                    opacity = _dismissFadeAnimation.value;
                  } else if (_isRefreshing) {
                    scale = 1.0;
                    opacity = 1.0;
                  } else {
                    scale = (0.35 +
                            0.65 *
                                Curves.easeOutBack.transform(
                                  (progress / 0.75).clamp(0.0, 1.0),
                                ))
                        .clamp(0.0, 1.15);
                    opacity = (progress * 2.2).clamp(0.0, 1.0);
                  }

                  return Opacity(
                    opacity: opacity.clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: scale.clamp(0.0, 1.2),
                      child: child,
                    ),
                  );
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF262626) : Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: isDark
                            ? Colors.black.withValues(alpha: 0.55)
                            : _kBrandCoral.withValues(alpha: 0.22),
                        blurRadius: 14,
                        spreadRadius: 1,
                        offset: const Offset(0, 4),
                      ),
                      BoxShadow(
                        color: Colors.black
                            .withValues(alpha: isDark ? 0.35 : 0.06),
                        blurRadius: 5,
                        offset: const Offset(0, 1),
                      ),
                    ],
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.12)
                          : _kBrandCoral.withValues(alpha: 0.18),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: _isRefreshing
                          ? const CircularProgressIndicator(
                              strokeWidth: 2.8,
                              color: _kBrandCoral,
                              strokeCap: StrokeCap.round,
                            )
                          : Transform.rotate(
                              angle: progress * math.pi * 1.6,
                              child: CircularProgressIndicator(
                                value: (progress * 0.85).clamp(0.06, 0.85),
                                strokeWidth: 2.8,
                                color: _kBrandCoral,
                                strokeCap: StrokeCap.round,
                                backgroundColor: isDark
                                    ? Colors.white10
                                    : const Color(0xFFFF6B6B)
                                        .withValues(alpha: 0.12),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
