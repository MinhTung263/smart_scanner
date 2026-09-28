import 'package:flutter/material.dart';

import '../../smart_scanner.dart';

/// A switch bound to `SmartScanner.vibrateOnScan`.
///
/// Put it anywhere in the host app (a settings screen, a `ListTile`'s
/// `trailing`, …); flipping it changes and saves scan vibration for every
/// scanner opened through `SmartScanner`.
class SmartScannerVibrationSwitch extends StatelessWidget {
  final Color? activeTrackColor;

  const SmartScannerVibrationSwitch({super.key, this.activeTrackColor});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SmartScanner.vibrateOnScan,
      builder: (context, vibrate, _) => Switch.adaptive(
        value: vibrate,
        activeTrackColor: activeTrackColor,
        onChanged: SmartScanner.setVibrateOnScan,
      ),
    );
  }
}
