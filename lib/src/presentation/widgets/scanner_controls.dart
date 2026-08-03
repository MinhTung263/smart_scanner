import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'glass_container.dart';

class ScannerTopBar extends StatelessWidget {
  final VoidCallback? onPickImage;
  final VoidCallback? onToggleFlash;
  final bool isTorchOn;
  final Widget? finishWidget;

  const ScannerTopBar({
    super.key,
    this.onPickImage,
    this.onToggleFlash,
    this.isTorchOn = false,
    this.finishWidget,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GlassContainer(
              padding: const EdgeInsets.all(10),
              borderRadius: 16,
              child: InkWell(
                onTap: () {
                  if (ModalRoute.of(context)?.isCurrent == true) {
                    Navigator.of(context).pop();
                  }
                },
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (finishWidget != null) ...[
                  finishWidget!,
                  const SizedBox(width: 12),
                ],
                if (onToggleFlash != null) ...[
                  GlassContainer(
                    padding: const EdgeInsets.all(10),
                    borderRadius: 16,
                    backgroundColor: isTorchOn
                        ? const Color(0xFFFBBF24).withValues(alpha: 0.25)
                        : null,
                    child: InkWell(
                      onTap: onToggleFlash,
                      child: Icon(
                        isTorchOn
                            ? Icons.flash_on_rounded
                            : Icons.flash_off_rounded,
                        color: isTorchOn
                            ? const Color(0xFFFBBF24)
                            : Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                if (onPickImage != null)
                  GlassContainer(
                    padding: const EdgeInsets.all(10),
                    borderRadius: 16,
                    child: InkWell(
                      onTap: onPickImage,
                      child: const Icon(
                        Icons.photo_library_outlined,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ScannerControlsRow extends StatelessWidget {
  final double currentZoom;
  final ValueChanged<double> onZoomChanged;
  final ValueChanged<double> onZoomChangeEnd;
  final bool isMultiScan;
  final ValueChanged<bool> onMultiScanChanged;
  final bool showMultiScanToggle;

  const ScannerControlsRow({
    super.key,
    required this.currentZoom,
    required this.onZoomChanged,
    required this.onZoomChangeEnd,
    required this.isMultiScan,
    required this.onMultiScanChanged,
    this.showMultiScanToggle = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Multi-Scan Toggle
          if (showMultiScanToggle)
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
          
          if (showMultiScanToggle)
            const SizedBox(height: 12),

          // Zoom Control
          Row(
            children: [
              Expanded(
                child: GlassContainer(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  borderRadius: 30,
                  backgroundColor: Colors.black.withValues(alpha: 0.4),
                  child: Row(
                    children: [
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2.0,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 8.0,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 16.0,
                            ),
                          ),
                          child: Slider(
                            value: currentZoom.clamp(1.0, 2.5),
                            min: 1.0,
                            max: 2.5,
                            activeColor: Colors.white,
                            inactiveColor: Colors.white24,
                            onChanged: onZoomChanged,
                            onChangeEnd: onZoomChangeEnd,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
