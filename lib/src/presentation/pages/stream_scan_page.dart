import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

import '../../core/constants/stream_scan_constants.dart';
import '../../domain/entities/stream_scan_card_item.dart';
import '../../domain/entities/stream_scan_options.dart';
import '../../domain/entities/stream_scan_request.dart';
import '../../domain/entities/stream_scan_response.dart';
import '../../domain/usecases/stream_scan_dispatcher.dart';
import '../components/stream_scan_continuous_toggle_component.dart';
import '../components/stream_scan_counter_component.dart';
import '../components/stream_scan_error_chip_component.dart';
import '../components/stream_scan_result_card_component.dart';
import '../components/stream_scan_slow_network_component.dart';
import '../controllers/stream_scan_controller.dart';
import '../widgets/custom_barcode_scanner.dart';
import '../widgets/scanner_controls.dart';
import '../widgets/scanner_overlay.dart';
import 'smart_scanner_page.dart';

/// Asks the user to confirm leaving; `true` means leave and discard.
typedef StreamScanExitConfirmBuilder =
    Future<bool> Function(BuildContext context);

/// Fullscreen stream scanning page (spec "Bán nhanh - Quét hàng loạt").
/// Pops with `true` when the user confirmed leaving (discard), else `false`.
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

  /// Custom builder for the scanned product card content.
  final StreamScanCardBuilder? cardBuilder;

  /// Custom builder for toast chips.
  final StreamScanErrorChipBuilder? chipBuilder;

  /// Custom builder for slow network hint indicator.
  final StreamScanSlowNetworkBuilder? slowNetworkBuilder;

  /// Custom builder for finish button.
  final Widget Function(BuildContext context, VoidCallback onFinish)?
  finishButtonBuilder;

  /// Custom exit confirmation; defaults to a simple dialog.
  final StreamScanExitConfirmBuilder? exitConfirmBuilder;

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
    this.exitConfirmBuilder,
    this.controller,
  }) : assert(
         dispatcher != null || onScan != null || controller != null,
         'Either dispatcher, onScan or controller must be provided',
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
  bool _isConfirmingExit = false;

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

  void _finish() => _pop(discarded: false);

  void _pop({required bool discarded}) {
    if (_isPopping) {
      return;
    }
    _isPopping = true;
    _scannerKey.currentState?.pauseCamera();
    Navigator.of(context).pop(discarded);
  }

  /// Back button / system back: confirm first when something was scanned.
  Future<void> _requestExit() async {
    if (_isPopping || _isConfirmingExit) {
      return;
    }
    if (!_controller.hasScannedItems) {
      _pop(discarded: false);
      return;
    }

    _isConfirmingExit = true;
    _controller.pause();
    final bool leave = widget.exitConfirmBuilder != null
        ? await widget.exitConfirmBuilder!(context)
        : await _showDefaultExitDialog();
    _isConfirmingExit = false;
    if (!mounted) {
      return;
    }
    if (leave) {
      _pop(discarded: true);
    } else {
      _controller.resume();
    }
  }

  Future<bool> _showDefaultExitDialog() async {
    final bool? leave = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text(StreamScanConstants.exitConfirmTitle),
          content: const Text(StreamScanConstants.exitConfirmMessage),
          actions: <Widget>[
            TextButton(
              key: const ValueKey<String>('stream_scan_exit_stay'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text(StreamScanConstants.exitConfirmStay),
            ),
            TextButton(
              key: const ValueKey<String>('stream_scan_exit_leave'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: const Color(
                  StreamScanConstants.errorColorValue,
                ),
              ),
              child: const Text(StreamScanConstants.exitConfirmLeave),
            ),
          ],
        );
      },
    );
    return leave ?? false;
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
    return PopScope<bool>(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, bool? result) {
        if (didPop) {
          return;
        }
        _requestExit();
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
            final double topBarBottom =
                MediaQuery.paddingOf(context).top +
                StreamScanConstants.topBarHeight;
            final double belowFrameTop =
                scanWindow.bottom + StreamScanConstants.belowFrameGap;

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
                    onFrameProcessed: _controller.onFrameProcessed,
                    onZoomChanged: (double zoom) {
                      if (mounted) {
                        setState(() {
                          _currentZoom = zoom;
                        });
                      }
                    },
                  ),
                ),
                Positioned.fill(child: _buildFrameOverlay(scanWindow)),
                Positioned.fromRect(
                  rect: scanWindow,
                  child: _buildFrameContent(),
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
                  ),
                ),
                // Intercepts the top bar back button so exit can be confirmed.
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
                        onTap: _requestExit,
                        child: const SizedBox(width: 48.0, height: 48.0),
                      ),
                    ),
                  ),
                ),
                // Toast chips sit between the top bar and the scan frame.
                Positioned(
                  top: topBarBottom,
                  left: StreamScanConstants.defaultComponentPadding,
                  right: StreamScanConstants.defaultComponentPadding,
                  child: Center(
                    child: StreamScanErrorChipComponent(
                      controller: _controller,
                      customBuilder: widget.chipBuilder,
                    ),
                  ),
                ),
                Positioned(
                  top: belowFrameTop,
                  left: scanWindow.left,
                  child: StreamScanContinuousToggleComponent(
                    controller: _controller,
                  ),
                ),
                Positioned(
                  top: belowFrameTop + 44.0,
                  left: 0.0,
                  right: 0.0,
                  child: Center(
                    child: StreamScanCounterComponent(controller: _controller),
                  ),
                ),
                Positioned(
                  left: StreamScanConstants.defaultComponentPadding,
                  right: StreamScanConstants.defaultComponentPadding,
                  bottom: 0.0,
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        StreamScanSlowNetworkComponent(
                          controller: _controller,
                          customBuilder: widget.slowNetworkBuilder,
                        ),
                        StreamScanResultCardComponent(
                          controller: _controller,
                          customBuilder: widget.cardBuilder,
                        ),
                        const SizedBox(height: 20.0),
                        Center(
                          child: widget.finishButtonBuilder != null
                              ? widget.finishButtonBuilder!(context, _finish)
                              : _buildDefaultFinishButton(),
                        ),
                        const SizedBox(height: 16.0),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Scan frame corners; flash green on accept, red on reject.
  Widget _buildFrameOverlay(Rect scanWindow) {
    return IgnorePointer(
      child: ValueListenableBuilder<StreamScanFrameFlash>(
        valueListenable: _controller.frameFlash,
        builder: (BuildContext context, StreamScanFrameFlash flash, _) {
          final Color borderColor = switch (flash) {
            StreamScanFrameFlash.success => const Color(
              StreamScanConstants.successColorValue,
            ),
            StreamScanFrameFlash.error => const Color(
              StreamScanConstants.errorColorValue,
            ),
            StreamScanFrameFlash.none => Colors.white,
          };
          return ScannerOverlay(
            scanWindow: scanWindow,
            borderColor: borderColor,
            borderRadius: 8.0,
            cornerLength: 35.0,
            strokeWidth: 3.0,
            overlayColor: Colors.black.withValues(alpha: 0.65),
          );
        },
      ),
    );
  }

  /// Empty while scanning; "Chạm để quét tiếp" while paused in single mode.
  Widget _buildFrameContent() {
    return ValueListenableBuilder<bool>(
      valueListenable: _controller.isWaitingForTap,
      builder: (BuildContext context, bool isWaiting, _) {
        if (!isWaiting) {
          return const SizedBox.shrink();
        }
        return GestureDetector(
          key: const ValueKey<String>('stream_scan_tap_to_continue'),
          behavior: HitTestBehavior.opaque,
          onTap: _controller.continueScanning,
          child: Container(
            alignment: Alignment.center,
            color: Colors.black.withValues(alpha: 0.45),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.touch_app_rounded, color: Colors.white, size: 20.0),
                SizedBox(width: StreamScanConstants.defaultItemSpacing),
                Text(
                  StreamScanConstants.tapToContinueLabel,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15.0,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDefaultFinishButton() {
    const Color green = Color(StreamScanConstants.successColorValue);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28.0),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: green.withValues(alpha: 0.45),
            blurRadius: 16.0,
            offset: const Offset(0.0, 4.0),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        key: const ValueKey<String>('stream_scan_finish_btn'),
        onPressed: _finish,
        icon: const Icon(Icons.check_circle_outline_rounded, size: 22.0),
        label: const Text(
          StreamScanConstants.defaultFinishButtonText,
          style: TextStyle(fontSize: 16.0, fontWeight: FontWeight.w800),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: green,
          foregroundColor: Colors.black87,
          elevation: 0.0,
          padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 14.0),
          shape: const StadiumBorder(),
        ),
      ),
    );
  }
}
