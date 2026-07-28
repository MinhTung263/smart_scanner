import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

import '../../data/services/barcode_scanner_service.dart';
import '../../data/services/camera_service.dart';
import 'barcode_overlay_painter.dart';

class CustomBarcodeScanner extends StatefulWidget {
  final List<BarcodeFormat> formats;
  final Widget Function(
    BuildContext context,
    List<Barcode> barcodes,
    Size? imageSize,
  )?
  overlayBuilder;
  final void Function(List<Barcode> barcodes) onDetect;
  final bool showBoundingBox;
  final Color boundingBoxColor;
  final Rect? scanWindow;
  final IconData? loadingIcon;
  final void Function()? onWindowScaleStart;
  final void Function(double scale)? onWindowScaleUpdate;
  final void Function(double zoomLevel)? onZoomChanged;

  /// Barcodes found before this delay (measured from when the scanner first
  /// mounts) are ignored, so a code already in frame doesn't get accepted
  /// while the entrance UI (e.g. the guide frame animation) is still settling.
  final Duration detectionWarmupDelay;

  const CustomBarcodeScanner({
    Key? key,
    required this.onDetect,
    this.formats = const [BarcodeFormat.all],
    this.showBoundingBox = true,
    this.boundingBoxColor = Colors.red,
    this.scanWindow,
    this.loadingIcon,
    this.overlayBuilder,
    this.onWindowScaleStart,
    this.onWindowScaleUpdate,
    this.onZoomChanged,
    this.detectionWarmupDelay = Duration.zero,
  }) : super(key: key);

  @override
  State<CustomBarcodeScanner> createState() => CustomBarcodeScannerState();
}

class CustomBarcodeScannerState extends State<CustomBarcodeScanner>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final CameraService _cameraService;
  late final BarcodeScannerService _barcodeScannerService;
  late final AnimationController _pulseController;
  Timer? _clearBarcodesTimer;

  bool _isDisposed = false;
  bool _isBusy = false;
  int _lastProcessTime = 0;
  double _currentZoom = 1.0;
  String? _cameraError;
  List<Barcode> _recognizedBarcodes = [];
  late final int _detectionReadyAtMs;

  // Adaptive frame-rate throttle: run at full speed while the phone is being
  // moved around or something's actually in frame, but back off once it's
  // been idle for a while to cut sustained CPU load (and heat) during long
  // scanning sessions. Speeds back up the instant motion resumes or a code
  // appears, so it never trades away responsiveness while actually scanning.
  static const int _activeThrottleMs = 20; // ~50 FPS cap
  static const int _idleThrottleMs = 100; // ~10 FPS cap
  static const int _idleGraceMs = 1500; // how long without activity before backing off
  late int _lastActivityAtMs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastActivityAtMs = DateTime.now().millisecondsSinceEpoch;

    _detectionReadyAtMs = DateTime.now()
        .add(widget.detectionWarmupDelay)
        .millisecondsSinceEpoch;

    _cameraService = CameraService();
    _barcodeScannerService = BarcodeScannerService(formats: widget.formats);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    // Delay initialization slightly so that the route transition animation (push)
    // runs at 60fps smoothly before the heavy native camera blocks the main thread.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isDisposed) {
        _initializeCamera();
      }
    });
  }

  Future<void> _initializeCamera() async {
    final errorMsg = await _cameraService.initializeCamera(
      onImageStream: _processCameraImage,
      isDisposedCheck: () => _isDisposed,
      onUpdateUI: () {
        if (mounted) setState(() {});
      },
      onZoomInitialized: _handleZoomInitialized,
    );

    if (errorMsg != null && mounted) {
      setState(() {
        _cameraError = errorMsg;
      });
    } else if (mounted && !_isDisposed) {
      // Prioritize sharpness on the scan window from the very first frame,
      // instead of whatever whole-frame point the camera defaults to.
      _refocusOnScanWindow();
    }
  }

  void _handleZoomInitialized(double zoom) {
    _currentZoom = zoom;
    _cameraService.handleScaleStart(zoom);
    if (widget.onZoomChanged != null) widget.onZoomChanged!(zoom);
  }

  Future<void> stopCameraSafely() async {
    if (_isDisposed) return;
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);

    await _cameraService.stopLiveFeed(
      isDisposing: true,
      onScannerClose: () => _barcodeScannerService.close(),
    );
    _cameraService.cancelZoomTimer();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _clearBarcodesTimer?.cancel();
    if (!_isDisposed) {
      _isDisposed = true;
      WidgetsBinding.instance.removeObserver(this);

      _cameraService.stopLiveFeed(
        isDisposing: true,
        onScannerClose: () => _barcodeScannerService.close(),
      );
      _cameraService.cancelZoomTimer();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(CustomBarcodeScanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.formats != widget.formats) {
      _barcodeScannerService.updateFormats(widget.formats);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _cameraService.stopLiveFeed(
        onUpdateUI: () {
          if (mounted) setState(() {});
        },
      );
    } else if (state == AppLifecycleState.resumed) {
      if (_cameraError != null || _cameraService.currentCamera == null) {
        setState(() => _cameraError = null);
        _initializeCamera();
      } else if (!_cameraService.isInitialized) {
        _cameraService.initializeCamera(
          onImageStream: _processCameraImage,
          isDisposedCheck: () => _isDisposed,
          onUpdateUI: () {
            if (mounted) setState(() {});
          },
          onZoomInitialized: _handleZoomInitialized,
        );
      }
    }
  }

  void _processCameraImage(CameraImage image) async {
    if (_isBusy || _isDisposed || _cameraService.currentCamera == null) return;

    final int now = DateTime.now().millisecondsSinceEpoch;
    // Ultra-Fast when active: 50 FPS cap (20ms). Backs off to ~10 FPS after a
    // stretch of no motion and nothing in frame, to cut sustained CPU/heat
    // during long idle waits — see the adaptive-throttle fields above.
    final bool idle = (now - _lastActivityAtMs) > _idleGraceMs;
    final int throttleMs = idle ? _idleThrottleMs : _activeThrottleMs;
    if (now - _lastProcessTime < throttleMs) return;

    _isBusy = true;
    _lastProcessTime = now;

    final screenSize = MediaQuery.of(context).size;

    // NOTE: crop-to-scan-window is temporarily disabled (not passing
    // scanWindow/screenSize here falls back to full-frame decoding) while we
    // isolate a reported bounding-box distortion — see processCameraImage's
    // crop path in barcode_scanner_service.dart.
    final (barcodes, justSettled, isMoving) = await _barcodeScannerService.processCameraImage(
      image,
      _cameraService.currentCamera!,
    );

    if (isMoving || justSettled || barcodes.isNotEmpty) {
      _lastActivityAtMs = now;
    }

    if (justSettled && mounted && !_isDisposed) {
      // The phone just stopped moving after being panned around looking for
      // a code; refresh focus on the scan window while it's held steady.
      _refocusOnScanWindow();
    }

    if (mounted && !_isDisposed) {
      // Ignore anything found while the entrance UI is still settling in,
      // so a code already in frame on open doesn't get accepted instantly.
      if (barcodes.isNotEmpty && now >= _detectionReadyAtMs) {
        _clearBarcodesTimer?.cancel();

        final controller = _cameraService.controller;
        final previewSize = controller?.value.previewSize;
        final imageSize = Size(image.width.toDouble(), image.height.toDouble());

        if (previewSize != null) {
          final filteredBarcodes = _barcodeScannerService.filterAndSortBarcodes(
            barcodes,
            imageSize,
            previewSize,
            screenSize,
            widget.scanWindow,
          );

          setState(() {
            _recognizedBarcodes = filteredBarcodes;
          });

          if (filteredBarcodes.isNotEmpty) {
            widget.onDetect(filteredBarcodes);
          }
        }
      } else {
        // Debounce clearing the barcodes to prevent flickering on frame drops
        if (_recognizedBarcodes.isNotEmpty &&
            (_clearBarcodesTimer == null || !_clearBarcodesTimer!.isActive)) {
          _clearBarcodesTimer = Timer(const Duration(milliseconds: 300), () {
            if (mounted && !_isDisposed) {
              setState(() {
                _recognizedBarcodes = [];
              });
            }
          });
        }
      }
    }

    _isBusy = false;
  }

  void setZoom(double zoomLevel) {
    if (_cameraService.isInitialized) {
      _cameraService.controller?.setZoomLevel(zoomLevel);
    }
  }

  void refocus() {
    _refocusOnScanWindow();
  }

  /// Focuses on the scan window's center when one is provided, so the camera
  /// keeps prioritizing sharpness where the barcode actually appears instead
  /// of resetting to a whole-frame default point.
  void _refocusOnScanWindow() {
    final scanWindow = widget.scanWindow;
    if (scanWindow == null) {
      _cameraService.focusOnScreenPosition(context, null);
      return;
    }
    _cameraService.focusOnScanWindow(scanWindow, MediaQuery.of(context).size);
  }

  Future<void> pauseCamera() async {
    if (_cameraService.controller?.value.isStreamingImages == true) {
      await _cameraService.controller?.stopImageStream();
    }
  }

  void _handleScaleStart(ScaleStartDetails details) {
    if (widget.onWindowScaleStart != null) {
      widget.onWindowScaleStart!();
    }
    _cameraService.handleScaleStart(_currentZoom);
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (widget.onWindowScaleUpdate != null) {
      widget.onWindowScaleUpdate!(details.scale);
    }
    _cameraService.handleScaleUpdate(details.scale, (zoomLevel) {
      _currentZoom = zoomLevel;
      if (widget.onZoomChanged != null) widget.onZoomChanged!(zoomLevel);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraError != null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _cameraError!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() => _cameraError = null);
                    _initializeCamera();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Thử lại'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white24,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final bool isCameraReady = _cameraService.isInitialized;
    final controller = _cameraService.controller;

    final size = MediaQuery.of(context).size;
    // Raw sensor preview size (e.g. 1280x720, always landscape-oriented on Android)
    // matching the coordinate space ML Kit's barcode.boundingBox is reported in.
    // mapMlKitRectToScreen() does its own portrait swap on this raw value.
    final previewSize = isCameraReady && controller != null
        ? controller.value.previewSize!
        : Size.zero;
    // Portrait-swapped size, used only to size the CameraPreview inside the FittedBox.
    final imageSize = isCameraReady && controller != null
        ? Size(previewSize.height, previewSize.width)
        : Size.zero;

    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: (isCameraReady && controller != null)
              ? GestureDetector(
                  key: const ValueKey('camera_preview'),
                  onScaleStart: _handleScaleStart,
                  onScaleUpdate: _handleScaleUpdate,
                  onScaleEnd: (details) => _refocusOnScanWindow(),
                  onDoubleTap: () {
                    // Toggle between the default zoom and the max available,
                    // for a quick zoom-in on small barcodes. Anchored to the
                    // camera's own default/max instead of hardcoded values, so
                    // it never zooms out below the level the scanner opened
                    // with (previously toggled to 1.0x, below the 1.5x default).
                    final controller = _cameraService.controller;
                    if (controller != null) {
                      final double baseZoom = CameraService.defaultZoomLevel
                          .clamp(_cameraService.minZoomLevel, _cameraService.maxZoomLevel);
                      final bool isAtBase = (_currentZoom - baseZoom).abs() < 0.05;
                      _currentZoom = isAtBase ? _cameraService.maxZoomLevel : baseZoom;
                      controller.setZoomLevel(_currentZoom);
                      _cameraService.handleScaleStart(_currentZoom);
                      if (widget.onZoomChanged != null)
                        widget.onZoomChanged!(_currentZoom);
                    }
                  },
                  onTapDown: (details) =>
                      _cameraService.focusOnScreenPosition(context, details),
                  child: SizedBox.expand(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: imageSize.width,
                        height: imageSize.height,
                        child: CameraPreview(controller),
                      ),
                    ),
                  ),
                )
              : Container(
                  key: const ValueKey('loading_background'),
                  color: Colors.black,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (widget.scanWindow != null)
                        Positioned(
                          left: widget.scanWindow!.center.dx - 70,
                          top: widget.scanWindow!.center.dy - 70,
                          child: _ScannerLoadingAnimation(
                            icon: widget.loadingIcon,
                          ),
                        )
                      else
                        Center(
                          child: _ScannerLoadingAnimation(
                            icon: widget.loadingIcon,
                          ),
                        ),
                    ],
                  ),
                ),
        ),

        if (widget.showBoundingBox &&
            _recognizedBarcodes.isNotEmpty &&
            isCameraReady)
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return CustomPaint(
                painter: BarcodeOverlayPainter(
                  barcodes: _recognizedBarcodes,
                  imageSize: previewSize,
                  screenSize: size,
                  color: widget.boundingBoxColor,
                  pulseValue: _pulseController.value,
                  zoomLevel: _currentZoom,
                ),
              );
            },
          ),

        if (widget.overlayBuilder != null)
          widget.overlayBuilder!(context, _recognizedBarcodes, imageSize),
      ],
    );
  }
}

class _ScannerLoadingAnimation extends StatefulWidget {
  final IconData? icon;
  const _ScannerLoadingAnimation({this.icon});

  @override
  State<_ScannerLoadingAnimation> createState() =>
      _ScannerLoadingAnimationState();
}

class _ScannerLoadingAnimationState extends State<_ScannerLoadingAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );

    _opacityAnimation = Tween<double>(begin: 0.2, end: 0.8).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(
                    0xFF10B981,
                  ).withValues(alpha: _opacityAnimation.value * 0.4),
                  blurRadius: 40,
                  spreadRadius: 10,
                ),
                BoxShadow(
                  color: const Color(
                    0xFF10B981,
                  ).withValues(alpha: _opacityAnimation.value * 0.15),
                  blurRadius: 80,
                  spreadRadius: 30,
                ),
              ],
              gradient: RadialGradient(
                colors: [
                  const Color(
                    0xFF10B981,
                  ).withValues(alpha: _opacityAnimation.value * 0.8),
                  const Color(
                    0xFF059669,
                  ).withValues(alpha: _opacityAnimation.value * 0.3),
                  Colors.transparent,
                ],
                stops: const [0.2, 0.6, 1.0],
              ),
            ),
            child: Center(
              child: Icon(
                widget.icon ?? Icons.qr_code_scanner,
                color: Colors.white.withValues(alpha: 0.9),
                size: 52,
              ),
            ),
          ),
        );
      },
    );
  }
}
