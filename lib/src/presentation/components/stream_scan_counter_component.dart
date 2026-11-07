import 'package:flutter/material.dart';

import '../../core/constants/stream_scan_constants.dart';
import '../../domain/entities/stream_scan_card_item.dart';
import '../controllers/stream_scan_controller.dart';

/// Read-only pill "Mặt hàng: N | Số lượng: M" for the current session.
class StreamScanCounterComponent extends StatelessWidget {
  /// Controller supplying the session counter.
  final StreamScanController controller;

  /// Creates a session counter pill.
  const StreamScanCounterComponent({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<StreamScanCounter>(
        valueListenable: controller.counter,
        builder: (BuildContext context, StreamScanCounter counter, _) {
          return Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 14.0,
              vertical: 8.0,
            ),
            decoration: BoxDecoration(
              color: const Color(
                StreamScanConstants.counterBackgroundColorValue,
              ),
              borderRadius: BorderRadius.circular(20.0),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _label(StreamScanConstants.counterItemsLabel),
                _value('${counter.itemCount}', Colors.white),
                Container(
                  width: 1.0,
                  height: 14.0,
                  margin: const EdgeInsets.symmetric(horizontal: 10.0),
                  color: Colors.white38,
                ),
                _label(StreamScanConstants.counterQuantityLabel),
                _value(
                  '${counter.totalQuantity}',
                  const Color(StreamScanConstants.counterQuantityColorValue),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      '$text ',
      style: const TextStyle(color: Colors.white70, fontSize: 13.0),
    );
  }

  Widget _value(String text, Color color) {
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 13.0,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}
