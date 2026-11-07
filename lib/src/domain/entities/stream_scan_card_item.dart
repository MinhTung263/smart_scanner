import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

/// Processing status of a scanned barcode card.
enum StreamScanCardStatus {
  /// At least one scan of this code is still waiting for the host.
  processing,

  /// Every scan of this code has been answered by the host.
  accepted,
}

/// Presentation item for one product layer, kept per code for the session.
class StreamScanCardItem {
  /// Scanned barcode string value.
  final String code;

  /// Barcode format recognized by the camera.
  final BarcodeFormat format;

  /// Optional item title returned from the latest accept response.
  final String? title;

  /// Optional item subtitle or price from the latest accept response.
  final String? subtitle;

  /// Optional item count in cart from the latest accept response.
  final int? totalInCart;

  /// Scans counted but not yet answered by the host (in-flight or queued).
  final int pendingQuantity;

  /// Scans of this code accepted by the host during this session.
  final int acceptedQuantity;

  /// Timestamp when this item was last scanned or updated.
  final DateTime timestamp;

  /// Creates a stream scan card item.
  const StreamScanCardItem({
    required this.code,
    this.format = BarcodeFormat.unknown,
    this.title,
    this.subtitle,
    this.totalInCart,
    this.pendingQuantity = 0,
    this.acceptedQuantity = 0,
    required this.timestamp,
  });

  /// Processing while any scan of this code awaits the host.
  StreamScanCardStatus get status => pendingQuantity > 0
      ? StreamScanCardStatus.processing
      : StreamScanCardStatus.accepted;

  /// Whether this item is currently in processing state.
  bool get isProcessing => status == StreamScanCardStatus.processing;

  /// Whether every scan of this item has been answered.
  bool get isAccepted => status == StreamScanCardStatus.accepted;

  /// Whether the host has accepted this code at least once.
  bool get hasBeenAccepted => acceptedQuantity > 0;

  /// Quantity to show: host cart total, else session accepted count.
  int? get displayQuantity =>
      totalInCart ?? (hasBeenAccepted ? acceptedQuantity : null);

  /// Creates a copy with optional updated fields.
  StreamScanCardItem copyWith({
    BarcodeFormat? format,
    String? title,
    String? subtitle,
    int? totalInCart,
    int? pendingQuantity,
    int? acceptedQuantity,
    DateTime? timestamp,
  }) {
    return StreamScanCardItem(
      code: code,
      format: format ?? this.format,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      totalInCart: totalInCart ?? this.totalInCart,
      pendingQuantity: pendingQuantity ?? this.pendingQuantity,
      acceptedQuantity: acceptedQuantity ?? this.acceptedQuantity,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

/// Presentation item representing an error chip in the UI.
class StreamScanErrorChipItem {
  /// Unique identifier for this error chip.
  final String id;

  /// Barcode string value that triggered the error.
  final String code;

  /// Error message to display to the user.
  final String message;

  /// Number of scanned items not added to cart.
  final int unaddedQuantity;

  /// Timestamp when this error chip was created.
  final DateTime timestamp;

  /// Creates an error chip presentation item.
  const StreamScanErrorChipItem({
    required this.id,
    required this.code,
    required this.message,
    this.unaddedQuantity = 1,
    required this.timestamp,
  });

  /// Creates a copy with optional updated fields.
  StreamScanErrorChipItem copyWith({
    String? id,
    String? code,
    String? message,
    int? unaddedQuantity,
    DateTime? timestamp,
  }) {
    return StreamScanErrorChipItem(
      id: id ?? this.id,
      code: code ?? this.code,
      message: message ?? this.message,
      unaddedQuantity: unaddedQuantity ?? this.unaddedQuantity,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
