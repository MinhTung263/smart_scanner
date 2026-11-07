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

  /// Error message when the scan request was rejected.
  final String? errorMessage;

  const StreamScanResponse._({
    required this.isAccepted,
    this.title,
    this.subtitle,
    this.totalInCart,
    this.errorMessage,
  });

  /// Creates a successful response accepting the scanned item.
  const StreamScanResponse.accept({
    String? title,
    String? subtitle,
    int? totalInCart,
  }) : this._(
         isAccepted: true,
         title: title,
         subtitle: subtitle,
         totalInCart: totalInCart,
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
          errorMessage == other.errorMessage;

  @override
  int get hashCode =>
      Object.hash(isAccepted, title, subtitle, totalInCart, errorMessage);

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

  /// Creates a summary with accepted and not added counts.
  const StreamScanSummary({
    this.acceptedQuantity = 0,
    this.notAddedQuantity = 0,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StreamScanSummary &&
          runtimeType == other.runtimeType &&
          acceptedQuantity == other.acceptedQuantity &&
          notAddedQuantity == other.notAddedQuantity;

  @override
  int get hashCode => Object.hash(acceptedQuantity, notAddedQuantity);

  @override
  String toString() =>
      'StreamScanSummary(acceptedQuantity: $acceptedQuantity, notAddedQuantity: $notAddedQuantity)';
}

/// Active session tracking background processing drain status.
class StreamScanSession {
  /// Future that completes when all background onScan calls finish.
  final Future<StreamScanSummary> drained;

  /// Creates a session referencing the drained future.
  const StreamScanSession({required this.drained});
}
