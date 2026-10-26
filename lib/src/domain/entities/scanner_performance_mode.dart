/// Controls how aggressively the scanner uses the camera.
enum ScannerPerformanceMode {
  /// Selects a preset from the device profile.
  auto,

  /// Uses a lower camera resolution to keep preview and decoding smooth.
  balanced,

  /// Uses the highest practical resolution for small/distant barcodes.
  quality,
}
