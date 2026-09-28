import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'data/services/camera_service.dart';
import 'presentation/pages/smart_scanner_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'domain/entities/smart_scanner_result.dart';

export 'domain/entities/smart_scanner_result.dart';

/// A helper class to easily integrate Smart Scanner into any project.
class SmartScanner {
  /// Whether the phone vibrates when a code is scanned. An app-wide setting
  /// saved on the device: every scanner opened through this class follows it
  /// unless a call passes `enableVibration`. `true` by default; listen to it
  /// to rebuild UI when it changes (or use [SmartScannerVibrationSwitch]).
  ///
  /// The saved value is loaded in the background the first time this is
  /// read (or by [warmUp]), so it may briefly report the default right after
  /// launch; listeners are notified once it arrives.
  static ValueListenable<bool> get vibrateOnScan {
    _loadSettings();
    return _vibrateOnScan;
  }

  /// Turns scan vibration on or off for every scanner and saves the choice.
  static Future<void> setVibrateOnScan(bool value) async {
    _vibrateOnScanChanged = true;
    _vibrateOnScan.value = value;
    try {
      await SharedPreferencesAsync().setBool(_vibrateOnScanKey, value);
    } catch (_) {
      // Still applies for this session even if it couldn't be saved.
    }
  }

  static const _vibrateOnScanKey = 'smart_scanner.vibrate_on_scan';
  static final ValueNotifier<bool> _vibrateOnScan = ValueNotifier(true);
  static bool _vibrateOnScanChanged = false;
  static Future<void>? _loadingSettings;

  static Future<void> _loadSettings() => _loadingSettings ??= () async {
    try {
      final saved = await SharedPreferencesAsync().getBool(_vibrateOnScanKey);
      // A change made while loading is newer than what was on disk.
      if (saved != null && !_vibrateOnScanChanged) {
        _vibrateOnScan.value = saved;
      }
    } catch (_) {
      // No persistent storage available: keep the default.
    }
  }();

  /// Warms up the camera subsystem ahead of time.
  ///
  /// On Android, the first camera call in a process has to bootstrap CameraX
  /// (`ProcessCameraProvider.getInstance()`), which is a noticeably heavier
  /// one-time cost per app launch — this is what makes the scanner screen's
  /// black/loading state drag on if it's the first camera call in the app.
  ///
  /// Call this once, as early as possible (e.g. in `main()` right after
  /// `runApp()`, or in your splash/home screen's `initState`), so that cost
  /// is paid in the background while the user is still navigating, instead
  /// of blocking the scanner screen on open. Safe to call multiple times —
  /// later calls are instant no-ops once the camera list is cached. Also
  /// loads the saved [vibrateOnScan] setting.
  static Future<void> warmUp() async {
    await Future.wait([CameraService.preloadCameras(), _loadSettings()]);
  }

  /// Opens the smart scanner screen and returns the scanned result(s).
  ///
  /// If [isQRMode] is true, the scanner will only look for QR codes.
  /// Otherwise, it will look for traditional 1D barcodes.
  ///
  /// Vibration on a successful scan follows the app-wide [vibrateOnScan];
  /// pass [enableVibration] to force it on or off for this scan only.
  ///
  /// - A [SmartScannerResult] if barcodes are scanned.
  /// - `null` if the user cancels or goes back without scanning.
  static Future<SmartScannerResult?> scan(
    BuildContext context, {
    bool isQRMode = false,
    bool showMultiScanToggle = true,
    bool? enableVibration,
    Widget Function(BuildContext context, String barcode)? bottomWidgetBuilder,
    Widget Function(BuildContext context, String barcode)? multiScanItemBuilder,
    Widget Function(BuildContext context, int totalItems, int totalQuantity)?
    multiScanSummaryBuilder,
    Widget Function(
      BuildContext context,
      Map<String, int> scannedBarcodes,
      VoidCallback onFinish,
    )?
    multiScanFinishButtonBuilder,
  }) {
    // Warm up the camera list before the route transition starts so the scanner
    // screen doesn't have to wait on availableCameras() after it's already visible.
    CameraService.preloadCameras();

    return Navigator.of(context).push<SmartScannerResult?>(
      MaterialPageRoute(
        builder: (context) => SmartScannerScreen(
          isQRMode: isQRMode,
          showMultiScanToggle: showMultiScanToggle,
          enableVibration: enableVibration,
          bottomWidgetBuilder:
              bottomWidgetBuilder ??
              (context, barcode) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 20,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4F46E5).withValues(alpha: 0.3),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text(
                        'MÃ VỪA QUÉT',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        barcode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Sản phẩm tồn tại trong Database',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                );
              },
          multiScanItemBuilder:
              multiScanItemBuilder ??
              (context, barcode) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      barcode,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        letterSpacing: 1.0,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Sản phẩm mới quét',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                );
              },
          multiScanSummaryBuilder:
              multiScanSummaryBuilder ??
              (context, totalItems, totalQuantity) {
                return Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isQRMode ? Icons.qr_code : Icons.barcode_reader,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$totalItems mã',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(width: 1, height: 12, color: Colors.white54),
                        const SizedBox(width: 12),
                        const Icon(
                          Icons.inventory_2_outlined,
                          color: Colors.amberAccent,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$totalQuantity SP',
                          style: const TextStyle(
                            color: Colors.amberAccent,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
          multiScanFinishButtonBuilder:
              multiScanFinishButtonBuilder ??
              (context, scannedBarcodes, onFinish) {
                return Container(
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF10B981), Color(0xFF059669)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withValues(alpha: 0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onFinish,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(
                              Icons.check_circle_outline,
                              color: Colors.white,
                              size: 18,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Hoàn tất',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
        ),
      ),
    );
  }

  /// Convenience method to easily scan only QR codes with the beautiful UI.
  static Future<SmartScannerResult?> scanQR(
    BuildContext context, {
    bool showMultiScanToggle = true,
    bool? enableVibration,
  }) {
    return scan(
      context,
      isQRMode: true,
      showMultiScanToggle: showMultiScanToggle,
      enableVibration: enableVibration,
    );
  }

  /// Convenience method to easily scan only Barcodes with the beautiful UI.
  static Future<SmartScannerResult?> scanBarcode(
    BuildContext context, {
    bool showMultiScanToggle = true,
    bool? enableVibration,
  }) {
    return scan(
      context,
      isQRMode: false,
      showMultiScanToggle: showMultiScanToggle,
      enableVibration: enableVibration,
    );
  }

  /// Opens the smart scanner with the pure, minimal, un-opinionated original UI.
  /// Use this if you prefer the default green UI rather than the customized Indigo one.
  static Future<SmartScannerResult?> scanBasic(
    BuildContext context, {
    bool isQRMode = false,
    bool showMultiScanToggle = true,
    bool? enableVibration,
    Widget Function(BuildContext context, String barcode)? bottomWidgetBuilder,
    Widget Function(BuildContext context, String barcode)? multiScanItemBuilder,
    Widget Function(BuildContext context, int totalItems, int totalQuantity)?
    multiScanSummaryBuilder,
    Widget Function(
      BuildContext context,
      Map<String, int> scannedBarcodes,
      VoidCallback onFinish,
    )?
    multiScanFinishButtonBuilder,
  }) {
    return Navigator.of(context).push<SmartScannerResult?>(
      MaterialPageRoute(
        builder: (context) => SmartScannerScreen(
          isQRMode: isQRMode,
          showMultiScanToggle: showMultiScanToggle,
          enableVibration: enableVibration,
          bottomWidgetBuilder: bottomWidgetBuilder,
          multiScanItemBuilder: multiScanItemBuilder,
          multiScanSummaryBuilder: multiScanSummaryBuilder,
          multiScanFinishButtonBuilder: multiScanFinishButtonBuilder,
        ),
      ),
    );
  }
}
