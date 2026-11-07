import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

import '../entities/stream_frame_report.dart';
import '../entities/stream_scan_options.dart';

/// Tracks barcode presence across frames under leaveFrame policy.
class StreamPresenceTrackerUseCase {
  final StreamScanOptions _options;
  final Map<String, _PresenceState> _trackedCodes = <String, _PresenceState>{};
  int _consecutiveIgnoredMisses = 0;
  bool _isPaused = false;

  /// Creates a tracker with the provided scan options.
  StreamPresenceTrackerUseCase({
    StreamScanOptions options = const StreamScanOptions(),
  }) : _options = options;

  /// Active options configured for this tracker.
  StreamScanOptions get options => _options;

  /// Returns true if tracking is currently paused.
  bool get isPaused => _isPaused;

  /// Pauses tracking while preserving internal presence states.
  void pause() {
    _isPaused = true;
  }

  /// Resumes tracking with existing presence states intact.
  void resume() {
    _isPaused = false;
  }

  /// Resets all presence states and ignored miss counters.
  void reset() {
    _trackedCodes.clear();
    _consecutiveIgnoredMisses = 0;
  }

  /// Checks whether a barcode code is currently marked present.
  bool isCodePresent(String code) {
    final _PresenceState? state = _trackedCodes[code];
    return state != null && state.isPresent;
  }

  /// Total number of barcodes currently considered present.
  int get presentCodesCount {
    int count = 0;
    for (final _PresenceState state in _trackedCodes.values) {
      if (state.isPresent) {
        count++;
      }
    }
    return count;
  }

  /// Processes a frame report and returns barcodes to count.
  List<Barcode> processFrame(StreamFrameReport report) {
    if (_isPaused) {
      // Return empty when paused.
      return const <Barcode>[];
    }

    // Filter and deduplicate valid barcodes in frame.
    final List<Barcode> validBarcodes = <Barcode>[];
    final Set<String> seenInFrame = <String>{};

    for (final Barcode barcode in report.barcodes) {
      final String? rawValue = barcode.rawValue;
      if (rawValue != null &&
          rawValue.isNotEmpty &&
          !seenInFrame.contains(rawValue)) {
        seenInFrame.add(rawValue);
        validBarcodes.add(barcode);
      }
    }

    // Update presence for already present barcodes.
    for (final Barcode barcode in validBarcodes) {
      final String code = barcode.rawValue!;
      final _PresenceState? state = _trackedCodes[code];
      if (state != null && state.isPresent) {
        state.missedFrames = 0;
      }
    }

    // Identify new barcodes not yet marked present.
    final List<Barcode> newBarcodes = <Barcode>[];
    for (final Barcode barcode in validBarcodes) {
      final String code = barcode.rawValue!;
      final _PresenceState? state = _trackedCodes[code];
      if (state == null || !state.isPresent) {
        newBarcodes.add(barcode);
      }
    }

    // Mark all new barcodes present and count up to limit.
    final List<Barcode> countedBarcodes = <Barcode>[];
    final int maxToCount = _options.maxCodesPerFrame;

    for (int i = 0; i < newBarcodes.length; i++) {
      final Barcode barcode = newBarcodes[i];
      final String code = barcode.rawValue!;
      final _PresenceState state = _trackedCodes.putIfAbsent(
        code,
        () => _PresenceState(),
      );
      state.isPresent = true;
      state.missedFrames = 0;

      // Count only up to maxCodesPerFrame.
      if (countedBarcodes.length < maxToCount) {
        countedBarcodes.add(barcode);
      }
    }

    // Check empty frame quality flags.
    final RescanPolicy policy = _options.rescanPolicy;
    final bool isFrameEmpty = validBarcodes.isEmpty;
    final bool isBlurryOrGlare = report.isBlurry || report.hasGlare;
    final bool canConsiderIgnore =
        policy.ignoreBlurryOrGlareMisses && isBlurryOrGlare && isFrameEmpty;

    bool ignoreMissesThisFrame = false;
    if (canConsiderIgnore) {
      if (_consecutiveIgnoredMisses < policy.maxIgnoredMisses) {
        _consecutiveIgnoredMisses++;
        ignoreMissesThisFrame = true;
      }
    } else {
      _consecutiveIgnoredMisses = 0;
    }

    // Handle missing barcodes for absent transitions.
    if (!ignoreMissesThisFrame) {
      final List<String> codesToMarkAbsent = <String>[];

      for (final MapEntry<String, _PresenceState> entry
          in _trackedCodes.entries) {
        final String code = entry.key;
        final _PresenceState state = entry.value;

        if (state.isPresent && !seenInFrame.contains(code)) {
          state.missedFrames++;
          if (state.missedFrames >= policy.missedFrames) {
            codesToMarkAbsent.add(code);
          }
        }
      }

      for (final String code in codesToMarkAbsent) {
        final _PresenceState? state = _trackedCodes[code];
        if (state != null) {
          state.isPresent = false;
          state.missedFrames = 0;
        }
      }
    }

    return countedBarcodes;
  }
}

/// Internal presence tracking state for a barcode.
class _PresenceState {
  int missedFrames = 0;
  bool isPresent = false;
}
