import 'package:flutter/material.dart';

import '../../core/constants/stream_scan_constants.dart';
import '../controllers/stream_scan_controller.dart';

/// Builder signature for custom slow network indicator.
typedef StreamScanSlowNetworkBuilder = Widget Function(BuildContext context);

/// Displays visual hint when network requests exceed slow hint threshold.
class StreamScanSlowNetworkComponent extends StatelessWidget {
  /// Controller supplying reactive slow network state.
  final StreamScanController controller;

  /// Custom builder override for slow network UI.
  final StreamScanSlowNetworkBuilder? customBuilder;

  /// Creates a stream scan slow network indicator component.
  const StreamScanSlowNetworkComponent({
    super.key,
    required this.controller,
    this.customBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<bool>(
        valueListenable: controller.isNetworkSlow,
        builder: (BuildContext context, bool isSlow, _) {
          if (!isSlow) {
            return const SizedBox.shrink();
          }

          if (customBuilder != null) {
            return customBuilder!(context);
          }

          return _buildDefaultIndicator(context);
        },
      ),
    );
  }

  Widget _buildDefaultIndicator(BuildContext context) {
    const Color warningColor = Color(StreamScanConstants.warningColorValue);

    return Container(
      key: const ValueKey<String>('slow_network_indicator'),
      margin: const EdgeInsets.only(
        bottom: StreamScanConstants.defaultItemSpacing,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: StreamScanConstants.defaultComponentPadding,
        vertical: 8.0,
      ),
      decoration: BoxDecoration(
        color: const Color(StreamScanConstants.cardBackgroundColorValue),
        borderRadius: BorderRadius.circular(
          StreamScanConstants.defaultChipBorderRadius,
        ),
        border: Border.all(
          color: warningColor.withValues(alpha: 0.5),
          width: 1.0,
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 16.0,
            height: 16.0,
            child: CircularProgressIndicator(
              strokeWidth: 2.0,
              valueColor: AlwaysStoppedAnimation<Color>(warningColor),
            ),
          ),
          SizedBox(width: StreamScanConstants.defaultItemSpacing),
          Text(
            StreamScanConstants.defaultSlowNetworkMessage,
            style: TextStyle(
              color: warningColor,
              fontSize: 12.0,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
