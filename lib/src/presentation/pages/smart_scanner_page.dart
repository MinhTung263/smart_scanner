import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_zxing/flutter_zxing.dart'
    hide CameraController, ResolutionPreset, CameraLensDirection;
import '../../domain/entities/smart_scanner_result.dart';
import '../../smart_scanner_settings.dart';

import '../../controllers/scanner_controller.dart';
import '../widgets/custom_barcode_scanner.dart';
import '../widgets/scanner_overlay.dart';
import '../widgets/scanner_controls.dart';
import '../widgets/scanner_bottom_sheet.dart';

// ZXing's file helper decodes pixels and calls FFI synchronously after its
// file read. Run the complete operation off the UI isolate, including JPEG/HEIC
// decompression, resizing and conversion to RGB.
Future<List<String>> _decodeGalleryBarcodes((String, int) request) async {
  final codes = await zx.readBarcodesImagePathString(
    request.$1,
    DecodeParams(
      format: request.$2,
      tryHarder: true,
      tryRotate: true,
      imageFormat: ImageFormat.rgb,
      maxSize: 4000,
    ),
  );
  return codes.codes
      .where((code) => code.isValid)
      .map((code) => code.text)
      .whereType<String>()
      .where((text) => text.isNotEmpty)
      .toList();
}

enum _GalleryStatus { idle, selecting, analyzing }

class SmartScannerScreen extends StatefulWidget {
  final bool isQRMode;
  final bool showMultiScanToggle;

  /// Whether the phone vibrates when a code is scanned (single scan, each new
  /// code in multi-scan, and finishing a multi-scan). `null` follows the
  /// app-wide `SmartScanner.vibrateOnScan`. Light taps on the
  /// scanner's own buttons are unaffected; they follow the system's touch
  /// feedback setting.
  final bool? enableVibration;
  final Widget Function(BuildContext context, String barcode)?
  bottomWidgetBuilder;
  final Widget Function(BuildContext context, String barcode)?
  multiScanItemBuilder;
  final Widget Function(
    BuildContext context,
    int totalItems,
    int totalQuantity,
  )?
  multiScanSummaryBuilder;
  final Widget Function(
    BuildContext context,
    Map<String, int> scannedBarcodes,
    VoidCallback onFinish,
  )?
  multiScanFinishButtonBuilder;

  const SmartScannerScreen({
    super.key,
    this.isQRMode = false,
    this.showMultiScanToggle = true,
    this.enableVibration,
    this.bottomWidgetBuilder,
    this.multiScanItemBuilder,
    this.multiScanSummaryBuilder,
    this.multiScanFinishButtonBuilder,
  });

  @override
  State<SmartScannerScreen> createState() => _SmartScannerScreenState();
}

class _SmartScannerScreenState extends State<SmartScannerScreen>
    with TickerProviderStateMixin {
  // Shared by the corner guide-frame entrance animation and the detection
  // warmup gate below, so a barcode already in frame on open can't be
  // accepted before the guide frame has visibly arrived.
  static const _introDuration = Duration(milliseconds: 650);

  late AnimationController _cornerController;
  late AnimationController _loadingController;
  late ScannerController _controller;
  final GlobalKey<CustomBarcodeScannerState> _scannerKey = GlobalKey();

  /// Current status of gallery picking & image decoding.
  _GalleryStatus _galleryStatus = _GalleryStatus.idle;
  bool _isTorchOn = false;

  bool get _isPickingImage => _galleryStatus != _GalleryStatus.idle;

  Future<void> _toggleFlash() async {
    final isOn = await _scannerKey.currentState?.toggleFlash();
    if (isOn != null && mounted) {
      setState(() {
        _isTorchOn = isOn;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    // The camera preview, guide frame and ML Kit rotation handling all assume
    // portrait, so lock the screen for as long as the scanner is open.
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SmartScannerSettings.load();
    _controller = ScannerController();

    _cornerController = AnimationController(
      vsync: this,
      duration: _introDuration,
    )..forward();

    _loadingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
  }

  @override
  void dispose() {
    // An empty list hands orientation back to the host app's own settings
    // (Info.plist / AndroidManifest) once the scanner closes.
    SystemChrome.setPreferredOrientations([]);
    _cornerController.dispose();
    _loadingController.dispose();
    _controller.dispose();
    super.dispose();
  }

  bool _isCompleting = false;
  String? _completionSubtitle;

  void _finishSingleScan(String barcode) {
    if (_isCompleting) return;
    _scannerKey.currentState?.pauseCamera();
    _scanHaptic();
    setState(() {
      _isCompleting = true;
      _completionSubtitle = 'Đã quét mã: $barcode';
    });

    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        _scannerKey.currentState?.pauseCamera();
        Navigator.of(context).pop(SmartScannerResult.single(barcode));
      }
    });
  }

  void _finishScanning() {
    if (_isCompleting) return;
    _scannerKey.currentState?.pauseCamera();
    _scanHaptic();
    setState(() {
      _isCompleting = true;
      _completionSubtitle = null;
    });

    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop(
          SmartScannerResult.multi(
            _controller.scannedBarcodes.map((k, v) => MapEntry(k, v.count)),
          ),
        );
      }
    });
  }

  List<BarcodeFormat> get _scannerFormats => widget.isQRMode
      ? const [BarcodeFormat.qrCode]
      : const [
          BarcodeFormat.code128,
          BarcodeFormat.code39,
          BarcodeFormat.code93,
          BarcodeFormat.ean13,
          BarcodeFormat.ean8,
          BarcodeFormat.upca,
          BarcodeFormat.upce,
          BarcodeFormat.itf,
          BarcodeFormat.codabar,
        ];

  /// Same allowed formats as [_scannerFormats], expressed as ZXing's format
  /// bitmask — used for the gallery-picker fallback below (ZXing's own
  /// decoder catches some images ML Kit's decoder misses entirely).
  int get _zxingAllowedFormats => widget.isQRMode
      ? Format.qrCode
      : Format.code128 |
            Format.code39 |
            Format.code93 |
            Format.ean13 |
            Format.ean8 |
            Format.upca |
            Format.upce |
            Format.itf |
            Format.codabar;

  Future<void> _pickImageFromGallery() async {
    if (_isPickingImage || _isCompleting) return;

    // Show the loading overlay in 'selecting' state immediately — before the gallery opens
    setState(() => _galleryStatus = _GalleryStatus.selecting);
    _loadingController.repeat();

    try {
      await _scannerKey.currentState?.pauseCamera();
      if (!mounted) return;
      final picker = ImagePicker();
      // Forces JPEG output instead of the gallery's original format — modern
      // iPhones store photos as HEIC by default, which has been an unreliable
      // input for some ML Kit / vision libraries when read directly by file
      // path rather than going through the camera's own image pipeline.
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );
      if (image == null) {
        // User cancelled — hide loading.
        if (mounted) setState(() => _galleryStatus = _GalleryStatus.idle);
        return;
      }

      // Image selected — proceed to barcode detection with 'analyzing' status.
      if (!mounted) return;
      setState(() => _galleryStatus = _GalleryStatus.analyzing);

      // ZXing first: testing showed it catching barcodes ML Kit's decoder
      // missed entirely (0 raw results) on the same photo. ML Kit only runs as
      // a fallback if ZXing comes up empty.
      List<String> values = await compute(_decodeGalleryBarcodes, (
        image.path,
        _zxingAllowedFormats,
      ), debugLabel: 'gallery-barcode-decode');

      if (values.isEmpty) {
        final inputImage = InputImage.fromFilePath(image.path);
        // Use BarcodeFormat.all to enable omnidirectional scanning, then filter in Dart
        final barcodeScanner = BarcodeScanner(
          formats: const [BarcodeFormat.all],
        );

        try {
          final rawBarcodes = await barcodeScanner.processImage(inputImage);
          values = rawBarcodes
              .where((b) => _scannerFormats.contains(b.format))
              .map((b) => b.displayValue ?? b.rawValue)
              .where((v) => v != null)
              .cast<String>()
              .toList();
        } finally {
          await barcodeScanner.close();
        }
      }

      if (!mounted) return;
      setState(() => _galleryStatus = _GalleryStatus.idle);

      if (values.isNotEmpty) {
        if (!_controller.isMultiScan) {
          _finishSingleScan(values.first);
        } else {
          _controller.processMultiScanValues(values);
          _showSnackBar(
            message: 'Đã tìm thấy ${values.length} mã trong ảnh',
            icon: Icons.check_circle_rounded,
            color: const Color(0xFF10B981),
          );
        }
      } else {
        _showSnackBar(
          message: 'Không tìm thấy mã nào trong ảnh',
          icon: Icons.image_search_rounded,
          color: const Color(0xFFF59E0B),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _galleryStatus = _GalleryStatus.idle);
      _showSnackBar(
        message: 'Có lỗi xảy ra khi xử lý ảnh',
        icon: Icons.error_rounded,
        color: const Color(0xFFEF4444),
      );
    } finally {
      if (mounted) {
        _loadingController.stop();
        setState(() => _galleryStatus = _GalleryStatus.idle);
        if (!_isCompleting && ModalRoute.of(context)?.isCurrent == true) {
          await _scannerKey.currentState?.resumeCamera();
        }
      }
    }
  }

  void _showSnackBar({
    required String message,
    required IconData icon,
    required Color color,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          elevation: 0,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          content: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1C1C2E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: color.withValues(alpha: 0.35),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.2),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  /// Scan-result feedback; a no-op when vibration is off for this scanner.
  bool get _vibrationEnabled =>
      widget.enableVibration ?? SmartScannerSettings.vibrateOnScan.value;

  void _scanHaptic() {
    if (!_vibrationEnabled) return;
    if (_vibrateAndroid()) return;
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  static const int _androidScanVibrationMs = 70;

  /// On Android, HapticFeedback is *touch* feedback (usage TOUCH), which the
  /// system silently drops whenever "touch vibration" is off in Settings — so
  /// scan confirmations never vibrated on such phones. A scan result isn't a
  /// touch echo, and the host opted in via enableVibration, so drive the
  /// vibrator directly there. Returns whether it handled the vibration.
  bool _vibrateAndroid() {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    Vibration.vibrate(duration: _androidScanVibrationMs).catchError((_) {});
    return true;
  }

  void _triggerVibration() {
    if (!_vibrationEnabled) return;
    if (_vibrateAndroid()) return;
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}
    try {
      HapticFeedback.vibrate();
    } catch (_) {}
  }

  /// Loading overlay shown while picking/processing a gallery image.
  Widget _buildLoadingOverlay() {
    final isSelecting = _galleryStatus == _GalleryStatus.selecting;
    final title = isSelecting
        ? 'Đang chọn ảnh từ thư viện'
        : 'Đang phân tích ảnh';

    return AnimatedOpacity(
      opacity: _isPickingImage ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: IgnorePointer(
        ignoring: !_isPickingImage,
        child: Container(
          color: Colors.black.withValues(alpha: 0.72),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // --- Animated scan card ---
                AnimatedBuilder(
                  animation: _loadingController,
                  builder: (context, child) {
                    return CustomPaint(
                      painter: _ScanLinePainter(
                        progress: _loadingController.value,
                        color: const Color(0xFF4F46E5),
                      ),
                      child: child,
                    );
                  },
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF4F46E5).withValues(alpha: 0.12),
                          const Color(0xFF7C3AED).withValues(alpha: 0.06),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: const Color(0xFF4F46E5).withValues(alpha: 0.4),
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        isSelecting
                            ? Icons.photo_library_rounded
                            : (widget.isQRMode
                                  ? Icons.qr_code_scanner
                                  : Icons.barcode_reader),
                        color: const Color(0xFF818CF8),
                        size: 48,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                // --- Text ---
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 8),
                // --- Animated dots ---
                AnimatedBuilder(
                  animation: _loadingController,
                  builder: (context, _) {
                    final dot = (_loadingController.value * 4).floor() % 4;
                    final String label;
                    if (isSelecting) {
                      label = 'Vui lòng chọn ảnh chứa mã${'.' * dot}';
                    } else {
                      label = widget.isQRMode
                          ? 'Nhận diện QR Code${'.' * dot}'
                          : 'Nhận diện mã vạch${'.' * dot}';
                    }
                    return Text(
                      label,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.3,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
        PopScope(
        canPop: true,
        onPopInvokedWithResult: (didPop, result) {
          // Stop the camera stream immediately when starting the pop animation
          _scannerKey.currentState?.pauseCamera();
        },
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final scanWindowWidth =
                size.width * _controller.scanWindowSizeRatio;

            final double heightMultiplier = widget.isQRMode
                ? 1.0
                : (0.15 +
                      0.35 * ((_controller.scanWindowSizeRatio - 0.2) / 0.7));
            final scanWindowHeight = scanWindowWidth * heightMultiplier;

            Rect currentScanWindow = Rect.fromCenter(
              center: size.center(const Offset(0, -60)),
              width: scanWindowWidth,
              height: scanWindowHeight,
            );

            return CustomBarcodeScanner(
              key: _scannerKey,
              showBoundingBox: true,
              formats: _scannerFormats,
              scanWindow: currentScanWindow,
              detectionWarmupDelay: _introDuration,
              loadingIcon: widget.isQRMode
                  ? Icons.qr_code_scanner
                  : Icons.barcode_reader,
              onWindowScaleStart: () {
                _controller.setBaseScanWindowSizeRatio(
                  _controller.scanWindowSizeRatio,
                );
              },
              onWindowScaleUpdate: (scale) {
                _controller.updateScanWindowSizeRatio(scale);
              },
              onZoomChanged: (zoomLevel) {
                _controller.setZoom(zoomLevel);
              },
              onDetect: (barcodes) async {
                if (_isCompleting || _isPickingImage) return;
                if (barcodes.isNotEmpty && !_controller.isProcessing) {
                  if (!_controller.isMultiScan) {
                    final firstBarcode = barcodes.first.displayValue ?? barcodes.first.rawValue;
                    if (firstBarcode != null) {
                      _controller.setProcessing(true);
                      _controller.setLatestBarcode(firstBarcode);
                      _finishSingleScan(firstBarcode);
                    }
                  } else {
                    final values = barcodes
                        .map((b) => b.displayValue ?? b.rawValue)
                        .where((v) => v != null)
                        .cast<String>()
                        .toList();
                    bool hasChanges = _controller.processMultiScanValues(values);

                    if (hasChanges) {
                      _controller.setProcessing(true);
                      _triggerVibration();

                      await Future.delayed(const Duration(milliseconds: 500));
                      if (context.mounted) {
                        _controller.setProcessing(false);
                      }
                    }
                  }
                }
              },
              overlayBuilder: (context, barcodes, imageSize) {
                final finishButtonWidget =
                    (_controller.isMultiScan &&
                        _controller.scannedBarcodes.isNotEmpty)
                    ? (widget.multiScanFinishButtonBuilder != null
                          ? widget.multiScanFinishButtonBuilder!(
                              context,
                              _controller.scannedBarcodes.map(
                                (k, v) => MapEntry(k, v.count),
                              ),
                              _finishScanning,
                            )
                          : Container(
                              height: 64,
                              margin: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF10B981),
                                    Color(0xFF047857),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(32),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.35),
                                  width: 1.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF10B981,
                                    ).withValues(alpha: 0.45),
                                    blurRadius: 24,
                                    spreadRadius: 2,
                                    offset: const Offset(0, 8),
                                  ),
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.35),
                                    blurRadius: 14,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: _finishScanning,
                                  borderRadius: BorderRadius.circular(32),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.2,
                                            ),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.check_rounded,
                                            color: Colors.white,
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(width: 14),
                                        const Expanded(
                                          child: Text(
                                            'Hoàn tất quét',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.4,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(
                                              alpha: 0.22,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            border: Border.all(
                                              color: Colors.white.withValues(
                                                alpha: 0.3,
                                              ),
                                              width: 1,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                '${_controller.scannedBarcodes.values.fold(0, (a, b) => a + b.count)} SP',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 0.2,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              const Icon(
                                                Icons.arrow_forward_rounded,
                                                color: Colors.white,
                                                size: 18,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ))
                    : null;

                // Calculate highest scan window top (when scan window ratio is at max 0.9)
                // so that ScannerControlsRow never overlaps the scan frame even at maximum zoom/expansion!
                const double maxRatio = 0.9;
                final maxScanWindowWidth = size.width * maxRatio;
                final double maxRatioHeightMultiplier = widget.isQRMode
                    ? 1.0
                    : (0.15 + 0.35 * ((maxRatio - 0.2) / 0.7));
                final maxScanWindowHeight =
                    maxScanWindowWidth * maxRatioHeightMultiplier;
                final highestScanWindowTop =
                    (size.height / 2 - 60) - (maxScanWindowHeight / 2);

                final double defaultScanWindowWidth = size.width * 0.8;

                final double fixedControlsTop =
                    math.max(68.0, highestScanWindowTop - 52.0);
                final double fixedRightMargin =
                    (size.width - defaultScanWindowWidth) / 2;

                return Stack(
                  children: [
                    AnimatedBuilder(
                      animation: _cornerController,
                      builder: (context, child) {
                        return IgnorePointer(
                          child: ScannerOverlay(
                            scanWindow: currentScanWindow,
                            borderColor: imageSize == Size.zero
                                ? const Color(0xFF10B981).withValues(
                                    alpha:
                                        0.3 +
                                        0.7 *
                                            ((math.sin(
                                                      _cornerController.value *
                                                          math.pi *
                                                          4,
                                                    ) +
                                                    1) /
                                                2),
                                  )
                                : Colors.white,
                            borderRadius: widget.isQRMode ? 20 : 8,
                            cornerLength: 35,
                            strokeWidth: 3,
                            cornerOffset: Tween<double>(begin: 40, end: 0)
                                .animate(CurvedAnimation(
                                  parent: _cornerController,
                                  curve: Curves.easeOutCubic,
                                ))
                                .value,
                            overlayColor: Colors.black.withValues(alpha: 0.65),
                          ),
                        );
                      },
                    ),

                    ScannerTopBar(
                      onPickImage: _pickImageFromGallery,
                      onToggleFlash: _toggleFlash,
                      onBack: () => _scannerKey.currentState?.pauseCamera(),
                      isTorchOn: _isTorchOn,
                      currentZoom: _controller.currentZoom,
                      onZoomChanged: (val) {
                        _controller.setZoom(val);
                        _scannerKey.currentState?.setZoom(val);
                      },
                      onZoomChangeEnd: (val) {
                        _scannerKey.currentState?.refocus();
                      },
                    ),

                    Positioned(
                      top: fixedControlsTop,
                      left: 0,
                      right: 0,
                      child: ScannerControlsRow(
                        currentZoom: _controller.currentZoom,
                        rightPadding: fixedRightMargin,
                        onZoomChanged: (val) {
                          _controller.setZoom(val);
                          _scannerKey.currentState?.setZoom(val);
                        },
                        onZoomChangeEnd: (val) {
                          _scannerKey.currentState?.refocus();
                        },
                        showMultiScanToggle: widget.showMultiScanToggle,
                        isMultiScan: _controller.isMultiScan,
                        onMultiScanChanged: (value) {
                          _controller.setMultiScan(value);
                          if (value) {
                            HapticFeedback.lightImpact();
                          }
                        },
                      ),
                    ),

                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ScannerBottomSheet(
                                isMultiScan: _controller.isMultiScan,
                                isQRMode: widget.isQRMode,
                                scannedBarcodes: _controller.scannedBarcodes
                                    .map((k, v) => MapEntry(k, v.count)),
                                latestBarcode: _controller.latestBarcode,
                                hasBarcodesInFrame: barcodes.isNotEmpty,
                                bottomWidgetBuilder: widget.bottomWidgetBuilder,
                                multiScanItemBuilder:
                                    widget.multiScanItemBuilder,
                                multiScanSummaryBuilder:
                                    widget.multiScanSummaryBuilder,
                              ),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                reverseDuration: const Duration(milliseconds: 150),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder: (child, animation) {
                                  final slideAnimation = Tween<Offset>(
                                    begin: const Offset(0, 0.3),
                                    end: Offset.zero,
                                  ).animate(animation);

                                  return SlideTransition(
                                    position: slideAnimation,
                                    child: ScaleTransition(
                                      scale: animation,
                                      child: FadeTransition(
                                        opacity: animation,
                                        child: child,
                                      ),
                                    ),
                                  );
                                },
                                child: finishButtonWidget != null
                                    ? Padding(
                                        key: const ValueKey('finish_button_visible'),
                                        padding: const EdgeInsets.only(top: 14),
                                        child: finishButtonWidget,
                                      )
                                    : const SizedBox.shrink(
                                        key: ValueKey('finish_button_hidden'),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    if (_isCompleting)
                      Positioned.fill(
                        child: _CompletionOverlay(
                          title: _controller.isMultiScan
                              ? 'Quét hoàn tất!'
                              : 'Quét thành công!',
                          itemCount: _controller.isMultiScan
                              ? _controller.scannedBarcodes.values
                                  .fold<int>(0, (a, b) => a + b.count)
                              : null,
                          subtitle: _completionSubtitle,
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
      // Loading overlay on top of everything
      _buildLoadingOverlay(),
      ],
    ),
  );
  }
}

/// Paints an animated scan line over a rounded-rect card to indicate
/// active barcode analysis. The line sweeps from top to bottom with a
/// soft glow trail, matching the indigo brand colour.
class _ScanLinePainter extends CustomPainter {
  const _ScanLinePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = const Radius.circular(20);
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, radius);

    // Clip so the line doesn't bleed outside the card.
    canvas.save();
    canvas.clipRRect(rrect);

    // Compute Y position with ease-in-out bounce using a sine curve.
    final t = (math.sin(progress * math.pi * 2 - math.pi / 2) + 1) / 2;
    final y = t * size.height;

    // Glow gradient trailing the line.
    final glowHeight = size.height * 0.45;
    final glowTop = (y - glowHeight).clamp(0.0, size.height);
    final glowRect = Rect.fromLTWH(0, glowTop, size.width, glowHeight);
    final glowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.18),
        ],
      ).createShader(glowRect);
    canvas.drawRect(glowRect, glowPaint);

    // The bright scan line itself.
    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.85)
      ..strokeWidth = 2.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);

    // Sharp top edge of the line.
    final sharpPaint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), sharpPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScanLinePainter old) => old.progress != progress;
}

class _CompletionOverlay extends StatefulWidget {
  final String? title;
  final int? itemCount;
  final String? subtitle;
  const _CompletionOverlay({this.title, this.itemCount, this.subtitle});

  @override
  State<_CompletionOverlay> createState() => _CompletionOverlayState();
}

class _CompletionOverlayState extends State<_CompletionOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();

    _scaleAnim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.elasticOut,
      ),
    );

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
      ),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return Container(
          color: Colors.black.withValues(alpha: 0.75 * _fadeAnim.value),
          child: Center(
            child: ScaleTransition(
              scale: _scaleAnim,
              child: Opacity(
                opacity: _fadeAnim.value.clamp(0.0, 1.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 36,
                    vertical: 28,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F2937).withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: const Color(0xFF10B981).withValues(alpha: 0.6),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withValues(alpha: 0.5),
                        blurRadius: 36,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF10B981),
                              Color(0xFF059669),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF10B981).withValues(alpha: 0.6),
                              blurRadius: 20,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        widget.title ?? 'Quét thành công!',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.subtitle ??
                            (widget.itemCount != null
                                ? 'Đã ghi nhận ${widget.itemCount} sản phẩm'
                                : 'Đã quét mã thành công'),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
