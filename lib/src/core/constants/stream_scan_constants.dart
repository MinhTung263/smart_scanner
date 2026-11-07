/// Default constants for stream scan operations.
abstract final class StreamScanConstants {
  /// Consecutive missed frames before marking barcode absent.
  static const int defaultMissedFrames = 2;

  /// Default flag whether to ignore blurry or glare misses.
  static const bool defaultIgnoreBlurryOrGlareMisses = false;

  /// Maximum consecutive blurry or glare misses ignored.
  static const int defaultMaxIgnoredMisses = 2;

  /// Default maximum new barcodes counted per frame.
  static const int defaultMaxCodesPerFrame = 1;

  /// Default maximum concurrent onScan calls.
  static const int defaultMaxConcurrent = 2;

  /// Duration before displaying slow network hint.
  static const Duration defaultSlowHintAfter = Duration(seconds: 3);

  /// Maximum visible success or in-flight cards.
  static const int defaultMaxVisibleCards = 3;

  /// Maximum visible error chips.
  static const int defaultMaxVisibleChips = 3;

  /// Auto-hide duration for error chips.
  static const Duration defaultChipAutoHide = Duration(seconds: 5);

  /// Fallback error message when onScan fails.
  static const String defaultErrorMessage = 'Có lỗi xảy ra';

  /// Default text for slow network indicator.
  static const String defaultSlowNetworkMessage = 'Đang xử lý, mạng chậm...';

  /// Default text for finish button.
  static const String defaultFinishButtonText = 'Hoàn tất';

  /// Default label for processing card item.
  static const String defaultProcessingLabel = 'Đang xử lý...';

  /// Prefix of the quantity badge on a product layer (e.g. "x3").
  static const String layerQuantityPrefix = 'x';

  /// Suffix for scans of a layer still awaiting the host (e.g. "+1 đang xử lý").
  static const String layerPendingSuffix = 'đang xử lý';

  /// Fixed height of each product layer card.
  static const double layerCardHeight = 72.0;

  /// Vertical peek of each layer behind the front card.
  static const double layerOffsetY = 10.0;

  /// Horizontal inset added per layer depth behind the front card.
  static const double layerInsetX = 14.0;

  /// Duration of the layer re-order animation.
  static const Duration layerAnimationDuration = Duration(milliseconds: 500);

  /// Blur radius of the light shadow under each layer.
  static const double layerShadowBlur = 8.0;

  /// Quantity badge color hex value.
  static const int layerQuantityColorValue = 0xFF60A5FA;

  /// Default suffix message for unadded items.
  static const String defaultUnaddedSuffix = 'chưa thêm vào giỏ, hãy quét lại';

  /// Vibration duration in milliseconds for success.
  static const int vibrationSuccessDurationMs = 70;

  /// Vibration duration in milliseconds for error.
  static const int vibrationErrorDurationMs = 70;

  /// Pause duration in milliseconds between error pulses.
  static const int vibrationErrorPauseDurationMs = 80;

  /// Success color hex value.
  static const int successColorValue = 0xFF10B981;

  /// Error color hex value.
  static const int errorColorValue = 0xFFEF4444;

  /// Warning color hex value.
  static const int warningColorValue = 0xFFF59E0B;

  /// Background card color hex value.
  static const int cardBackgroundColorValue = 0xFF1C1C2E;

  /// Default component horizontal and vertical padding.
  static const double defaultComponentPadding = 16.0;

  /// Default border radius for card items.
  static const double defaultCardBorderRadius = 16.0;

  /// Default border radius for chip items.
  static const double defaultChipBorderRadius = 12.0;

  /// Default spacing between adjacent cards or chips.
  static const double defaultItemSpacing = 8.0;

  /// Default scan window size ratio.
  static const double defaultScanWindowRatio = 0.85;
}
