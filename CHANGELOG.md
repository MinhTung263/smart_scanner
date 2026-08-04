## 0.0.3

- **Completion Celebration & Animation Effects**:
  - Added animated completion overlay with elastic scale bounce, checkmark icon, custom title ("Quét thành công!", "Quét hoàn tất!"), and heavy haptic feedback.
  - Enabled completion animation overlay for both Single Scan and Multi Scan modes.
  - Added snappy entrance & exit transitions (`200ms` cubic ease) for the finish button.

- **Scanner Controls & Layout Improvements**:
  - Repositioned "Quét liên tục" (Multi-scan) toggle button to the top-right area above the scan window.
  - Added pixel-perfect right alignment flush with the scan frame border.
  - Fixed control button positioning so it stays stationary during camera zoom and never overlaps the scan frame at maximum zoom.
  - Refined the "Hoàn tất" button layout with side padding and prominent CTA style.
  - Preserved scanned barcode list when toggling continuous scanning mode.

- **Gesture & Camera Performance Optimizations**:
  - Restricted Tap-to-Focus gesture to only trigger within the `scanWindow` boundary.
  - Fixed 2-finger pinch-zoom stuttering with an async lock (`_isSettingZoom`) and micro-jitter filtering for smooth 60 FPS camera zoom.

## 0.0.2

- **Core Scanner Features**:
  - High-performance Barcode and QR code scanning powered by Google ML Kit.
  - Single Scan and Multi-Scan (continuous scanning) modes with real-time barcode tracking.
  - Gallery photo picker with high-resolution image decoding (ZXing & ML Kit fallback).
  - Customizable UI builders (`bottomWidgetBuilder`, `multiScanFinishButtonBuilder`, `multiScanItemBuilder`, `multiScanSummaryBuilder`).
  - Flashlight (torch) control and smooth zoom controls (`1x`, `2x`, `3x`).
- **Performance & Thermal Optimizations**:
  - Reduced default resolution to 720p (`ResolutionPreset.high`) to cut CPU/GPU thermal load.
  - Added Adaptive Frame Throttling and Auto-Sleep inactivity timer (60s).

## 0.0.1

- Initial release of `smart_scanner` package.
