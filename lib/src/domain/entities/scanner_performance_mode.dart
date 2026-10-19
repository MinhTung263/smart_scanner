/// Controls how frequently camera frames are sent to the barcode decoder.
enum ScannerPerformanceMode {
  /// Learns from the decoder cost at runtime. Fast devices scan more often,
  /// while slower POS devices automatically leave more time for UI rendering.
  adaptive,

  /// Lowest sustained CPU and heat usage. Recommended for fixed POS devices,
  /// older phones, or long-running inventory sessions.
  efficiency,

  /// Predictable middle ground matching the package's conservative defaults.
  balanced,

  /// Lowest scan latency for modern, high-performance devices.
  performance,
}

extension ScannerPerformanceVisualPolicy on ScannerPerformanceMode {
  /// Continuous glow is reserved for explicitly high-performance devices.
  bool get usesContinuousOverlayPulse =>
      this == ScannerPerformanceMode.performance;

  /// Blur is one of the most expensive effects in the scanner overlay.
  bool get usesRichOverlayEffects => this == ScannerPerformanceMode.performance;

  /// Efficiency mode keeps only the lock box and checkmark.
  bool get showsOverlayLabels => this != ScannerPerformanceMode.efficiency;
}

/// Runtime scheduling policy kept separate from the camera widget so its
/// adaptive behavior can be tested without a camera or platform channel.
class ScannerPerformancePolicy {
  ScannerPerformancePolicy(this.mode);

  final ScannerPerformanceMode mode;

  static const int _minimumAdaptiveSamples = 3;
  static const double _averageWeight = 0.25;

  double? _averageDecodeMs;
  int _samples = 0;

  double? get averageDecodeMs => _averageDecodeMs;

  void recordDecode(Duration elapsed) {
    final milliseconds = elapsed.inMicroseconds / 1000;
    if (milliseconds <= 0) return;

    final previous = _averageDecodeMs;
    _averageDecodeMs = previous == null
        ? milliseconds
        : previous * (1 - _averageWeight) + milliseconds * _averageWeight;
    _samples++;
  }

  Duration interval({required bool idle}) {
    final milliseconds = switch (mode) {
      ScannerPerformanceMode.efficiency => idle ? 800 : 350,
      ScannerPerformanceMode.balanced => idle ? 500 : 200,
      ScannerPerformanceMode.performance => idle ? 300 : 100,
      ScannerPerformanceMode.adaptive => _adaptiveInterval(idle: idle),
    };
    return Duration(milliseconds: milliseconds);
  }

  int _adaptiveInterval({required bool idle}) {
    final average = _averageDecodeMs;
    if (average == null || _samples < _minimumAdaptiveSamples) {
      return idle ? 500 : 200;
    }

    // Active scanning targets at most ~50% decoder duty. Idle scanning leaves
    // still more headroom for POS apps that remain open for an entire shift.
    final multiplier = idle ? 3.0 : 2.0;
    final minimum = idle ? 400 : 120;
    final maximum = idle ? 1000 : 400;
    return (average * multiplier).round().clamp(minimum, maximum);
  }
}
