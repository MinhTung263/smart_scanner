import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

import '../../core/constants/stream_scan_constants.dart';
import '../../domain/entities/stream_frame_report.dart';
import '../../domain/entities/stream_scan_options.dart';
import '../../domain/entities/stream_scan_request.dart';
import '../../domain/entities/stream_scan_response.dart';
import '../../domain/usecases/stream_scan_dispatcher.dart';
import '../components/stream_scan_error_chip_component.dart';
import '../components/stream_scan_result_card_component.dart';
import '../components/stream_scan_slow_network_component.dart';
import '../controllers/stream_scan_controller.dart';
import '../widgets/custom_barcode_scanner.dart';
import '../widgets/scanner_controls.dart';
import '../widgets/scanner_overlay.dart';
import 'smart_scanner_page.dart';

/// Fullscreen stream scanning page with reactive result cards and chips.
class StreamScanPage extends StatefulWidget {
  /// Handler invoked for each detected barcode.
  final Future<StreamScanResponse> Function(StreamScanRequest request)? onScan;

  /// Optional underlying dispatcher handling background requests.
  final StreamScanDispatcher? dispatcher;

  /// Configuration options controlling scan behavior.
  final StreamScanOptions options;

  /// Optional vibration override flag.
  final bool? enableVibration;

  /// Barcode formats recognized during stream scan.
  final List<BarcodeFormat> formats;

  /// Custom builder for success result cards.
  final StreamScanCardBuilder? cardBuilder;

  /// Custom builder for error chips.
  final StreamScanErrorChipBuilder? chipBuilder;

  /// Custom builder for slow network hint indicator.
  final StreamScanSlowNetworkBuilder? slowNetworkBuilder;

  /// Custom builder for finish button.
  final Widget Function(BuildContext context, VoidCallback onFinish)?
  finishButtonBuilder;

  /// Optional controller injection for testing.
  final StreamScanController? controller;

  /// Default 1D barcode formats allowed in stream mode.
  static const List<BarcodeFormat> defaultFormats = <BarcodeFormat>[
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

  /// Creates a stream scanning screen page.
  const StreamScanPage({
    super.key,
    this.onScan,
    this.dispatcher,
    this.options = const StreamScanOptions(),
    this.enableVibration,
    this.formats = defaultFormats,
    this.cardBuilder,
    this.chipBuilder,
    this.slowNetworkBuilder,
    this.finishButtonBuilder,
    this.controller,
  }) : assert(
         dispatcher != null || onScan != null,
         'Either dispatcher or onScan must be provided',
       );

  @override
  State<StreamScanPage> createState() => StreamScanPageState();
}

/// State for [StreamScanPage] exposing controller for testing.
class StreamScanPageState extends State<StreamScanPage> {
  final GlobalKey<CustomBarcodeScannerState> _scannerKey =
      GlobalKey<CustomBarcodeScannerState>();

  late final StreamScanController _controller;
  late final bool _isOwnController;

  /// Underlying controller managing stream scan state.
  @visibleForTesting
  StreamScanController get controller => _controller;

  bool _isTorchOn = false;
  double _currentZoom = 1.0;
  bool _isPopping = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
      _isOwnController = false;
    } else {
      final StreamScanDispatcher dispatcher =
          widget.dispatcher ??
          StreamScanDispatcher(
            onScan: widget.onScan!,
            options: widget.options,
          );
      _controller = StreamScanController(
        onScan: dispatcher.onScan,
        dispatcher: dispatcher,
        options: widget.options,
        enableVibration: widget.enableVibration,
      );
      _isOwnController = true;
    }
  }

  @override
  void dispose() {
    if (_isOwnController) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _finishAndPop() {
    if (_isPopping) {
      return;
    }
    _isPopping = true;
    _scannerKey.currentState?.pauseCamera();
    Navigator.of(context).pop();
  }

  Future<void> _toggleFlash() async {
    final bool isOn = await _scannerKey.currentState?.toggleFlash() ?? false;
    if (mounted) {
      setState(() {
        _isTorchOn = isOn;
      });
    }
  }

  void _setZoom(double value) {
    setState(() {
      _currentZoom = value;
    });
    _scannerKey.currentState?.setZoom(value);
  }

  void _refocus(double value) {
    _scannerKey.currentState?.refocus();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) {
          return;
        }
        _finishAndPop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Size screenSize = Size(
              constraints.maxWidth,
              constraints.maxHeight,
            );
            // Ignore visibility annotation to reuse existing calculation logic.
            // ignore: invalid_use_of_visible_for_testing_member
            final Rect scanWindow = calculateScanWindow(
              screenSize: screenSize,
              sizeRatio: StreamScanConstants.defaultScanWindowRatio,
              isQRMode: false,
            );

            return Stack(
              children: <Widget>[
                Positioned.fill(
                  child: CustomBarcodeScanner(
                    key: _scannerKey,
                    formats: widget.formats,
                    scanWindow: scanWindow,
                    onDetect: (List<Barcode> barcodes) {
                      // Handled through onFrameProcessed hook.
                    },
                    onFrameProcessed: (StreamFrameReport report) {
                      _controller.onFrameProcessed(report);
                    },
                    onZoomChanged: (double zoom) {
                      if (mounted) {
                        setState(() {
                          _currentZoom = zoom;
                        });
                      }
                    },
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: ScannerOverlay(
                      scanWindow: scanWindow,
                      borderColor: Colors.white,
                      borderRadius: 8.0,
                      cornerLength: 35.0,
                      strokeWidth: 3.0,
                      overlayColor: Colors.black.withValues(alpha: 0.65),
                    ),
                  ),
                ),
                Positioned(
                  top: 0.0,
                  left: 0.0,
                  right: 0.0,
                  child: ScannerTopBar(
                    onToggleFlash: _toggleFlash,
                    isTorchOn: _isTorchOn,
                    currentZoom: _currentZoom,
                    onZoomChanged: _setZoom,
                    onZoomChangeEnd: _refocus,
                    onBack: () => _scannerKey.currentState?.pauseCamera(),
                  ),
                ),
                Positioned(
                  top: 0.0,
                  left: 0.0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 8.0,
                      ),
                      child: GestureDetector(
                        key: const ValueKey<String>('stream_scan_back_btn'),
                        behavior: HitTestBehavior.opaque,
                        onTap: _finishAndPop,
                        child: const SizedBox(width: 48.0, height: 48.0),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: StreamScanConstants.defaultComponentPadding,
                  right: StreamScanConstants.defaultComponentPadding,
                  bottom: 90.0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      StreamScanSlowNetworkComponent(
                        controller: _controller,
                        customBuilder: widget.slowNetworkBuilder,
                      ),
                      StreamScanErrorChipComponent(
                        controller: _controller,
                        customBuilder: widget.chipBuilder,
                      ),
                      StreamScanResultCardComponent(
                        controller: _controller,
                        customBuilder: widget.cardBuilder,
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: StreamScanConstants.defaultComponentPadding,
                  right: StreamScanConstants.defaultComponentPadding,
                  bottom: 24.0,
                  child: SafeArea(
                    top: false,
                    child: widget.finishButtonBuilder != null
                        ? widget.finishButtonBuilder!(context, _finishAndPop)
                        : _buildDefaultFinishButton(context),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildDefaultFinishButton(BuildContext context) {
    return ElevatedButton(
      key: const ValueKey<String>('stream_scan_finish_btn'),
      onPressed: _finishAndPop,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(StreamScanConstants.successColorValue),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14.0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            StreamScanConstants.defaultCardBorderRadius,
          ),
        ),
        elevation: 2.0,
      ),
      child: const Text(
        StreamScanConstants.defaultFinishButtonText,
        style: TextStyle(fontSize: 16.0, fontWeight: FontWeight.w700),
      ),
    );
  }
}
