## 0.1.0

- **Barcode Stream Scanning (Continuous POS Realtime Mode)**:
  - Added `SmartScanner.scanStream` for continuous, high-throughput barcode scanning with real-time host callbacks (`onScan`).
  - Added `RescanPolicy.leaveFrame` presence tracker preventing duplicate increments when items stay stationary in the scan window.
  - Added sequential per-barcode queueing and quantity batch aggregation (`StreamScanDispatcher`) with `maxConcurrent` throttling.
  - Added non-blocking background queue drain (`session.drained` returning `StreamScanSummary`) ensuring all in-flight requests finish cleanly after the screen closes.
  - Built with pure Flutter reactive primitives (`ChangeNotifier`, `ValueNotifier`, `RepaintBoundary`) without third-party framework dependencies.
  - Added `StreamScanResponse.accept` and `StreamScanResponse.reject` models with visual feedback cards and error chips.
  - Scanned products use the same stacked-card effect as multi-scan: the newest card in front at the bottom, older cards peeking out above it (narrower, 12px steps) and sliding up with a 500ms ease-out when a new card arrives. At most 3 layers are drawn, which is display only.
  - Scanned products are shown as stacked layers, most recent scan in front; re-scanning a product moves its layer to the front and updates its quantity, and a rejected re-scan of a product already in the cart keeps its layer at the previous quantity.
  - The product card and the "Mặt hàng | Số lượng" counter are hidden until the first code is accepted; the counter sits right above the card stack and is hidden while the "Quét liên tục" toggle is off.
  - Removed the "Hoàn thành" button, the exit confirmation and `isDiscarded`. Back leaves at once and keeps the cart; tapping the product card closes the screen and `StreamScanSession.exitReason` is `StreamScanExitReason.cardTap` so the host can open the cart. `scanStream` no longer takes `finishButtonBuilder` or `exitConfirmBuilder`.
  - Each accepted code shows a green "Thêm vào giỏ hàng thành công" toast (`StreamScanChipKind.success`); a later error toast replaces it.
  - Added `StreamScanOptions.validator` (`StreamScanValidator`): a host rule run before a scan is counted. Invalid codes flash red, vibrate and show the returned message, and never reach `onScan`, the card or the counter. Default `null` keeps the previous behavior.
  - Added opt-in `StreamScanValidators.gs1CheckDigit` (EAN-13, EAN-8, UPC-A, UPC-E, ITF-14) and `StreamScanValidators.all` to combine rules.
  - Added double-haptic error vibration and single-haptic success vibration via `StreamVibrationService`.
  - Added slow network warning indicator (`slowHintAfter`) without aborting or desynchronizing host requests.
  - Added demo POS cashier screen with realtime API simulation in `smart_scanner_app`.

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
