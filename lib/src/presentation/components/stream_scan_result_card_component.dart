import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/constants/stream_scan_constants.dart';
import '../../domain/entities/stream_scan_card_item.dart';
import '../controllers/stream_scan_controller.dart';

/// Builder signature for custom stream scan result cards.
/// The returned widget replaces the content of the front card.
typedef StreamScanCardBuilder =
    Widget Function(BuildContext context, StreamScanCardItem item);

/// Card of the most recently scanned product, with decorative layers below.
/// Hidden entirely until the first code is scanned.
class StreamScanResultCardComponent extends StatelessWidget {
  /// Controller supplying reactive card state.
  final StreamScanController controller;

  /// Custom builder override for the content of the front card.
  final StreamScanCardBuilder? customBuilder;

  /// Creates a stream scan result card component.
  const StreamScanResultCardComponent({
    super.key,
    required this.controller,
    this.customBuilder,
  });

  @override
  Widget build(BuildContext context) {
    const int layers = StreamScanConstants.decorativeLayerCount;
    const double stackHeight =
        StreamScanConstants.productCardHeight +
        layers * StreamScanConstants.decorativeLayerOffsetY;

    return RepaintBoundary(
      child: ValueListenableBuilder<List<StreamScanCardItem>>(
        valueListenable: controller.recentCards,
        builder: (BuildContext context, List<StreamScanCardItem> cards, _) {
          // Spec: no card at all until the first code is scanned.
          if (cards.isEmpty) {
            return const SizedBox.shrink();
          }
          final StreamScanCardItem front = cards.first;
          return SizedBox(
            height: stackHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                // Decorative layers only; drawn farthest first.
                for (int depth = layers; depth >= 1; depth--)
                  _buildDecorativeLayer(depth),
                Positioned(
                  top: 0.0,
                  left: 0.0,
                  right: 0.0,
                  height: StreamScanConstants.productCardHeight,
                  child: customBuilder != null
                      ? customBuilder!(context, front)
                      : _buildCardShell(
                          child: _buildProductContent(context, front),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDecorativeLayer(int depth) {
    final double inset = depth * StreamScanConstants.decorativeLayerInsetX;
    final double alpha = 0.75 - depth * 0.18;
    return Positioned(
      top: depth * StreamScanConstants.decorativeLayerOffsetY,
      left: inset,
      right: inset,
      height: StreamScanConstants.productCardHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(
            StreamScanConstants.productCardColorValue,
          ).withValues(alpha: alpha),
          borderRadius: BorderRadius.circular(
            StreamScanConstants.defaultCardBorderRadius,
          ),
        ),
      ),
    );
  }

  Widget _buildCardShell({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      decoration: BoxDecoration(
        color: const Color(StreamScanConstants.productCardColorValue),
        borderRadius: BorderRadius.circular(
          StreamScanConstants.defaultCardBorderRadius,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 8.0,
            offset: const Offset(0.0, 4.0),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildProductContent(BuildContext context, StreamScanCardItem item) {
    final bool isLookingUp = !item.hasBeenAccepted;
    return Row(
      key: ValueKey<String>('card_${item.code}'),
      children: <Widget>[
        _buildThumbnail(context, item.imageUrl),
        const SizedBox(width: 12.0),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                item.title ??
                    (isLookingUp
                        ? StreamScanConstants.defaultProcessingLabel
                        : item.code),
                style: const TextStyle(
                  color: Color(StreamScanConstants.productTitleColorValue),
                  fontWeight: FontWeight.w700,
                  fontSize: 14.0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2.0),
              Text(
                item.code,
                style: const TextStyle(
                  color: Color(StreamScanConstants.productSubtitleColorValue),
                  fontSize: 12.0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: StreamScanConstants.defaultItemSpacing),
        if (isLookingUp)
          const SizedBox(
            width: 18.0,
            height: 18.0,
            child: CircularProgressIndicator(
              strokeWidth: 2.0,
              valueColor: AlwaysStoppedAnimation<Color>(
                Color(StreamScanConstants.badgeTextColorValue),
              ),
            ),
          )
        else
          _buildQuantityBadge(item.acceptedQuantity),
        const SizedBox(width: 4.0),
      ],
    );
  }

  Widget _buildThumbnail(BuildContext context, String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return _buildPlaceholderThumbnail();
    }
    // Decode at display size to keep memory low on weak devices.
    final int cacheSize =
        (StreamScanConstants.thumbnailSize *
                MediaQuery.devicePixelRatioOf(context))
            .round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8.0),
      child: Image.network(
        imageUrl,
        width: StreamScanConstants.thumbnailSize,
        height: StreamScanConstants.thumbnailSize,
        fit: BoxFit.cover,
        cacheWidth: cacheSize,
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
            _buildPlaceholderThumbnail(),
      ),
    );
  }

  Widget _buildPlaceholderThumbnail() {
    return Container(
      width: StreamScanConstants.thumbnailSize,
      height: StreamScanConstants.thumbnailSize,
      decoration: BoxDecoration(
        color: const Color(StreamScanConstants.badgeBackgroundColorValue),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: const Icon(
        CupertinoIcons.barcode,
        color: Color(StreamScanConstants.badgeTextColorValue),
        size: 26.0,
      ),
    );
  }

  Widget _buildQuantityBadge(int quantity) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: const Color(StreamScanConstants.badgeBackgroundColorValue),
        borderRadius: BorderRadius.circular(10.0),
      ),
      child: Text(
        '${StreamScanConstants.quantityBadgePrefix}$quantity',
        style: const TextStyle(
          color: Color(StreamScanConstants.badgeTextColorValue),
          fontSize: 15.0,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
