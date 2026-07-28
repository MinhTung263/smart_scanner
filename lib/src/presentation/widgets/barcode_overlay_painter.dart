import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import '../../data/services/barcode_scanner_service.dart';

class BarcodeOverlayPainter extends CustomPainter {
  final List<Barcode> barcodes;
  final Size imageSize;
  final Size screenSize;
  final Color color;
  final double pulseValue;
  final double zoomLevel;

  BarcodeOverlayPainter({
    required this.barcodes,
    required this.imageSize,
    required this.screenSize,
    this.color = Colors.red,
    this.pulseValue = 0.0,
    this.zoomLevel = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Soft breathing halo behind the crisp bracket, so the "found" state feels
    // alive instead of a static rectangle slapped on the frame.
    final Paint glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color.withAlpha((255 * (0.16 + pulseValue * 0.26)).toInt())
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7.0);

    final Paint corePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    final Paint fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withAlpha(18);

    for (final barcode in barcodes) {
      final Rect rect = BarcodeScannerService.mapMlKitRectToScreen(
        rawRect: barcode.boundingBox,
        previewSize: imageSize,
        screenSize: screenSize,
      );

      // Faint tinted highlight so the found area reads as "selected" even
      // between the corner brackets, not just four disconnected marks.
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(10.0)),
        fillPaint,
      );

      final path = _bracketPath(rect);
      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, corePaint);

      if (barcode.displayValue != null) {
        _drawLabel(canvas, rect, barcode.displayValue!);
      }
    }
  }

  /// Rounded corner brackets, matching the guide-frame style used elsewhere
  /// in the scanner instead of hard right-angle corners. Corner length scales
  /// with the box itself so tiny and large detections both look proportioned.
  Path _bracketPath(Rect rect) {
    double cornerLength = (rect.shortestSide * 0.22).clamp(10.0, 26.0);
    double radius = 6.0;

    final double halfShortSide = rect.shortestSide / 2;
    if (cornerLength > halfShortSide) cornerLength = halfShortSide.clamp(2.0, 26.0);
    if (radius > cornerLength / 2) radius = cornerLength / 2;

    final double left = rect.left;
    final double top = rect.top;
    final double right = rect.right;
    final double bottom = rect.bottom;
    final double cl = cornerLength;
    final double r = radius;

    return Path()
      // top-left
      ..moveTo(left, top + cl)
      ..lineTo(left, top + r)
      ..arcToPoint(Offset(left + r, top), radius: Radius.circular(r))
      ..lineTo(left + cl, top)
      // top-right
      ..moveTo(right - cl, top)
      ..lineTo(right - r, top)
      ..arcToPoint(Offset(right, top + r), radius: Radius.circular(r))
      ..lineTo(right, top + cl)
      // bottom-right
      ..moveTo(right, bottom - cl)
      ..lineTo(right, bottom - r)
      ..arcToPoint(Offset(right - r, bottom), radius: Radius.circular(r))
      ..lineTo(right - cl, bottom)
      // bottom-left
      ..moveTo(left, bottom - cl)
      ..lineTo(left, bottom - r)
      ..arcToPoint(Offset(left + r, bottom), radius: Radius.circular(r), clockwise: false)
      ..lineTo(left + cl, bottom);
  }

  void _drawLabel(Canvas canvas, Rect rect, String text) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 260);

    const double horizontalPadding = 12.0;
    const double dotDiameter = 6.0;
    const double dotGap = 8.0;
    const double labelHeight = 28.0;

    final double labelWidth =
        horizontalPadding * 2 + dotDiameter + dotGap + textPainter.width;

    // Prefer sitting just above the box; drop below it if there isn't room
    // (e.g. the barcode sits near the top edge of the screen).
    final bool fitsAbove = rect.top - labelHeight - 8 >= 0;
    final double labelTop =
        fitsAbove ? rect.top - labelHeight - 8 : rect.bottom + 8;

    double labelLeft = rect.center.dx - labelWidth / 2;
    final double maxLeft = screenSize.width - labelWidth - 4.0;
    labelLeft = labelLeft.clamp(4.0, maxLeft > 4.0 ? maxLeft : 4.0);

    final RRect labelRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(labelLeft, labelTop, labelWidth, labelHeight),
      const Radius.circular(14.0),
    );

    final Paint labelBgPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.black.withAlpha(170);
    canvas.drawRRect(labelRRect, labelBgPaint);

    canvas.drawCircle(
      Offset(labelLeft + horizontalPadding + dotDiameter / 2, labelTop + labelHeight / 2),
      dotDiameter / 2,
      Paint()..color = color,
    );

    textPainter.paint(
      canvas,
      Offset(
        labelLeft + horizontalPadding + dotDiameter + dotGap,
        labelTop + (labelHeight - textPainter.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant BarcodeOverlayPainter oldDelegate) {
    return oldDelegate.barcodes != barcodes ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.screenSize != screenSize ||
        oldDelegate.zoomLevel != zoomLevel ||
        oldDelegate.color != color ||
        oldDelegate.pulseValue != pulseValue;
  }
}
