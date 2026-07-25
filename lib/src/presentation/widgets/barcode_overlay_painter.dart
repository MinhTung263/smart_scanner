import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

class BarcodeOverlayPainter extends CustomPainter {
  final List<Barcode> barcodes;
  final Size imageSize;
  final Size screenSize;
  final Color color;

  BarcodeOverlayPainter({
    required this.barcodes,
    required this.imageSize,
    required this.screenSize,
    this.color = Colors.red,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Tạo hiệu ứng chớp tắt (pulse) dựa trên thời gian
    final int ms = DateTime.now().millisecondsSinceEpoch;
    final double pulse = (ms % 800) / 800.0; // 0.0 -> 1.0 mỗi 800ms
    
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0 + (pulse * 3) // Dày lên
      ..color = color.withAlpha((255 * (1.0 - pulse * 0.5)).toInt()); // Mờ dần

    final Paint backgroundPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.black.withAlpha(102);

    // Depending on rotation, imageSize might need its width/height swapped
    // For simplicity, we assume imageSize matches the orientation.
    // Real-world implementation for Android might need deeper platform logic 
    // to map exact ML kit coordinates to screen coordinates.
    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / imageSize.height;

    for (final barcode in barcodes) {
      final Rect boundingBox = barcode.boundingBox;
      final Rect rect = Rect.fromLTRB(
        boundingBox.left * scaleX,
        boundingBox.top * scaleY,
        boundingBox.right * scaleX,
        boundingBox.bottom * scaleY,
      );

      // Draw bounding box
      canvas.drawRect(rect, paint);

      // Draw value background
      canvas.drawRect(
          Rect.fromLTWH(rect.left, rect.top - 25, rect.width, 25),
          backgroundPaint);

      // Draw value
      if (barcode.displayValue != null) {
        final textSpan = TextSpan(
          text: barcode.displayValue,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        );
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout(
          minWidth: 0,
          maxWidth: size.width,
        );
        textPainter.paint(
          canvas,
          Offset(rect.left + 5, rect.top - 23),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant BarcodeOverlayPainter oldDelegate) {
    return oldDelegate.barcodes != barcodes ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.screenSize != screenSize ||
        oldDelegate.color != color;
  }
}
