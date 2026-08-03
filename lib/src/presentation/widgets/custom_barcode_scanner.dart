import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    this.boundingBoxColor = const Color(0xFF10B981),
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
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late final CameraService _cameraService;
  late final BarcodeScannerService _barcodeScannerService;
  late final AnimationController _pulseController;
  late final AnimationController _lockController;
  Timer? _clearBarcodesTimer;
  Timer? _periodicRefocusTimer;

  bool _isDisposed = false;
  bool _isBusy = false;
  bool _isAutoZooming = false;
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
  static const int _idleThrottleMs = 250; // ~4 FPS cap
  static const int _idleGraceMs = 1500; // how long without activity before backing off
  static const int _autoPauseTimeoutMs = 60000; // Auto-pause after 60s idle
  late int _lastActivityAtMs;
  late int _lastUserActivityMs;
  bool _isAutoPaused = false;
  Timer? _inactivityCheckTimer;

  // Guards CameraPreview against CameraController's async teardown.
  // AnimatedSwitcher keeps the outgoing "camera_preview" branch mounted (and
  // subscribed to the controller) for its whole crossfade duration; if
  // stopImageStream()/dispose() notify listeners during that window,
  // CameraPreview's own ValueListenableBuilder rebuilds and calls
  // buildPreview() on an already-disposed controller, throwing
  // "Disposed CameraController". Flipping this to false synchronously, before
  // the async teardown starts, swaps CameraPreview out immediately so that
  // race can't happen.
  final ValueNotifier<bool> _cameraAlive = ValueNotifier(false);

  // Visual feedback for tap-to-focus: a small bracket that briefly appears
  // where focus was requested, then shrinks and fades out on its own. The id
  // (rather than the position) is used as the indicator's key so tapping the
  // exact same spot twice in a row still restarts the animation.
  Offset? _focusIndicatorPosition;
  int _focusIndicatorId = 0;

  void _showFocusIndicatorAt(Offset position) {
    if (!mounted) return;
    setState(() {
      _focusIndicatorPosition = position;
      _focusIndicatorId++;
    });
  }

  // "Back away a bit" hint: shown once the frame has been blurry OR glare-
  // affected — a glare edge is still a sharp edge, so this is a separate
  // signal from blur, but the same remedy (back away / change angle) helps
  // both — *and* the phone has been held steady *and* nothing has decoded,
  // for a sustained stretch. Never on a single bad frame, so it doesn't nag
  // during normal panning/searching or a brief blip.
  static const int _scanTroubleHintDelayMs = 2500;
  int? _scanTroubleSinceMs;
  bool _scanTroubleIsGlare = false;
  bool _showBackAwayHint = false;

  void _updateBackAwayHint({
    required int now,
    required bool isBlurry,
    required bool hasGlare,
    required bool isMoving,
    required bool hasBarcode,
  }) {
    final bool sustained = (isBlurry || hasGlare) && !isMoving && !hasBarcode;
    if (!sustained) {
      _scanTroubleSinceMs = null;
      if (_showBackAwayHint && mounted) setState(() => _showBackAwayHint = false);
      return;
    }

    _scanTroubleSinceMs ??= now;
    final bool shouldShow = (now - _scanTroubleSinceMs!) > _scanTroubleHintDelayMs;
    if ((shouldShow != _showBackAwayHint || hasGlare != _scanTroubleIsGlare) && mounted) {
      setState(() {
        _showBackAwayHint = shouldShow;
        _scanTroubleIsGlare = hasGlare;
      });
    }
  }

  void _handleCameraUpdateUI() {
    if (!mounted) return;
    _cameraAlive.value = _cameraService.isInitialized;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastActivityAtMs = DateTime.now().millisecondsSinceEpoch;
    _lastUserActivityMs = DateTime.now().millisecondsSinceEpoch;
    _startInactivityChecker();

    _detectionReadyAtMs = DateTime.now()
        .add(widget.detectionWarmupDelay)
        .millisecondsSinceEpoch;

    _cameraService = CameraService();
    _barcodeScannerService = BarcodeScannerService(formats: widget.formats);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _lockController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

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
      onUpdateUI: _handleCameraUpdateUI,
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
      _startPeriodicRefocus();
    }
  }

  /// Nudges autofocus every ~900ms while still searching for a code, instead
  /// of relying solely on the motion-just-settled trigger. That trigger can
  /// fail to fire at close range: the same small hand tremor produces a much
  /// bigger apparent frame-to-frame change when the subject fills more of the
  /// frame, so the motion detector may never register "settled" — leaving the
  /// lens stuck at whatever distance it last focused on and the image blurry
  /// once the phone is moved in close.
  void _startPeriodicRefocus() {
    _periodicRefocusTimer?.cancel();
    _periodicRefocusTimer = Timer.periodic(const Duration(milliseconds: 3000), (_) {
      if (!mounted || _isDisposed || _isAutoPaused) return;
      // Leave a working focus alone once a code is actually in frame.
      if (_recognizedBarcodes.isEmpty) {
        _refocusOnScanWindow();
      }
    });
  }

  void _stopPeriodicRefocus() {
    _periodicRefocusTimer?.cancel();
    _periodicRefocusTimer = null;
  }

  void _startInactivityChecker() {
    _inactivityCheckTimer?.cancel();
    _inactivityCheckTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || _isDisposed || _isAutoPaused) return;
      final int now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastUserActivityMs > _autoPauseTimeoutMs) {
        _triggerAutoPause();
      }
    });
  }

  void _triggerAutoPause() {
    if (_isAutoPaused || !mounted || _isDisposed) return;
    _stopPeriodicRefocus();
    _pulseController.stop();
    _lockController.stop();
    _cameraAlive.value = false;
    _cameraService.stopLiveFeed(onUpdateUI: _handleCameraUpdateUI);
    setState(() {
      _isAutoPaused = true;
    });
  }

  Future<void> _resumeFromAutoPause() async {
    if (!_isAutoPaused || _isDisposed || !mounted) return;
    setState(() {
      _isAutoPaused = false;
    });
    _lastUserActivityMs = DateTime.now().millisecondsSinceEpoch;
    _lastActivityAtMs = DateTime.now().millisecondsSinceEpoch;
    if (!_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    }
    await _initializeCamera();
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
    _stopPeriodicRefocus();
    _cameraAlive.value = false;

    await _cameraService.stopLiveFeed(
      isDisposing: true,
      onScannerClose: () => _barcodeScannerService.close(),
    );
    _cameraService.cancelZoomTimer();
  }

  /// Toggles camera flash (torch) and returns new state.
  Future<bool> toggleFlash() async {
    final isOn = await _cameraService.toggleTorch();
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
    return isOn;
  }

  bool get isTorchOn => _cameraService.isTorchOn;

  @override
  void dispose() {
    _pulseController.dispose();
    _lockController.dispose();
    _clearBarcodesTimer?.cancel();
    _inactivityCheckTimer?.cancel();
    _stopPeriodicRefocus();
    _cameraAlive.value = false;
    _cameraAlive.dispose();
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
      _stopPeriodicRefocus();
      _cameraService.stopLiveFeed(
        onUpdateUI: _handleCameraUpdateUI,
      );
    } else if (state == AppLifecycleState.resumed) {
      if (_cameraError != null || _cameraService.currentCamera == null) {
        setState(() => _cameraError = null);
        _initializeCamera();
      } else if (!_cameraService.isInitialized) {
        _cameraService.initializeCamera(
          onImageStream: _processCameraImage,
          isDisposedCheck: () => _isDisposed,
          onUpdateUI: _handleCameraUpdateUI,
          onZoomInitialized: _handleZoomInitialized,
        ).then((errorMsg) {
          if (errorMsg == null && mounted && !_isDisposed) {
            _refocusOnScanWindow();
            _startPeriodicRefocus();
          }
        });
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
    final (barcodes, justSettled, isMoving, isBlurry, hasGlare) =
        await _barcodeScannerService.processCameraImage(
      image,
      _cameraService.currentCamera!,
    );

    if (isMoving || justSettled || barcodes.isNotEmpty) {
      _lastActivityAtMs = now;
      _lastUserActivityMs = now;
    }

    if (justSettled && mounted && !_isDisposed) {
      // The phone just stopped moving after being panned around looking for
      // a code; refresh focus on the scan window while it's held steady.
      _refocusOnScanWindow();
    }

    _updateBackAwayHint(
      now: now,
      isBlurry: isBlurry,
      hasGlare: hasGlare,
      isMoving: isMoving,
      hasBarcode: barcodes.isNotEmpty,
    );

    if (mounted && !_isDisposed) {
      if (now >= _detectionReadyAtMs) {
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

          if (_recognizedBarcodes.isEmpty && filteredBarcodes.isNotEmpty) {
            _clearBarcodesTimer?.cancel();
            _clearBarcodesTimer = null;
            _lockController.forward(from: 0.0);
          }

          if (filteredBarcodes.isNotEmpty) {
            _clearBarcodesTimer?.cancel();
            _clearBarcodesTimer = null;
            setState(() {
              _recognizedBarcodes = filteredBarcodes;
            });

            final firstBarcode = filteredBarcodes.first;
            final mappedRect = BarcodeScannerService.mapMlKitRectToScreen(
              rawRect: firstBarcode.boundingBox,
              previewSize: previewSize,
              screenSize: screenSize,
            );
            _autoZoomToBarcode(mappedRect, screenSize);
            widget.onDetect(filteredBarcodes);
          } else if (_recognizedBarcodes.isNotEmpty) {
            // Barcodes lost: play reverse exit animation (fade-out & scale-out) smoothly back to hidden state
            if (_clearBarcodesTimer == null || !_clearBarcodesTimer!.isActive) {
              _lockController.reverse();
              _clearBarcodesTimer = Timer(const Duration(milliseconds: 200), () {
                if (mounted && !_isDisposed) {
                  setState(() {
                    _recognizedBarcodes = [];
                  });
                }
              });
            }
          }
        }
      }
    }

    _isBusy = false;
  }

  Future<void> _autoZoomToBarcode(Rect mappedRect, Size screenSize) async {
    if (_isAutoZooming || !_cameraService.isInitialized || _cameraService.maxZoomLevel <= 1.0) return;

    final scanWinWidth = widget.scanWindow?.width ?? (screenSize.width * 0.7);
    final double qrRatio = (mappedRect.width / scanWinWidth).clamp(0.05, 1.0);

    if (qrRatio < 0.5) {
      final double targetZoom = (_currentZoom * (0.55 / qrRatio)).clamp(
        _cameraService.minZoomLevel,
        _cameraService.maxZoomLevel,
      );

      if ((targetZoom - _currentZoom).abs() > 0.2) {
        _isAutoZooming = true;
        _currentZoom = targetZoom;
        await _cameraService.setZoomLevel(targetZoom, widget.onZoomChanged);
        await Future.delayed(const Duration(milliseconds: 300));
        _isAutoZooming = false;
      }
    }
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

  void pauseCamera() {
    _cameraAlive.value = false;
    _pulseController.stop();
    _lockController.stop();
    _stopPeriodicRefocus();
    final controller = _cameraService.controller;
    if (controller != null && controller.value.isInitialized && controller.value.isStreamingImages) {
      controller.stopImageStream().catchError((_) {});
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
                  onScaleStart: (details) {
                    _lastUserActivityMs = DateTime.now().millisecondsSinceEpoch;
                    _handleScaleStart(details);
                  },
                  onScaleUpdate: (details) {
                    _lastUserActivityMs = DateTime.now().millisecondsSinceEpoch;
                    _handleScaleUpdate(details);
                  },
                  onScaleEnd: (details) => _refocusOnScanWindow(),
                  onDoubleTap: () {
                    _lastUserActivityMs = DateTime.now().millisecondsSinceEpoch;
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
                  onTapDown: (details) {
                    _lastUserActivityMs = DateTime.now().millisecondsSinceEpoch;
                    final scanWindow = widget.scanWindow;
                    final Offset focusIndicatorPoint;
                    if (scanWindow != null && scanWindow.contains(details.localPosition)) {
                      // Focus the scan window's center rather than the exact
                      // tap point: the barcode itself is high-contrast and
                      // easy for autofocus to lock onto, but a slightly
                      // off-target tap can land on low-contrast background
                      // next to it, where autofocus struggles to converge at
                      // all — confirmed by zoom's center-based refocus
                      // achieving focus at distances where exact-tap focus
                      // didn't.
                      _refocusOnScanWindow();
                      focusIndicatorPoint = scanWindow.center;
                    } else {
                      _cameraService.focusOnScreenPosition(context, details);
                      focusIndicatorPoint = details.localPosition;
                    }
                    _showFocusIndicatorAt(focusIndicatorPoint);
                  },
                  child: SizedBox.expand(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: imageSize.width,
                        height: imageSize.height,
                        child: ValueListenableBuilder<bool>(
                          valueListenable: _cameraAlive,
                          builder: (context, alive, _) {
                            if (!alive) return const SizedBox.shrink();
                            return CameraPreview(controller);
                          },
                        ),
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
            animation: Listenable.merge([_pulseController, _lockController]),
            builder: (context, child) {
              return CustomPaint(
                painter: BarcodeOverlayPainter(
                  barcodes: _recognizedBarcodes,
                  imageSize: previewSize,
                  screenSize: size,
                  color: widget.boundingBoxColor,
                  pulseValue: _pulseController.value,
                  lockValue: _lockController.value,
                  zoomLevel: _currentZoom,
                ),
              );
            },
          ),

        if (widget.overlayBuilder != null)
          widget.overlayBuilder!(context, _recognizedBarcodes, imageSize),

        if (_showBackAwayHint && isCameraReady)
          Positioned(
            left: 24,
            right: 24,
            top: widget.scanWindow != null
                ? widget.scanWindow!.bottom + 16
                : size.height / 2 + 90,
            child: IgnorePointer(
              child: Center(
                child: AnimatedOpacity(
                  opacity: _showBackAwayHint ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(180),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _scanTroubleIsGlare
                          ? 'Mã đang bị lóa sáng, hãy lùi ra hoặc đổi góc quét một chút'
                          : 'Ảnh đang mờ, hãy lùi camera ra xa mã vạch một chút',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

        if (_focusIndicatorPosition != null)
          Positioned(
            left: _focusIndicatorPosition!.dx - 36,
            top: _focusIndicatorPosition!.dy - 36,
            child: IgnorePointer(
              child: _FocusIndicator(
                key: ValueKey(_focusIndicatorId),
                onCompleted: () {
                  if (mounted) setState(() => _focusIndicatorPosition = null);
                },
              ),
            ),
          ),

        if (_isAutoPaused)
          Positioned.fill(
            child: GestureDetector(
              onTap: _resumeFromAutoPause,
              behavior: HitTestBehavior.opaque,
              child: Container(
                color: Colors.black.withValues(alpha: 0.85),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.pause_circle_outline_rounded,
                            color: Colors.white,
                            size: 56,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Đã tạm dừng để tiết kiệm pin & làm mát máy',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Chạm vào màn hình để tiếp tục quét',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One-shot bracket that appears where a focus request was made, shrinks
/// slightly and fades out, then reports back so the parent can remove it.
class _FocusIndicator extends StatefulWidget {
  final VoidCallback onCompleted;
  const _FocusIndicator({super.key, required this.onCompleted});

  @override
  State<_FocusIndicator> createState() => _FocusIndicatorState();
}

class _FocusIndicatorState extends State<_FocusIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onCompleted();
      }
    });
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
        final double t = _controller.value.clamp(0.0, 1.0);
        final double scale = 1.35 - 0.35 * Curves.easeOut.transform(t);
        final double opacity = t < 0.55 ? 1.0 : (1.0 - (t - 0.55) / 0.45).clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        );
      },
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
