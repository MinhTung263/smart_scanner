import 'package:flutter/material.dart';

import '../../core/constants/stream_scan_constants.dart';
import '../../domain/entities/stream_scan_card_item.dart';
import '../controllers/stream_scan_controller.dart';

/// Builder signature for custom stream scan error chips.
typedef StreamScanErrorChipBuilder =
    Widget Function(BuildContext context, StreamScanErrorChipItem item);

/// Toast chips above the scan frame: red error, green success, dark info.
/// Shows the host message only, newest first, up to `maxVisibleChips`.
class StreamScanErrorChipComponent extends StatelessWidget {
  /// Controller supplying reactive error chip state.
  final StreamScanController controller;

  /// Custom builder override for error chip UI.
  final StreamScanErrorChipBuilder? customBuilder;

  /// Creates a stream scan error chip component.
  const StreamScanErrorChipComponent({
    super.key,
    required this.controller,
    this.customBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<List<StreamScanErrorChipItem>>(
        valueListenable: controller.errorChips,
        builder:
            (BuildContext context, List<StreamScanErrorChipItem> chips, _) {
              if (chips.isEmpty) {
                return const SizedBox.shrink();
              }

              final int limit = controller.options.maxVisibleChips;
              final List<StreamScanErrorChipItem> visibleChips = chips
                  .take(limit)
                  .toList();

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: visibleChips.map((StreamScanErrorChipItem item) {
                  if (customBuilder != null) {
                    return customBuilder!(context, item);
                  }
                  return _buildDefaultChip(item);
                }).toList(),
              );
            },
      ),
    );
  }

  Widget _buildDefaultChip(StreamScanErrorChipItem item) {
    final Color background = switch (item.kind) {
      StreamScanChipKind.error => const Color(
        StreamScanConstants.errorColorValue,
      ),
      StreamScanChipKind.success => const Color(
        StreamScanConstants.successColorValue,
      ),
      StreamScanChipKind.info => const Color(
        StreamScanConstants.cardBackgroundColorValue,
      ).withValues(alpha: 0.9),
    };
    final IconData icon = switch (item.kind) {
      StreamScanChipKind.error => Icons.error_outline_rounded,
      StreamScanChipKind.success => Icons.check_circle_outline_rounded,
      StreamScanChipKind.info => Icons.info_outline_rounded,
    };
    return Container(
      key: ValueKey<String>('chip_${item.id}'),
      margin: const EdgeInsets.only(
        bottom: StreamScanConstants.defaultItemSpacing,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 9.0),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(
          StreamScanConstants.defaultChipBorderRadius,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: Colors.white, size: 18.0),
          const SizedBox(width: StreamScanConstants.defaultItemSpacing),
          Flexible(
            child: Text(
              item.message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.0,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
