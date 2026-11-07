import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

import '../../core/constants/stream_scan_constants.dart';
import '../../smart_scanner.dart';

/// Provides haptic and vibrator feedback for stream scanning.
class StreamVibrationService {
  /// Optional override flag controlling vibration feedback.
  final bool? enableVibration;

  /// Creates a vibration service with optional enable override.
  const StreamVibrationService({this.enableVibration});

  /// Evaluates whether vibration is active for this session.
  bool get isVibrationEnabled =>
      enableVibration ?? SmartScanner.vibrateOnScan.value;

  /// Emits a single vibration pulse for successful scan.
  Future<void> vibrateSuccess() async {
    if (!isVibrationEnabled) {
      return;
    }

    // Trigger platform-specific single vibration pulse.
    if (defaultTargetPlatform == TargetPlatform.android) {
      Vibration.vibrate(
        duration: StreamScanConstants.vibrationSuccessDurationMs,
      ).catchError((_) {});
      return;
    }

    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  /// Emits a two-pulse vibration sequence for failed scan.
  Future<void> vibrateError() async {
    if (!isVibrationEnabled) {
      return;
    }

    // Trigger platform-specific two-pulse vibration sequence.
    if (defaultTargetPlatform == TargetPlatform.android) {
      Vibration.vibrate(
        pattern: const <int>[
          0,
          StreamScanConstants.vibrationErrorDurationMs,
          StreamScanConstants.vibrationErrorPauseDurationMs,
          StreamScanConstants.vibrationErrorDurationMs,
        ],
      ).catchError((_) {});
      return;
    }

    try {
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(
        const Duration(
          milliseconds: StreamScanConstants.vibrationErrorPauseDurationMs,
        ),
      );
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }
}
