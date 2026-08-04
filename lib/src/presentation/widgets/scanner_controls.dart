import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'glass_container.dart';

class ScannerTopBar extends StatelessWidget {
  final VoidCallback? onPickImage;
  final VoidCallback? onToggleFlash;
  final VoidCallback? onBack;
  final bool isTorchOn;
  final Widget? finishWidget;
  final double? currentZoom;
  final ValueChanged<double>? onZoomChanged;
  final ValueChanged<double>? onZoomChangeEnd;

  const ScannerTopBar({
    super.key,
    this.onPickImage,
    this.onToggleFlash,
    this.onBack,
    this.isTorchOn = false,
    this.finishWidget,
    this.currentZoom,
    this.onZoomChanged,
    this.onZoomChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final double zoomVal = currentZoom ?? 1.0;
    final bool isZoomedIn = zoomVal > 1.1;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GlassContainer(
                  padding: EdgeInsets.zero,
                  borderRadius: 16,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      if (ModalRoute.of(context)?.isCurrent == true) {
                        if (onBack != null) onBack!();
                        Navigator.of(context).pop();
                      }
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onToggleFlash != null) ...[
                      GlassContainer(
                        padding: EdgeInsets.zero,
                        borderRadius: 16,
                        backgroundColor: isTorchOn
                            ? const Color(0xFFFBBF24).withValues(alpha: 0.25)
                            : null,
                        border: Border.all(
                          color: isTorchOn
                              ? const Color(0xFFFBBF24).withValues(alpha: 0.6)
                              : Colors.white.withValues(alpha: 0.15),
                          width: 1.2,
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: onToggleFlash,
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              transitionBuilder: (child, anim) =>
                                  ScaleTransition(scale: anim, child: child),
                              child: Icon(
                                isTorchOn
                                    ? Icons.bolt_rounded
                                    : Icons.bolt_outlined,
                                key: ValueKey<bool>(isTorchOn),
                                color: isTorchOn
                                    ? const Color(0xFFFFD54F)
                                    : Colors.white.withValues(alpha: 0.9),
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    if (onPickImage != null)
                      GlassContainer(
                        padding: EdgeInsets.zero,
                        borderRadius: 16,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: onPickImage,
                          child: const Padding(
                            padding: EdgeInsets.all(10),
                            child: Icon(
                              Icons.photo_library_outlined,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            if (onZoomChanged != null)
              GlassContainer(
                padding: EdgeInsets.zero,
                borderRadius: 16,
                backgroundColor: isZoomedIn
                    ? const Color(0xFF10B981).withValues(alpha: 0.25)
                    : null,
                border: Border.all(
                  color: isZoomedIn
                      ? const Color(0xFF10B981).withValues(alpha: 0.6)
                      : Colors.white.withValues(alpha: 0.15),
                  width: 1.2,
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    final double nextZoom;
                    if (zoomVal < 1.8) {
                      nextZoom = 2.0;
                    } else if (zoomVal < 2.8) {
                      nextZoom = 3.0;
                    } else {
                      nextZoom = 1.0;
                    }
                    onZoomChanged!(nextZoom);
                    onZoomChangeEnd?.call(nextZoom);
                    HapticFeedback.lightImpact();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.center_focus_strong_rounded,
                          color: isZoomedIn
                              ? Colors.greenAccent
                              : Colors.white,
                          size: 19,
                        ),
                        const SizedBox(width: 4),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          transitionBuilder: (child, anim) =>
                              ScaleTransition(scale: anim, child: child),
                          child: Text(
                            '${zoomVal.toStringAsFixed(zoomVal.truncateToDouble() == zoomVal ? 0 : 1)}x',
                            key: ValueKey<String>(
                              '${zoomVal.toStringAsFixed(zoomVal.truncateToDouble() == zoomVal ? 0 : 1)}x',
                            ),
                            style: TextStyle(
                              color: isZoomedIn
                                  ? Colors.greenAccent
                                  : Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ScannerControlsRow extends StatelessWidget {
  final double? currentZoom;
  final ValueChanged<double>? onZoomChanged;
  final ValueChanged<double>? onZoomChangeEnd;
  final bool isMultiScan;
  final ValueChanged<bool> onMultiScanChanged;
  final bool showMultiScanToggle;
  final double? rightPadding;

  const ScannerControlsRow({
    super.key,
    this.currentZoom,
    this.onZoomChanged,
    this.onZoomChangeEnd,
    required this.isMultiScan,
    required this.onMultiScanChanged,
    this.showMultiScanToggle = true,
    this.rightPadding,
  });

  @override
  Widget build(BuildContext context) {
    if (!showMultiScanToggle) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(right: rightPadding ?? 16.0, left: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          GlassContainer(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            borderRadius: 30,
            backgroundColor: Colors.black.withValues(alpha: 0.4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isMultiScan
                      ? Icons.auto_awesome_motion
                      : Icons.auto_awesome_motion_outlined,
                  color: isMultiScan ? Colors.greenAccent : Colors.white70,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Quét liên tục',
                  style: TextStyle(
                    color: isMultiScan ? Colors.greenAccent : Colors.white70,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 26,
                  width: 44,
                  child: CupertinoSwitch(
                    value: isMultiScan,
                    activeTrackColor: Colors.greenAccent.shade400,
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
                    onChanged: (value) {
                      onMultiScanChanged(value);
                      HapticFeedback.lightImpact();
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
