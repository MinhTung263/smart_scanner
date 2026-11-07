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

  /// Optional product thumbnail URL from the latest accept response.
  final String? imageUrl;

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
    this.imageUrl,
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
    String? imageUrl,
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
      imageUrl: imageUrl ?? this.imageUrl,
      pendingQuantity: pendingQuantity ?? this.pendingQuantity,
      acceptedQuantity: acceptedQuantity ?? this.acceptedQuantity,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

/// Kind of toast chip shown above the scan frame.
enum StreamScanChipKind {
  /// Red toast for a rejected scan.
  error,

  /// Neutral toast, e.g. when the continuous-scan toggle changes.
  info,
}

/// Presentation item for a toast chip shown above the scan frame.
class StreamScanErrorChipItem {
  /// Unique identifier for this error chip.
  final String id;

  /// Barcode string value that triggered the error (empty for info chips).
  final String code;

  /// Error message to display to the user.
  final String message;

  /// Number of scanned items not added to cart.
  final int unaddedQuantity;

  /// Whether this chip reports an error or neutral information.
  final StreamScanChipKind kind;

  /// Timestamp when this error chip was created.
  final DateTime timestamp;

  /// Creates an error chip presentation item.
  const StreamScanErrorChipItem({
    required this.id,
    required this.code,
    required this.message,
    this.unaddedQuantity = 1,
    this.kind = StreamScanChipKind.error,
    required this.timestamp,
  });

  /// Whether this chip reports a rejected scan.
  bool get isError => kind == StreamScanChipKind.error;

  /// Creates a copy with optional updated fields.
  StreamScanErrorChipItem copyWith({
    String? id,
    String? code,
    String? message,
    int? unaddedQuantity,
    StreamScanChipKind? kind,
    DateTime? timestamp,
  }) {
    return StreamScanErrorChipItem(
      id: id ?? this.id,
      code: code ?? this.code,
      message: message ?? this.message,
      unaddedQuantity: unaddedQuantity ?? this.unaddedQuantity,
      kind: kind ?? this.kind,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

/// Session counter shown as "Mặt hàng: N | Số lượng: M".
class StreamScanCounter {
  /// Distinct products accepted in this session.
  final int itemCount;

  /// Total accepted quantity of all products in this session.
  final int totalQuantity;

  /// Creates a session counter value.
  const StreamScanCounter({this.itemCount = 0, this.totalQuantity = 0});

  @override
  bool operator ==(Object other) =>
      other is StreamScanCounter &&
      other.itemCount == itemCount &&
      other.totalQuantity == totalQuantity;

  @override
  int get hashCode => Object.hash(itemCount, totalQuantity);
}

/// Momentary color flash of the scan frame after a result.
enum StreamScanFrameFlash {
  /// Normal white frame.
  none,

  /// Green flash after an accepted scan.
  success,

  /// Red border after a rejected scan.
  error,
}
