import '../../core/constants/stream_scan_constants.dart';
import 'stream_scan_validator.dart';

/// Policy governing when a barcode is eligible to be rescanned.
class RescanPolicy {
  /// Consecutive missed frames required to mark absent.
  final int missedFrames;

  /// Whether empty blurry or glare frames should be ignored.
  final bool ignoreBlurryOrGlareMisses;

  /// Maximum consecutive blurry or glare empty frames ignored.
  final int maxIgnoredMisses;

  /// Rescan policy that requires barcode to leave the frame.
  const RescanPolicy.leaveFrame({
    this.missedFrames = StreamScanConstants.defaultMissedFrames,
    this.ignoreBlurryOrGlareMisses =
        StreamScanConstants.defaultIgnoreBlurryOrGlareMisses,
    this.maxIgnoredMisses = StreamScanConstants.defaultMaxIgnoredMisses,
  });
}

/// Options configuring stream scanning behaviors.
class StreamScanOptions {
  /// Policy controlling barcode re-detection eligibility.
  final RescanPolicy rescanPolicy;

  /// Maximum new codes dispatched per frame.
  final int maxCodesPerFrame;

  /// Maximum concurrent onScan invocations.
  final int maxConcurrent;

  /// Duration before slow network hint is shown.
  final Duration slowHintAfter;

  /// Maximum recent cards visible on screen.
  final int maxVisibleCards;

  /// Maximum error chips visible simultaneously.
  final int maxVisibleChips;

  /// Auto-hide duration for error chips.
  final Duration chipAutoHide;

  /// Optional host rule run before counting; invalid codes never reach onScan.
  /// Null (default) accepts every decoded code, as before.
  final StreamScanValidator? validator;

  /// Creates configuration options for stream scan session.
  const StreamScanOptions({
    this.validator,
    this.rescanPolicy = const RescanPolicy.leaveFrame(),
    this.maxCodesPerFrame = StreamScanConstants.defaultMaxCodesPerFrame,
    this.maxConcurrent = StreamScanConstants.defaultMaxConcurrent,
    this.slowHintAfter = StreamScanConstants.defaultSlowHintAfter,
    this.maxVisibleCards = StreamScanConstants.defaultMaxVisibleCards,
    this.maxVisibleChips = StreamScanConstants.defaultMaxVisibleChips,
    this.chipAutoHide = StreamScanConstants.defaultChipAutoHide,
  });
}
