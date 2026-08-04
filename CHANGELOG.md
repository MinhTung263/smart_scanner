## 0.0.2

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
  - Reduced thermal load and improved camera lifecycle management during backgrounding/pausing.

## 0.0.1

- Initial release of `smart_scanner` package.
