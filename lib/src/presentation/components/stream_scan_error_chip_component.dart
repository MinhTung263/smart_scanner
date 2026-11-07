import 'package:flutter/material.dart';

import '../../core/constants/stream_scan_constants.dart';
import '../../domain/entities/stream_scan_card_item.dart';
import '../controllers/stream_scan_controller.dart';

/// Builder signature for custom stream scan error chips.
typedef StreamScanErrorChipBuilder =
    Widget Function(BuildContext context, StreamScanErrorChipItem item);

/// Displays error alert chips for rejected barcode scans.
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
        builder: (BuildContext context, List<StreamScanErrorChipItem> chips, _) {
          if (chips.isEmpty) {
            return const SizedBox.shrink();
          }

          final int limit = controller.options.maxVisibleChips;
          final List<StreamScanErrorChipItem> visibleChips =
              chips.take(limit).toList();

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: visibleChips.map((StreamScanErrorChipItem item) {
              if (customBuilder != null) {
                return customBuilder!(context, item);
              }
              return _buildDefaultChip(context, item);
            }).toList(),
          );
        },
      ),
    );
  }

  Widget _buildDefaultChip(BuildContext context, StreamScanErrorChipItem item) {
    const Color errorColor = Color(StreamScanConstants.errorColorValue);

    final String displayText =
        '⚠ ${item.message} · ${item.unaddedQuantity} SP (${item.code}) ${StreamScanConstants.defaultUnaddedSuffix}';

    return Container(
      key: ValueKey<String>('chip_${item.id}'),
      margin: const EdgeInsets.only(
        bottom: StreamScanConstants.defaultItemSpacing,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: StreamScanConstants.defaultComponentPadding,
        vertical: 10.0,
      ),
      decoration: BoxDecoration(
        color: const Color(StreamScanConstants.cardBackgroundColorValue),
        borderRadius: BorderRadius.circular(
          StreamScanConstants.defaultChipBorderRadius,
        ),
        border: Border.all(
          color: errorColor.withValues(alpha: 0.5),
          width: 1.0,
        ),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.warning_amber_rounded,
            color: errorColor,
            size: 20.0,
          ),
          const SizedBox(width: StreamScanConstants.defaultItemSpacing),
          Expanded(
            child: Text(
              displayText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12.0,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
