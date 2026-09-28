import 'package:flutter/material.dart';

import '../../smart_scanner_settings.dart';

/// A switch bound to [SmartScannerSettings.vibrateOnScan].
///
/// Put it anywhere in the host app (a settings screen, a `ListTile`'s
/// `trailing`, …); flipping it changes and saves scan vibration for every
/// scanner opened through `SmartScanner`.
class SmartScannerVibrationSwitch extends StatefulWidget {
  final Color? activeTrackColor;

  const SmartScannerVibrationSwitch({super.key, this.activeTrackColor});

  @override
  State<SmartScannerVibrationSwitch> createState() =>
      _SmartScannerVibrationSwitchState();
}

class _SmartScannerVibrationSwitchState
    extends State<SmartScannerVibrationSwitch> {
  @override
  void initState() {
    super.initState();
    SmartScannerSettings.load();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SmartScannerSettings.vibrateOnScan,
      builder: (context, vibrate, _) => Switch.adaptive(
        value: vibrate,
        activeTrackColor: widget.activeTrackColor,
        onChanged: SmartScannerSettings.setVibrateOnScan,
      ),
    );
  }
}
