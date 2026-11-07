import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

/// Report containing detected barcodes and image quality flags.
class StreamFrameReport {
  /// Decoded barcodes sorted from center outwards.
  final List<Barcode> barcodes;

  /// Indicates if frame is determined to be blurry.
  final bool isBlurry;

  /// Indicates if frame has specular glare.
  final bool hasGlare;

  /// Indicates if camera or subject is moving.
  final bool isMoving;

  /// Creates a report for a processed stream frame.
  const StreamFrameReport({
    required this.barcodes,
    this.isBlurry = false,
    this.hasGlare = false,
    this.isMoving = false,
  });
}
