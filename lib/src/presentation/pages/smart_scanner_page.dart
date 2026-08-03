import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_zxing/flutter_zxing.dart' hide CameraController, ResolutionPreset, CameraLensDirection;
import '../../domain/entities/smart_scanner_result.dart';

import '../../controllers/scanner_controller.dart';
import '../widgets/custom_barcode_scanner.dart';
import '../widgets/scanner_overlay.dart';
import '../widgets/scanner_controls.dart';
import '../widgets/scanner_bottom_sheet.dart';

enum _GalleryStatus {
  idle,
  selecting,
  analyzing,
}

class SmartScannerScreen extends StatefulWidget {
  final bool isQRMode;
  final bool showMultiScanToggle;
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
    _controller = ScannerController();

    _cornerController = AnimationController(
      vsync: this,
      duration: _introDuration,
    )..forward();

    _loadingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _cornerController.dispose();
    _loadingController.dispose();
    _controller.dispose();
    super.dispose();
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
    if (_isPickingImage) return;

    // Show the loading overlay in 'selecting' state immediately — before the gallery opens
    setState(() => _galleryStatus = _GalleryStatus.selecting);

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

    try {
      // ZXing first: testing showed it catching barcodes ML Kit's decoder
      // missed entirely (0 raw results) on the same photo. ML Kit only runs as
      // a fallback if ZXing comes up empty.
      final zxCodes = await zx.readBarcodesImagePathString(
        image.path,
        DecodeParams(
          format: _zxingAllowedFormats,
          tryHarder: true,
          tryRotate: true,
          // readBarcodesImagePath (used internally by this call) converts the
          // file to RGB bytes but does NOT set imageFormat itself — leaving
          // the default (ImageFormat.lum, 1 byte/pixel) causes the RGB data
          // (3 bytes/pixel) to be misread entirely, so decoding silently fails
          // on every image regardless of content. Must set this explicitly.
          imageFormat: ImageFormat.rgb,
          // A gallery photo deserves full detail — don't downscale it to
          // ZXing's ~768px default, which is tuned for live camera frames.
          maxSize: 4000,
        ),
      );


      List<String> values = zxCodes.codes
          .where((c) => c.isValid)
          .map((c) => c.text)
          .where((t) => t != null && t.isNotEmpty)
          .cast<String>()
          .toList();

      if (values.isEmpty) {
        final inputImage = InputImage.fromFilePath(image.path);
        // Use BarcodeFormat.all to enable omnidirectional scanning, then filter in Dart
        final barcodeScanner = BarcodeScanner(formats: const [BarcodeFormat.all]);

        final rawBarcodes = await barcodeScanner.processImage(inputImage);
        barcodeScanner.close();


        values = rawBarcodes
            .where((b) => _scannerFormats.contains(b.format))
            .map((b) => b.displayValue ?? b.rawValue)
            .where((v) => v != null)
            .cast<String>()
            .toList();
      }

      if (!mounted) return;
      setState(() => _galleryStatus = _GalleryStatus.idle);

      if (values.isNotEmpty) {
        if (!_controller.isMultiScan) {
          Navigator.of(context).pop(SmartScannerResult.single(values.first));
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

  void _triggerVibration() {
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
    final title = isSelecting ? 'Đang chọn ảnh từ thư viện' : 'Đang phân tích ảnh';

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
          // Stop the heavy 1080p camera stream immediately when starting the pop animation
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
                if (barcodes.isNotEmpty && !_controller.isProcessing) {
                  if (!_controller.isMultiScan) {
                    final firstBarcode = barcodes.first.displayValue ?? barcodes.first.rawValue;
                    if (firstBarcode != null) {
                      _controller.setProcessing(true);
                      _controller.setLatestBarcode(firstBarcode);

                      _triggerVibration();

                      // Wait 200ms for green lock animation to finish before popping result
                      await Future.delayed(const Duration(milliseconds: 200));

                      if (context.mounted) {
                        _scannerKey.currentState?.pauseCamera();
                        if (ModalRoute.of(context)?.isCurrent == true) {
                          Navigator.of(
                            context,
                          ).pop(SmartScannerResult.single(firstBarcode));
                        }
                      }
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
                      finishWidget:
                          (_controller.isMultiScan &&
                              _controller.scannedBarcodes.isNotEmpty)
                          ? (widget.multiScanFinishButtonBuilder != null
                                ? widget.multiScanFinishButtonBuilder!(
                                    context,
                                    _controller.scannedBarcodes.map(
                                      (k, v) => MapEntry(k, v.count),
                                    ),
                                    () {
                                      if (ModalRoute.of(context)?.isCurrent ==
                                          true) {
                                        Navigator.of(context).pop(
                                          SmartScannerResult.multi(
                                            _controller.scannedBarcodes.map(
                                              (k, v) => MapEntry(k, v.count),
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                  )
                                : Container(
                                    height: 38,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFF10B981),
                                          Color(0xFF059669),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(
                                            0xFF10B981,
                                          ).withValues(alpha: 0.4),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () {
                                          if (ModalRoute.of(
                                                context,
                                              )?.isCurrent ==
                                              true) {
                                            Navigator.of(context).pop(
                                              SmartScannerResult.multi(
                                                _controller.scannedBarcodes.map(
                                                  (k, v) =>
                                                      MapEntry(k, v.count),
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                        borderRadius: BorderRadius.circular(20),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                          ),
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
                                  ))
                          : null,
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
                              ScannerControlsRow(
                                currentZoom: _controller.currentZoom,
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
                              const SizedBox(height: 16),
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
                            ],
                          ),
                        ),
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
