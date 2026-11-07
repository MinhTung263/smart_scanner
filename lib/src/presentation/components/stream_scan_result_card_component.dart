import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants/stream_scan_constants.dart';
import '../../domain/entities/stream_scan_card_item.dart';
import '../controllers/stream_scan_controller.dart';

/// Builder signature for custom stream scan result cards.
/// The returned widget fills one fixed-height layer of the stack.
typedef StreamScanCardBuilder =
    Widget Function(BuildContext context, StreamScanCardItem item);

/// Shows scanned products as stacked layers, most recent scan in front.
/// Layers are keyed by code, so a re-scanned product slides to the front.
class StreamScanResultCardComponent extends StatelessWidget {
  /// Controller supplying reactive card state.
  final StreamScanController controller;

  /// Custom builder override for the content of each layer.
  final StreamScanCardBuilder? customBuilder;

  /// Creates a stream scan result card component.
  const StreamScanResultCardComponent({
    super.key,
    required this.controller,
    this.customBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<List<StreamScanCardItem>>(
        valueListenable: controller.recentCards,
        builder: (BuildContext context, List<StreamScanCardItem> cards, _) {
          final int maxLayers = controller.options.maxVisibleCards;
          if (cards.isEmpty || maxLayers <= 0) {
            return const SizedBox.shrink();
          }

          final int count = math.min(maxLayers, cards.length);
          final double stackHeight =
              StreamScanConstants.layerCardHeight +
              (maxLayers - 1) * StreamScanConstants.layerOffsetY;

          return SizedBox(
            height: stackHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                // Paint back to front so the newest layer sits on top.
                for (int depth = count - 1; depth >= 0; depth--)
                  _buildLayer(context, cards[depth], depth, maxLayers),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLayer(
    BuildContext context,
    StreamScanCardItem item,
    int depth,
    int maxLayers,
  ) {
    // Front layer stays anchored at the bottom; older layers peek above it.
    final double inset = depth * StreamScanConstants.layerInsetX;
    return AnimatedPositioned(
      key: ValueKey<String>('layer_${item.code}'),
      duration: StreamScanConstants.layerAnimationDuration,
      curve: Curves.easeOutQuart,
      top: (maxLayers - 1 - depth) * StreamScanConstants.layerOffsetY,
      left: inset,
      right: inset,
      height: StreamScanConstants.layerCardHeight,
      child: customBuilder != null
          ? customBuilder!(context, item)
          : _buildDefaultCard(item),
    );
  }

  Widget _buildDefaultCard(StreamScanCardItem item) {
    final bool isProcessing = item.isProcessing;
    final int? quantity = item.displayQuantity;
    final Color accentColor = isProcessing
        ? const Color(StreamScanConstants.warningColorValue)
        : const Color(StreamScanConstants.successColorValue);

    return Container(
      key: ValueKey<String>('card_${item.code}'),
      padding: const EdgeInsets.symmetric(
        horizontal: StreamScanConstants.defaultComponentPadding,
      ),
      decoration: BoxDecoration(
        color: const Color(StreamScanConstants.cardBackgroundColorValue),
        borderRadius: BorderRadius.circular(
          StreamScanConstants.defaultCardBorderRadius,
        ),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.35),
          width: 1.0,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: StreamScanConstants.layerShadowBlur,
            offset: const Offset(0.0, 4.0),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          if (isProcessing)
            SizedBox(
              width: 20.0,
              height: 20.0,
              child: CircularProgressIndicator(
                strokeWidth: 2.0,
                valueColor: AlwaysStoppedAnimation<Color>(accentColor),
              ),
            )
          else
            Icon(Icons.check_circle_rounded, color: accentColor, size: 20.0),
          const SizedBox(width: StreamScanConstants.defaultItemSpacing),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.title ?? item.code,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14.0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.subtitle != null && item.subtitle!.isNotEmpty)
                  Text(
                    item.subtitle!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12.0,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (quantity != null || isProcessing)
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                if (quantity != null) _buildQuantityBadge(quantity),
                if (isProcessing)
                  Padding(
                    padding: const EdgeInsets.only(top: 2.0),
                    child: Text(
                      '+${item.pendingQuantity} '
                      '${StreamScanConstants.layerPendingSuffix}',
                      style: const TextStyle(
                        color: Color(StreamScanConstants.warningColorValue),
                        fontSize: 11.0,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildQuantityBadge(int quantity) {
    const Color badgeColor = Color(StreamScanConstants.layerQuantityColorValue);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(
          StreamScanConstants.defaultChipBorderRadius,
        ),
      ),
      child: Text(
        '${StreamScanConstants.layerQuantityPrefix}$quantity',
        style: const TextStyle(
          color: badgeColor,
          fontSize: 14.0,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
