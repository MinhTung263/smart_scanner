import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image_picker/image_picker.dart';
import '../../domain/entities/smart_scanner_result.dart';

import '../../controllers/scanner_controller.dart';
import '../widgets/custom_barcode_scanner.dart';
import '../widgets/scanner_overlay.dart';
import '../widgets/scanner_controls.dart';
import '../widgets/scanner_bottom_sheet.dart';

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
  static const _introDuration = Duration(milliseconds: 350);

  late AnimationController _cornerController;
  late ScannerController _controller;
  final GlobalKey<CustomBarcodeScannerState> _scannerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _controller = ScannerController();

    _cornerController = AnimationController(
      vsync: this,
      duration: _introDuration,
    )..forward();
  }

  @override
  void dispose() {
    _cornerController.dispose();
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

  Future<void> _pickImageFromGallery() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    final inputImage = InputImage.fromFilePath(image.path);
    // Use BarcodeFormat.all to enable omnidirectional scanning, then filter in Dart
    final barcodeScanner = BarcodeScanner(formats: const [BarcodeFormat.all]);

    final rawBarcodes = await barcodeScanner.processImage(inputImage);
    barcodeScanner.close();

    final barcodes = rawBarcodes
        .where((b) => _scannerFormats.contains(b.format))
        .toList();

    if (barcodes.isNotEmpty) {
      if (!mounted) return;

      if (!_controller.isMultiScan) {
        final barcode = barcodes.first.displayValue ?? barcodes.first.rawValue;
        if (barcode != null) {
          Navigator.of(context).pop(SmartScannerResult.single(barcode));
        }
      } else {
        _controller.processMultiScanBarcodes(barcodes);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã tìm thấy ${barcodes.length} mã trong ảnh'),
          ),
        );
      }
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm thấy mã nào trong ảnh!')),
      );
    }
  }

  void _triggerVibration() {
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}
    try {
      HapticFeedback.vibrate();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: PopScope(
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

                      // Pause camera and return result instantly (0ms delay)
                      _scannerKey.currentState?.pauseCamera();
                      if (context.mounted) {
                        if (ModalRoute.of(context)?.isCurrent == true) {
                          Navigator.of(
                            context,
                          ).pop(SmartScannerResult.single(firstBarcode));
                        }
                      }
                    }
                  } else {
                    bool hasChanges = _controller.processMultiScanBarcodes(
                      barcodes,
                    );

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
    );
  }
}
