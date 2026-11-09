import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/constants/stream_scan_constants.dart';
import '../controllers/stream_scan_controller.dart';

/// "Quét liên tục" switch. On by default every time the screen opens.
class StreamScanContinuousToggleComponent extends StatelessWidget {
  /// Controller owning the continuous mode flag.
  final StreamScanController controller;

  /// Creates the continuous scan toggle.
  const StreamScanContinuousToggleComponent({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: controller.isContinuous,
      builder: (BuildContext context, bool isOn, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CupertinoSwitch(
              key: const ValueKey<String>('stream_scan_continuous_toggle'),
              value: isOn,
              activeTrackColor: const Color(
                StreamScanConstants.toggleActiveColorValue,
              ),
              onChanged: controller.setContinuousMode,
            ),
            const SizedBox(width: StreamScanConstants.defaultItemSpacing),
            const Text(
              StreamScanConstants.continuousToggleLabel,
              style: TextStyle(
                color: Colors.white,
                fontSize: 15.0,
                fontWeight: FontWeight.w600,
                shadows: <Shadow>[
                  Shadow(color: Colors.black54, blurRadius: 4.0),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
