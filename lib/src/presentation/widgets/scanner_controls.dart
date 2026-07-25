import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'glass_container.dart';

class ScannerTopBar extends StatelessWidget {
  final VoidCallback? onPickImage;
  final Widget? finishWidget;

  const ScannerTopBar({super.key, this.onPickImage, this.finishWidget});

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
                onTap: () => Navigator.of(context).pop(),
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

  const ScannerControlsRow({
    super.key,
    required this.currentZoom,
    required this.onZoomChanged,
    required this.onZoomChangeEnd,
    required this.isMultiScan,
    required this.onMultiScanChanged,
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
          GlassContainer(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            borderRadius: 30,
            backgroundColor: Colors.black.withOpacity(0.4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isMultiScan
                      ? Icons.library_add_check
                      : Icons.library_add_check_outlined,
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
                    activeColor: Colors.greenAccent.shade400,
                    trackColor: Colors.white.withOpacity(0.3),
                    onChanged: (value) {
                      onMultiScanChanged(value);
                      HapticFeedback.lightImpact();
                    },
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 12),

          // Zoom Control
          Row(
            children: [
              Expanded(
                child: GlassContainer(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  borderRadius: 30,
                  backgroundColor: Colors.black.withOpacity(0.4),
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
                            value: currentZoom,
                            min: 1.0,
                            max: 4.0,
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
