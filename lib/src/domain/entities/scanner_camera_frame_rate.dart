/// Preferred camera capture rate for the scanner preview and image stream.
///
/// This is a best-effort request. Camera hardware and platform drivers may
/// select the nearest supported rate or fall back to [platformDefault].
enum ScannerCameraFrameRate {
  /// Keeps the scanner's thermal-friendly default: 24 FPS on iOS and 30 FPS
  /// on other platforms.
  platformDefault,

  /// Requests a fixed 30 FPS capture rate.
  fps30,

  /// Requests a fixed 60 FPS capture rate for capable devices.
  ///
  /// This increases camera/ISP work and memory bandwidth. It improves preview
  /// smoothness and gives the decoder more frames to choose from, but does not
  /// force ML Kit itself to decode 60 times per second.
  fps60,
}

extension ScannerCameraFrameRatePolicy on ScannerCameraFrameRate {
  int resolve({required bool isIOS}) => switch (this) {
    ScannerCameraFrameRate.platformDefault => isIOS ? 24 : 30,
    ScannerCameraFrameRate.fps30 => 30,
    ScannerCameraFrameRate.fps60 => 60,
  };
}
