import 'package:flutter/material.dart';

import '../../core/constants/stream_scan_constants.dart';

/// Green laser line sweeping up and down inside the scan frame.
/// Repaints only itself; the animation stops when [active] is false.
class StreamScanLaserComponent extends StatefulWidget {
  /// Whether the laser is animating and visible.
  final bool active;

  /// Creates a laser sweep for the scan frame.
  const StreamScanLaserComponent({super.key, this.active = true});

  @override
  State<StreamScanLaserComponent> createState() =>
      _StreamScanLaserComponentState();
}

class _StreamScanLaserComponentState extends State<StreamScanLaserComponent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: StreamScanConstants.laserSweepDuration,
  );

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(StreamScanLaserComponent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (widget.active) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _LaserPainter(progress: _controller),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _LaserPainter extends CustomPainter {
  final Animation<double> progress;

  _LaserPainter({required this.progress}) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    const double margin = 8.0;
    final double t = Curves.easeInOut.transform(progress.value);
    final double y = margin + t * (size.height - 2 * margin);
    const Color color = Color(StreamScanConstants.laserColorValue);

    final Rect lineRect = Rect.fromLTWH(margin, y - 1.0, size.width - 2 * margin, 2.0);
    final Paint linePaint = Paint()
      ..shader = LinearGradient(
        colors: <Color>[
          color.withValues(alpha: 0.0),
          color,
          color.withValues(alpha: 0.0),
        ],
      ).createShader(lineRect);
    canvas.drawRect(lineRect, linePaint);

    // Soft glow around the line.
    final Paint glowPaint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
    canvas.drawRect(lineRect.inflate(1.5), glowPaint);
  }

  @override
  bool shouldRepaint(_LaserPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
