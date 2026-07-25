import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image_picker/image_picker.dart';

import '../../controllers/scanner_controller.dart';
import '../widgets/custom_barcode_scanner.dart';
import '../widgets/scanner_overlay.dart';
import '../widgets/scanner_controls.dart';
import '../widgets/scanner_bottom_sheet.dart';

class SmartScannerScreen extends StatefulWidget {
  final bool isQRMode;
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
  late AnimationController _cornerController;
  late ScannerController _controller;
  final GlobalKey<CustomBarcodeScannerState> _scannerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _controller = ScannerController();

    _cornerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);
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
    final barcodeScanner = BarcodeScanner(formats: _scannerFormats);

    final barcodes = await barcodeScanner.processImage(inputImage);
    barcodeScanner.close();

    if (barcodes.isNotEmpty) {
      if (!mounted) return;

      if (!_controller.isMultiScan) {
        Navigator.of(context).pop(barcodes.first.displayValue);
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final scanWindowWidth = size.width * _controller.scanWindowSizeRatio;

          final double heightMultiplier = widget.isQRMode
              ? 1.0
              : (0.15 + 0.35 * ((_controller.scanWindowSizeRatio - 0.2) / 0.7));
          final scanWindowHeight = scanWindowWidth * heightMultiplier;

          Rect currentScanWindow = Rect.fromCenter(
            center: size.center(const Offset(0, -60)),
            width: scanWindowWidth,
            height: scanWindowHeight,
          );

          return CustomBarcodeScanner(
            key: _scannerKey,
            showBoundingBox: false,
            formats: _scannerFormats,
            scanWindow: currentScanWindow,
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
                  final firstBarcode = barcodes.first.displayValue;
                  if (firstBarcode != null) {
                    _controller.setProcessing(true);
                    _controller.setLatestBarcode(firstBarcode);

                    HapticFeedback.heavyImpact();

                    await Future.delayed(const Duration(milliseconds: 500));
                    if (context.mounted) {
                      Navigator.of(context).pop(firstBarcode);
                    }
                  }
                } else {
                  bool hasChanges = _controller.processMultiScanBarcodes(
                    barcodes,
                  );

                  if (hasChanges) {
                    _controller.setProcessing(true);
                    HapticFeedback.heavyImpact();

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
                          borderColor: Colors.white,
                          borderRadius: widget.isQRMode ? 20 : 8,
                          cornerLength: 35,
                          strokeWidth: 3,
                          cornerOffset:
                              3.0 *
                              math.sin(_cornerController.value * math.pi * 2),
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
                                  () => Navigator.of(context).pop(
                                    _controller.scannedBarcodes.map(
                                      (k, v) => MapEntry(k, v.count),
                                    ),
                                  ),
                                )
                              : ElevatedButton(
                                  onPressed: () {
                                    Navigator.of(context).pop(
                                      _controller.scannedBarcodes.map(
                                        (k, v) => MapEntry(k, v.count),
                                      ),
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.greenAccent,
                                    foregroundColor: Colors.black87,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: const Text(
                                    'Hoàn tất',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
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
                              scannedBarcodes: _controller.scannedBarcodes.map(
                                (k, v) => MapEntry(k, v.count),
                              ),
                              latestBarcode: _controller.latestBarcode,
                              hasBarcodesInFrame: barcodes.isNotEmpty,
                              bottomWidgetBuilder: widget.bottomWidgetBuilder,
                              multiScanItemBuilder: widget.multiScanItemBuilder,
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
    );
  }
}
