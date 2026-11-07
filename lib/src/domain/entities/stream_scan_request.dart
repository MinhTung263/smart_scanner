import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

/// Short alias for [StreamScanRequest].
typedef ScanRequest = StreamScanRequest;

/// Request payload emitted for each scanned barcode batch.
class StreamScanRequest {
  /// Raw string value of the scanned barcode.
  final String code;

  /// Barcode format recognized by the scanner.
  final BarcodeFormat format;

  /// Number of scans aggregated into this request.
  final int quantity;

  /// Creates a new stream scan request.
  const StreamScanRequest({
    required this.code,
    this.format = BarcodeFormat.unknown,
    this.quantity = 1,
  });

  /// Creates a copy with optional updated fields.
  StreamScanRequest copyWith({
    String? code,
    BarcodeFormat? format,
    int? quantity,
  }) {
    return StreamScanRequest(
      code: code ?? this.code,
      format: format ?? this.format,
      quantity: quantity ?? this.quantity,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StreamScanRequest &&
          runtimeType == other.runtimeType &&
          code == other.code &&
          format == other.format &&
          quantity == other.quantity;

  @override
  int get hashCode => Object.hash(code, format, quantity);

  @override
  String toString() =>
      'StreamScanRequest(code: $code, format: $format, quantity: $quantity)';
}
