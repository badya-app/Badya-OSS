import 'package:flutter/material.dart';

class CustomButton extends StatefulWidget {
  final String text;
  final VoidCallback onPressed;
  final bool isLoading;

  /// When false, the button is visually dimmed and ignores taps.
  /// Used e.g. to keep the signup button disabled until the user accepts
  /// the Terms of Service / Privacy Policy.
  final bool isEnabled;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? borderColor;
  final double? borderWidth;

  const CustomButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.isEnabled = true,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
    this.borderWidth,
  });

  @override
  State<CustomButton> createState() => _CustomButtonState();
}

class _CustomButtonState extends State<CustomButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTapDown: widget.isEnabled
          ? (_) => setState(() => _isPressed = true)
          : null,
      onTapUp: widget.isEnabled
          ? (_) => setState(() => _isPressed = false)
          : null,
      onTapCancel: widget.isEnabled
          ? () => setState(() => _isPressed = false)
          : null,
      onTap: (!widget.isEnabled || widget.isLoading) ? null : widget.onPressed,
      child: AnimatedScale(
        scale: _isPressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            color: (widget.backgroundColor ??
                        theme.elevatedButtonTheme.style?.backgroundColor
                            ?.resolve({}) ??
                    theme.primaryColor)
                .withValues(alpha: widget.isEnabled ? 1.0 : 0.45),
            borderRadius: BorderRadius.circular(30),
            border: widget.borderColor != null
                ? Border.all(
                    color: widget.borderColor!,
                    width: widget.borderWidth ?? 2,
                  )
                : null,
            boxShadow: [
              if (!_isPressed && widget.isEnabled)
                BoxShadow(
                  color: (widget.backgroundColor ?? theme.primaryColor)
                      .withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
            ],
          ),
          child: Center(
            child: widget.isLoading
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  )
                : Text(
                    widget.text.toUpperCase(),
                    style:
                        theme.elevatedButtonTheme.style?.textStyle
                            ?.resolve({})
                            ?.copyWith(
                              color: widget.foregroundColor ??
                                  (widget.isEnabled
                                      ? Colors.white
                                      : Colors.white60),
                            ) ??
                        TextStyle(
                          color: widget.isEnabled
                              ? Colors.white
                              : Colors.white60,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                        ),
                  ),
          ),
        ),
      ),
    );
  }
}
