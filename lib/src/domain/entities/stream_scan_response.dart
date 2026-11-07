import 'package:flutter/foundation.dart' show mapEquals;

/// Short alias for [StreamScanResponse].
typedef ScanAck = StreamScanResponse;

/// Response returned by the host app for a scan request.
class StreamScanResponse {
  /// Whether the scan was accepted by the host app.
  final bool isAccepted;

  /// Optional display title for accepted item card.
  final String? title;

  /// Optional display subtitle or price for accepted item card.
  final String? subtitle;

  /// Optional total quantity of this item in the cart.
  final int? totalInCart;

  /// Optional product thumbnail URL shown on the scanned card.
  final String? imageUrl;

  /// Error message when the scan request was rejected.
  final String? errorMessage;

  const StreamScanResponse._({
    required this.isAccepted,
    this.title,
    this.subtitle,
    this.totalInCart,
    this.imageUrl,
    this.errorMessage,
  });

  /// Creates a successful response accepting the scanned item.
  const StreamScanResponse.accept({
    String? title,
    String? subtitle,
    int? totalInCart,
    String? imageUrl,
  }) : this._(
         isAccepted: true,
         title: title,
         subtitle: subtitle,
         totalInCart: totalInCart,
         imageUrl: imageUrl,
       );

  /// Creates an error response rejecting the scanned item.
  const StreamScanResponse.reject(String message)
    : this._(isAccepted: false, errorMessage: message);

  /// Helper flag returning true when scan is accepted.
  bool get isSuccess => isAccepted;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StreamScanResponse &&
          runtimeType == other.runtimeType &&
          isAccepted == other.isAccepted &&
          title == other.title &&
          subtitle == other.subtitle &&
          totalInCart == other.totalInCart &&
          imageUrl == other.imageUrl &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(
    isAccepted,
    title,
    subtitle,
    totalInCart,
    imageUrl,
    errorMessage,
  );

  @override
  String toString() {
    if (isAccepted) {
      return 'StreamScanResponse.accept(title: $title, subtitle: $subtitle, totalInCart: $totalInCart)';
    }
    return 'StreamScanResponse.reject(message: $errorMessage)';
  }
}

/// Final summary of quantities processed in a session.
class StreamScanSummary {
  /// Total quantity of items successfully accepted into cart.
  final int acceptedQuantity;

  /// Total quantity of items rejected and not added.
  final int notAddedQuantity;

  /// Accepted quantity per barcode, e.g. to roll back a discarded session.
  final Map<String, int> acceptedByCode;

  /// Creates a summary with accepted and not added counts.
  const StreamScanSummary({
    this.acceptedQuantity = 0,
    this.notAddedQuantity = 0,
    this.acceptedByCode = const <String, int>{},
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StreamScanSummary &&
          runtimeType == other.runtimeType &&
          acceptedQuantity == other.acceptedQuantity &&
          notAddedQuantity == other.notAddedQuantity &&
          mapEquals(acceptedByCode, other.acceptedByCode);

  @override
  int get hashCode => Object.hash(
    acceptedQuantity,
    notAddedQuantity,
    Object.hashAllUnordered(
      acceptedByCode.entries.map(
        (MapEntry<String, int> e) => Object.hash(e.key, e.value),
      ),
    ),
  );

  @override
  String toString() =>
      'StreamScanSummary(acceptedQuantity: $acceptedQuantity, notAddedQuantity: $notAddedQuantity, acceptedByCode: $acceptedByCode)';
}

/// Active session tracking background processing drain status.
class StreamScanSession {
  /// Future that completes when all background onScan calls finish.
  final Future<StreamScanSummary> drained;

  /// True when the user left with "Thoát" after the exit confirmation.
  /// Items were already added in realtime, so the host should remove
  /// `acceptedByCode` from the cart after awaiting [drained].
  final bool isDiscarded;

  /// Creates a session referencing the drained future.
  const StreamScanSession({required this.drained, this.isDiscarded = false});
}
