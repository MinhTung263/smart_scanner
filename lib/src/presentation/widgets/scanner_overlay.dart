import 'package:flutter/material.dart';

class ScannerOverlay extends StatelessWidget {
  final Rect scanWindow;
  final double borderRadius;
  final double strokeWidth;
  final Color borderColor;
  final double cornerLength;
  final Color overlayColor;
  final double cornerOffset;

  const ScannerOverlay({
    Key? key,
    required this.scanWindow,
    this.borderRadius = 12.0,
    this.strokeWidth = 3.0,
    this.borderColor = Colors.white,
    this.cornerLength = 30.0,
    this.overlayColor = const Color(0x88000000),
    this.cornerOffset = 0.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Rect?>(
      tween: RectTween(begin: scanWindow, end: scanWindow),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      builder: (context, rect, child) {
        final currentRect = rect ?? scanWindow;
        return Stack(
          fit: StackFit.expand,
          children: [
            // Lớp làm mờ thực sự (Blur) kết hợp ClipPath để chừa phần khung quét ra
            ClipPath(
              clipper: _ScannerHoleClipper(
                holeRect: currentRect,
                radius: borderRadius,
              ),
              child: Container(
                color: overlayColor, // Phủ màu nền (bỏ hẳn blur để tối ưu mượt cho máy cấu hình yếu)
              ),
            ),
            // Vẽ 4 viền góc mỏ neo
            CustomPaint(
              painter: _ScannerOverlayPainter(
                scanWindow: currentRect,
                borderRadius: borderRadius,
                strokeWidth: strokeWidth,
                borderColor: borderColor,
                cornerLength: cornerLength,
                cornerOffset: cornerOffset,
                overlayColor:
                    Colors.transparent, // Không cần vẽ nền trong painter nữa
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ScannerHoleClipper extends CustomClipper<Path> {
  final Rect holeRect;
  final double radius;

  _ScannerHoleClipper({required this.holeRect, required this.radius});

  @override
  Path getClip(Size size) {
    return Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(holeRect, Radius.circular(radius)))
      ..fillType = PathFillType.evenOdd;
  }

  @override
  bool shouldReclip(covariant _ScannerHoleClipper oldClipper) {
    return oldClipper.holeRect != holeRect || oldClipper.radius != radius;
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  final Rect scanWindow;
  final double borderRadius;
  final double strokeWidth;
  final Color borderColor;
  final double cornerLength;
  final double cornerOffset;
  final Color overlayColor;

  _ScannerOverlayPainter({
    required this.scanWindow,
    required this.borderRadius,
    required this.strokeWidth,
    required this.borderColor,
    required this.cornerLength,
    required this.overlayColor,
    this.cornerOffset = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Không vẽ nền trong này nữa vì đã dùng BackdropFilter ở ngoài
    // Chỉ vẽ 4 góc viền

    // 2. Vẽ 4 góc cong
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.square;

    final double cl = cornerLength;
    final double left = scanWindow.left - cornerOffset;
    final double top = scanWindow.top - cornerOffset;
    final double right = scanWindow.right + cornerOffset;
    final double bottom = scanWindow.bottom + cornerOffset;
    final double r = borderRadius;

    // Góc trên - trái
    canvas.drawPath(
      Path()
        ..moveTo(left, top + cl)
        ..lineTo(left, top + r)
        ..arcToPoint(Offset(left + r, top), radius: Radius.circular(r))
        ..lineTo(left + cl, top),
      borderPaint,
    );

    // Góc trên - phải
    canvas.drawPath(
      Path()
        ..moveTo(right - cl, top)
        ..lineTo(right - r, top)
        ..arcToPoint(Offset(right, top + r), radius: Radius.circular(r))
        ..lineTo(right, top + cl),
      borderPaint,
    );

    // Góc dưới - trái
    canvas.drawPath(
      Path()
        ..moveTo(left, bottom - cl)
        ..lineTo(left, bottom - r)
        ..arcToPoint(Offset(left + r, bottom), radius: Radius.circular(r), clockwise: false)
        ..lineTo(left + cl, bottom),
      borderPaint,
    );

    // Góc dưới - phải
    canvas.drawPath(
      Path()
        ..moveTo(right, bottom - cl)
        ..lineTo(right, bottom - r)
        ..arcToPoint(Offset(right - r, bottom), radius: Radius.circular(r))
        ..lineTo(right - cl, bottom),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) {
    return oldDelegate.scanWindow != scanWindow ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.cornerLength != cornerLength ||
        oldDelegate.overlayColor != overlayColor;
  }
}
