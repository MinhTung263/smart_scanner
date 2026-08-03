import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import '../../data/services/barcode_scanner_service.dart';

class BarcodeOverlayPainter extends CustomPainter {
  final List<Barcode> barcodes;
  final Size imageSize;
  final Size screenSize;
  final Color color;
  final double pulseValue;
  final double lockValue;
  final double zoomLevel;

  BarcodeOverlayPainter({
    required this.barcodes,
    required this.imageSize,
    required this.screenSize,
    this.color = const Color(0xFF10B981), // ZaloPay Emerald Green
    this.pulseValue = 0.0,
    this.lockValue = 1.0,
    this.zoomLevel = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (barcodes.isEmpty) return;

    // Banking App Standard Lock-In & Un-Lock Exit Animation (Bidirectional 60fps):
    // Entry: 1.15x -> 1.0x (Fade In)
    // Exit (Animation back): 1.0x -> 1.15x (Fade Out smoothly)
    final double lockProgress = Curves.easeInOutCubic.transform(lockValue.clamp(0.0, 1.0));
    final double scale = 1.15 - 0.15 * lockProgress;
    final double opacity = lockProgress.clamp(0.0, 1.0);

    final Paint glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(alpha: (0.15 + pulseValue * 0.2) * opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0);

    final Paint corePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color.withValues(alpha: opacity);

    final Paint fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: 0.10 * opacity);

    for (final barcode in barcodes) {
      final Rect rawRect = BarcodeScannerService.mapMlKitRectToScreen(
        rawRect: barcode.boundingBox,
        previewSize: imageSize,
        screenSize: screenSize,
      );

      final Offset center = rawRect.center;

      final Rect rect = Rect.fromCenter(
        center: center,
        width: rawRect.width * scale,
        height: rawRect.height * scale,
      );

      // 1. Soft green background fill tint
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(10.0)),
        fillPaint,
      );

      // 2. Crisp corner brackets
      final path = _bracketPath(rect);
      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, corePaint);

      // 3. Clean Checkmark Icon Badge at Center (Banking App Standard)
      _drawCheckmarkBadge(canvas, center, opacity * lockProgress);

      // 4. Label (if display value present)
      if (barcode.displayValue != null && lockProgress > 0.6) {
        _drawLabel(canvas, rect, barcode.displayValue!);
      }
    }
  }

  void _drawCheckmarkBadge(Canvas canvas, Offset center, double scaleProgress) {
    if (scaleProgress <= 0.05) return;
    final double radius = 14.0 * scaleProgress;

    // Badge background glow
    canvas.drawCircle(
      center,
      radius + 4,
      Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: 0.25 * scaleProgress)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0),
    );

    // Badge solid green circle
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: scaleProgress),
    );

    // White Checkmark Icon
    final Path checkPath = Path()
      ..moveTo(center.dx - 4.5 * scaleProgress, center.dy + 0.5 * scaleProgress)
      ..lineTo(center.dx - 1.0 * scaleProgress, center.dy + 4.0 * scaleProgress)
      ..lineTo(center.dx + 5.0 * scaleProgress, center.dy - 3.5 * scaleProgress);

    canvas.drawPath(
      checkPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 * scaleProgress
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white.withValues(alpha: scaleProgress),
    );
  }

  /// Rounded corner brackets, matching the guide-frame style used elsewhere
  /// in the scanner instead of hard right-angle corners. Corner length scales
  /// with the box itself so tiny and large detections both look proportioned.
  Path _bracketPath(Rect rect) {
    double cornerLength = (rect.shortestSide * 0.22).clamp(12.0, 28.0);
    double radius = 8.0;

    final double halfShortSide = rect.shortestSide / 2;
    if (cornerLength > halfShortSide) cornerLength = halfShortSide.clamp(2.0, 28.0);
    if (radius > cornerLength / 2) radius = cornerLength / 2;

    final double left = rect.left;
    final double top = rect.top;
    final double right = rect.right;
    final double bottom = rect.bottom;
    final double cl = cornerLength;
    final double r = radius;

    return Path()
      // Top-Left
      ..moveTo(left, top + cl)
      ..lineTo(left, top + r)
      ..arcToPoint(Offset(left + r, top), radius: Radius.circular(r))
      ..lineTo(left + cl, top)
      // Top-Right
      ..moveTo(right - cl, top)
      ..lineTo(right - r, top)
      ..arcToPoint(Offset(right, top + r), radius: Radius.circular(r))
      ..lineTo(right, top + cl)
      // Bottom-Right
      ..moveTo(right, bottom - cl)
      ..lineTo(right, bottom - r)
      ..arcToPoint(Offset(right - r, bottom), radius: Radius.circular(r))
      ..lineTo(right - cl, bottom)
      // Bottom-Left
      ..moveTo(left + cl, bottom)
      ..lineTo(left + r, bottom)
      ..arcToPoint(Offset(left, bottom - r), radius: Radius.circular(r))
      ..lineTo(left, bottom - cl);
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
        oldDelegate.pulseValue != pulseValue ||
        oldDelegate.lockValue != lockValue;
  }
}
