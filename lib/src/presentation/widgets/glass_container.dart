import 'package:flutter/material.dart';

/// Translucent panel for the controls drawn over the live camera preview.
///
/// Deliberately has no BackdropFilter blur: the camera texture changes every
/// frame, so each blurred panel would re-sample and re-blur the screen behind
/// it ~30 times a second for as long as the scanner is open — a steady GPU
/// load that shows up as heat. The semi-opaque fill keeps controls legible
/// without it (Android already rendered this way).
class GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final Color? backgroundColor;
  final Border? border;

  const GlassContainer({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 24.0,
    this.backgroundColor,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(borderRadius),
        border: border ?? Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            spreadRadius: -2,
          ),
        ],
      ),
      child: child,
    );
  }
}
