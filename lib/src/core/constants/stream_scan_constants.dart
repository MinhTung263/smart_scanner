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

  /// Number of most recent products published in `recentCards`.
  static const int defaultMaxVisibleCards = 3;

  /// Maximum toast chips visible at once (spec shows one at a time).
  static const int defaultMaxVisibleChips = 1;

  /// Auto-hide duration for error chips.
  static const Duration defaultChipAutoHide = Duration(seconds: 5);

  /// Auto-hide duration for info chips (continuous toggle toasts).
  static const Duration infoChipAutoHide = Duration(seconds: 2);

  /// Auto-hide duration for success chips after a code is added.
  static const Duration successChipAutoHide = Duration(seconds: 2);

  /// Duration of the green or red scan-frame flash after a result.
  static const Duration frameFlashDuration = Duration(milliseconds: 350);

  // ---- Texts ----

  /// Fallback error message when onScan fails.
  static const String defaultErrorMessage = 'Có lỗi xảy ra';

  /// Default toast when a code fails the GS1 check digit validator.
  static const String invalidCodeMessage = 'Mã không hợp lệ';

  /// Default text for slow network indicator.
  static const String defaultSlowNetworkMessage = 'Đang xử lý, mạng chậm...';

  /// Default label for a product still being looked up.
  static const String defaultProcessingLabel = 'Đang xử lý...';

  /// Success toast after a code was added to the cart.
  static const String successToastMessage = 'Thêm vào giỏ hàng thành công';

  /// Prefix of the scanned quantity badge (e.g. "+2").
  static const String quantityBadgePrefix = '+';

  /// Label of the continuous scan toggle.
  static const String continuousToggleLabel = 'Quét liên tục';

  /// Info toast when continuous scanning is turned on.
  static const String continuousOnMessage = 'Đã bật quét liên tục';

  /// Info toast when continuous scanning is turned off.
  static const String continuousOffMessage =
      'Đã tắt quét liên tục, quét xong 1 mã sẽ tạm dừng';

  /// Overlay text while paused after one code in single mode.
  static const String tapToContinueLabel = 'Chạm để quét tiếp';

  /// Counter label for distinct products.
  static const String counterItemsLabel = 'Mặt hàng:';

  /// Counter label for total quantity.
  static const String counterQuantityLabel = 'Số lượng:';

  // ---- Vibration ----

  /// Vibration duration in milliseconds for success.
  static const int vibrationSuccessDurationMs = 70;

  /// Vibration duration in milliseconds for error.
  static const int vibrationErrorDurationMs = 70;

  /// Pause duration in milliseconds between error pulses.
  static const int vibrationErrorPauseDurationMs = 80;

  // ---- Colors ----

  /// Success color hex value (frame flash, success toast).
  static const int successColorValue = 0xFF10B981;

  /// Error color hex value (error toast, frame error border).
  static const int errorColorValue = 0xFFE5534B;

  /// Warning color hex value.
  static const int warningColorValue = 0xFFF59E0B;

  /// Dark surface color hex value (slow network, info toast).
  static const int cardBackgroundColorValue = 0xFF1C1C2E;

  /// Toggle active track color hex value.
  static const int toggleActiveColorValue = 0xFF2563EB;

  /// Counter pill background color hex value.
  static const int counterBackgroundColorValue = 0xCC1F2937;

  /// Counter quantity value color hex value.
  static const int counterQuantityColorValue = 0xFFFBBF24;

  /// Product card surface color hex value.
  static const int productCardColorValue = 0xFFFFFFFF;

  /// Product name text color hex value.
  static const int productTitleColorValue = 0xFF111827;

  /// Barcode text color hex value.
  static const int productSubtitleColorValue = 0xFF9CA3AF;

  /// Quantity badge background color hex value.
  static const int badgeBackgroundColorValue = 0xFFE0E7FF;

  /// Quantity badge text color hex value.
  static const int badgeTextColorValue = 0xFF2563EB;

  // ---- Sizes ----

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

  /// Height of the scanned product card.
  static const double productCardHeight = 64.0;

  /// Product thumbnail size.
  static const double thumbnailSize = 48.0;

  /// Number of decorative layers stacked under the product card.
  static const int decorativeLayerCount = 3;

  /// Vertical step of each decorative layer below the card.
  static const double decorativeLayerOffsetY = 5.0;

  /// Horizontal inset added per decorative layer.
  static const double decorativeLayerInsetX = 10.0;

  /// Height reserved for the top bar under the safe area.
  static const double topBarHeight = 58.0;

  /// Gap between the scan frame and widgets placed below it.
  static const double belowFrameGap = 14.0;

  /// Height of the continuous scan toggle row under the frame.
  static const double continuousToggleHeight = 32.0;
}
