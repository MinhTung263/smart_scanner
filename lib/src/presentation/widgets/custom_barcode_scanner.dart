import 'dart:async';
import 'package:app_settings/app_settings.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

import '../../data/services/barcode_scanner_service.dart';
import '../../data/services/camera_service.dart';
import 'barcode_overlay_painter.dart';
import 'glass_container.dart';

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

  bool _isDisposed = false;
  bool _isBusy = false;
  bool _isPaused = false;
  bool _isAppActive = true;
  int _session = 0;
  Future<void>? _initializing;
  final Stopwatch _clock = Stopwatch()..start();
  int _nextProcessTime = 0;
  double _currentZoom = 1.0;
  String? _cameraError;
  // Permission errors can't be fixed by retrying in-app — the error view
  // offers a shortcut to Settings instead. Coming back from Settings resumes
  // the app, which retries the camera via didChangeAppLifecycleState.
  bool _cameraErrorIsPermission = false;
  // Set once the app is actually backgrounded (hidden/paused), as opposed to
  // just inactive — which is all a system permission prompt causes.
  bool _wasInBackground = false;
  List<Barcode> _recognizedBarcodes = [];
  late final int _detectionReadyAtMs;

  // Preview remains fluid; decoding needs a much smaller frame budget.
  // Slow devices also get a rest period proportional to the last decode time.
  // Each decode is a full-frame ML Kit pass plus a frame copy to native, so
  // this rate is the main CPU/heat knob. At 5/sec a code held in frame is
  // still picked up within ~200ms.
  static const int _activeThrottleMs = 200; // at most 5 decodes/sec
  static const int _idleThrottleMs = 500;
  static const int _idleGraceMs =
      1500; // how long without activity before backing off
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
      if (_showBackAwayHint && mounted)
        setState(() => _showBackAwayHint = false);
      return;
    }

    _scanTroubleSinceMs ??= now;
    final bool shouldShow =
        (now - _scanTroubleSinceMs!) > _scanTroubleHintDelayMs;
    if ((shouldShow != _showBackAwayHint || hasGlare != _scanTroubleIsGlare) &&
        mounted) {
      setState(() {
        _showBackAwayHint = shouldShow;
        _scanTroubleIsGlare = hasGlare;
      });
    }
  }

  void _handleCameraUpdateUI() {
    if (!mounted || _isDisposed) return;
    _cameraAlive.value = _cameraService.isInitialized;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastActivityAtMs = _clock.elapsedMilliseconds;
    _lastUserActivityMs = _clock.elapsedMilliseconds;
    _startInactivityChecker();

    _detectionReadyAtMs =
        _clock.elapsedMilliseconds + widget.detectionWarmupDelay.inMilliseconds;

    _cameraService = CameraService();
    _barcodeScannerService = BarcodeScannerService(formats: widget.formats);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

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

  bool get _canScan =>
      mounted && !_isDisposed && !_isPaused && !_isAutoPaused && _isAppActive;

  Future<void> _initializeCamera() async {
    if (!_canScan) return;
    if (_initializing != null) {
      await _initializing;
      // Don't chain another attempt onto one that just failed — after a
      // permission denial that would make Android show the dialog again.
      if (_canScan && !_cameraService.isInitialized && _cameraError == null) {
        await _initializeCamera();
      }
      return;
    }
    if (_cameraService.isInitialized) return;
    final future = _startCamera();
    _initializing = future;
    try {
      await future;
    } finally {
      _initializing = null;
    }
  }

  Future<void> _startCamera() async {
    final errorMsg = await _cameraService.initializeCamera(
      onImageStream: _processCameraImage,
      isDisposedCheck: () => !_canScan,
      onUpdateUI: _handleCameraUpdateUI,
      onZoomInitialized: _handleZoomInitialized,
    );
    if (!mounted || _isDisposed) return;
    final permissionDenied =
        errorMsg != null && _cameraService.isPermissionDenied;
    // The permission prompt itself makes the app inactive, so a denial
    // usually arrives while !_canScan. Record it anyway: the resume that
    // follows has to see it, or it would start another attempt and re-prompt.
    if (!_canScan && !permissionDenied) return;
    if (errorMsg != null) {
      await _cameraService.stopLiveFeed();
      if (!mounted || _isDisposed) return;
      if (!_canScan && !permissionDenied) return;
      setState(() {
        _cameraError = errorMsg;
        _cameraErrorIsPermission = permissionDenied;
      });
    } else {
      _blurrySinceMs = null;
      _refocusOnScanWindow();
    }
  }

  // Blur-triggered refocus. Continuous autofocus normally keeps up, but it can
  // settle on the background or lag behind as the phone creeps closer. Once
  // the view has stayed soft for a short, steady stretch with nothing decoded,
  // re-aim focus at the scan window. The cooldown lets each focus sweep finish
  // before judging again, so a scene that simply can't get sharp (closer than
  // the lens's minimum focus distance) doesn't make the lens hunt nonstop.
  static const int _blurRefocusAfterMs = 600;
  static const int _refocusCooldownMs = 2000;
  int? _blurrySinceMs;
  int _lastRefocusAtMs = -_refocusCooldownMs;

  void _refocusIfBlurry({
    required int now,
    required bool isBlurry,
    required bool isMoving,
    required bool justSettled,
    required bool hasBarcode,
  }) {
    if (!isBlurry || isMoving || hasBarcode) {
      _blurrySinceMs = null;
      return;
    }
    _blurrySinceMs ??= now;
    // Just stopped after panning around: no need to wait out the delay.
    final bool due =
        justSettled || now - _blurrySinceMs! >= _blurRefocusAfterMs;
    if (due && now - _lastRefocusAtMs >= _refocusCooldownMs) {
      _refocusOnScanWindow();
    }
  }

  void _startInactivityChecker() {
    _inactivityCheckTimer?.cancel();
    _inactivityCheckTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_canScan) return;
      final int now = _clock.elapsedMilliseconds;
      if (now - _lastUserActivityMs > _autoPauseTimeoutMs) {
        _triggerAutoPause();
      }
    });
  }

  void _triggerAutoPause() {
    if (_isAutoPaused || !mounted || _isDisposed) return;
    _session++;
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
    _lastUserActivityMs = _clock.elapsedMilliseconds;
    _lastActivityAtMs = _clock.elapsedMilliseconds;
    await _initializeCamera();
  }

  void _handleZoomInitialized(double zoom) {
    if (!_canScan) return;
    _currentZoom = zoom;
    _cameraService.handleScaleStart(zoom);
    if (widget.onZoomChanged != null) widget.onZoomChanged!(zoom);
  }

  Future<void> stopCameraSafely() async {
    if (_isDisposed) return;
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
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
    if (!listEquals(oldWidget.formats, widget.formats)) {
      _barcodeScannerService.updateFormats(widget.formats);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed) return;
    if (state == AppLifecycleState.resumed) {
      _isAppActive = true;
      final wasInBackground = _wasInBackground;
      _wasInBackground = false;
      // Resuming from the permission prompt itself (the app was only
      // inactive) must not retry: Android would ask again straight away, and
      // once the user has blocked the permission every attempt flashes an
      // invisible, auto-denying prompt that resumes the app again — an
      // endless loop that keeps the scanner stuck on its loading state. Only
      // retry after a real trip away from the app, e.g. to Settings.
      if (_cameraError != null && _cameraErrorIsPermission && !wasInBackground) {
        return;
      }
      if (_canScan) {
        setState(() => _cameraError = null);
        _initializeCamera();
      }
    } else {
      if (state == AppLifecycleState.hidden ||
          state == AppLifecycleState.paused) {
        _wasInBackground = true;
      }
      _isAppActive = false;
      _session++;
        _pulseController.stop();
      _cameraAlive.value = false;
      _cameraService.stopLiveFeed(onUpdateUI: _handleCameraUpdateUI);
    }
  }

  void _processCameraImage(CameraImage image) async {
    if (_isBusy || !_canScan || _cameraService.currentCamera == null) return;

    final int now = _clock.elapsedMilliseconds;
    if (now < _detectionReadyAtMs || now < _nextProcessTime) return;
    final bool idle = (now - _lastActivityAtMs) > _idleGraceMs;
    final int throttleMs = idle ? _idleThrottleMs : _activeThrottleMs;
    final session = _session;
    _isBusy = true;
    try {
      final screenSize = MediaQuery.of(context).size;

      // NOTE: crop-to-scan-window is temporarily disabled (not passing
      // scanWindow/screenSize here falls back to full-frame decoding) while we
      // isolate a reported bounding-box distortion — see processCameraImage's
      // crop path in barcode_scanner_service.dart.
      final (
        barcodes,
        justSettled,
        isMoving,
        isBlurry,
        hasGlare,
      ) = await _barcodeScannerService.processCameraImage(
        image,
        _cameraService.currentCamera!,
      );

      if (!_canScan || session != _session) return;

      if (isMoving || justSettled || barcodes.isNotEmpty) {
        _lastActivityAtMs = now;
        _lastUserActivityMs = now;
      }

      _refocusIfBlurry(
        now: now,
        isBlurry: isBlurry,
        isMoving: isMoving,
        justSettled: justSettled,
        hasBarcode: barcodes.isNotEmpty,
      );

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
          final imageSize = Size(
            image.width.toDouble(),
            image.height.toDouble(),
          );

          if (previewSize != null) {
            final filteredBarcodes = _barcodeScannerService
                .filterAndSortBarcodes(
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
              _pulseController.repeat(reverse: true);
            }

            if (filteredBarcodes.isNotEmpty) {
              _clearBarcodesTimer?.cancel();
              _clearBarcodesTimer = null;
              setState(() {
                _recognizedBarcodes = filteredBarcodes;
              });

              widget.onDetect(filteredBarcodes);
            } else if (_recognizedBarcodes.isNotEmpty) {
              // Barcodes lost: play reverse exit animation (fade-out & scale-out) smoothly back to hidden state
              if (_clearBarcodesTimer == null ||
                  !_clearBarcodesTimer!.isActive) {
                _lockController.reverse();
                _clearBarcodesTimer = Timer(
                  const Duration(milliseconds: 200),
                  () {
                    if (mounted && !_isDisposed) {
                      _pulseController.stop();
                      setState(() {
                        _recognizedBarcodes = [];
                      });
                    }
                  },
                );
              }
            }
          }
        }
      }
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'smart_scanner',
          context: ErrorDescription('while processing a camera frame'),
        ),
      );
    } finally {
      final finished = _clock.elapsedMilliseconds;
      final elapsed = finished - now;
      // Never immediately re-run a slow decoder; allow time for rendering
      // and cap sustained decoder duty to roughly 50% on slower devices.
      _nextProcessTime =
          finished + (elapsed > throttleMs ~/ 2 ? elapsed : throttleMs ~/ 2);
      if (_nextProcessTime < now + throttleMs)
        _nextProcessTime = now + throttleMs;
      _isBusy = false;
    }
  }

  void setZoom(double zoomLevel) {
    if (_cameraService.isInitialized) {
      _currentZoom = zoomLevel;
      _cameraService.setZoomLevel(zoomLevel, widget.onZoomChanged);
    }
  }

  void refocus() {
    _refocusOnScanWindow();
  }

  /// Focuses on the scan window's center when one is provided, so the camera
  /// keeps prioritizing sharpness where the barcode actually appears instead
  /// of resetting to a whole-frame default point.
  void _refocusOnScanWindow() {
    if (!_canScan) return;
    _lastRefocusAtMs = _clock.elapsedMilliseconds;
    final scanWindow = widget.scanWindow;
    if (scanWindow == null) {
      _cameraService.focusOnScreenPosition(context, null);
      return;
    }
    _cameraService.focusOnScanWindow(scanWindow, MediaQuery.of(context).size);
  }

  Future<void> pauseCamera() async {
    if (_isDisposed) return;
    _isPaused = true;
    _session++;
    _cameraAlive.value = false;
    _pulseController.stop();
    _lockController.stop();
    _clearBarcodesTimer?.cancel();
    await _cameraService.stopLiveFeed();
  }

  Future<void> resumeCamera() async {
    if (_isDisposed || !mounted) return;
    _isPaused = false;
    _recognizedBarcodes = [];
    _lastActivityAtMs = _lastUserActivityMs = _clock.elapsedMilliseconds;
    await _initializeCamera();
  }

  void _handleScaleStart(ScaleStartDetails details) {
    if (widget.onWindowScaleStart != null) {
      widget.onWindowScaleStart!();
    }
    _cameraService.handleScaleStart(_currentZoom);
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2) return;
    if (widget.onWindowScaleUpdate != null) {
      widget.onWindowScaleUpdate!(details.scale);
    }
    _cameraService.handleScaleUpdate(details.scale, (zoomLevel) {
      if (mounted && !_isDisposed) {
        _currentZoom = zoomLevel;
        if (widget.onZoomChanged != null) {
          widget.onZoomChanged!(zoomLevel);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraError != null) {
      return _CameraErrorView(
        message: _cameraError!,
        isPermissionDenied: _cameraErrorIsPermission,
        onRetry: () {
          setState(() => _cameraError = null);
          _initializeCamera();
        },
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
          key: ValueKey(_session),
          duration: const Duration(milliseconds: 400),
          child: (isCameraReady && controller != null)
              ? GestureDetector(
                  key: const ValueKey('camera_preview'),
                  onScaleStart: (details) {
                    _lastUserActivityMs = _clock.elapsedMilliseconds;
                    _handleScaleStart(details);
                  },
                  onScaleUpdate: (details) {
                    _lastUserActivityMs = _clock.elapsedMilliseconds;
                    _handleScaleUpdate(details);
                  },
                  onScaleEnd: (details) => _refocusOnScanWindow(),
                  onDoubleTap: () {
                    _lastUserActivityMs = _clock.elapsedMilliseconds;
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
                    _lastUserActivityMs = _clock.elapsedMilliseconds;
                    final scanWindow = widget.scanWindow;
                    if (scanWindow != null) {
                      if (scanWindow.contains(details.localPosition)) {
                        _refocusOnScanWindow();
                        _showFocusIndicatorAt(scanWindow.center);
                      }
                    } else {
                      _cameraService.focusOnScreenPosition(context, details);
                      _showFocusIndicatorAt(details.localPosition);
                    }
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
                            // An outgoing switcher child must never revive its
                            // old controller when a new camera becomes ready.
                            if (!alive || !_canScan ||
                                _cameraService.controller != controller) {
                              return const SizedBox.shrink();
                            }
                            return RepaintBoundary(child: CameraPreview(controller));
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
            child: _AutoPauseOverlay(
              onResume: _resumeFromAutoPause,
            ),
          ),
      ],
    );
  }
}

/// Full-screen state shown when the camera can't be opened. Replaces the whole
/// scanner (including the host's overlay and its back button), so it carries
/// its own way out.
class _CameraErrorView extends StatelessWidget {
  final String message;
  final bool isPermissionDenied;
  final VoidCallback onRetry;

  const _CameraErrorView({
    required this.message,
    required this.isPermissionDenied,
    required this.onRetry,
  });

  static const _accent = Color(0xFF10B981);

  @override
  Widget build(BuildContext context) {
    final bool canPop = Navigator.of(context).canPop();

    // Material (not a plain Container) so the back button's InkWell works even
    // when the scanner is embedded without a Scaffold above it.
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: Stack(
          children: [
            if (canPop)
              Positioned(
                left: 16,
                top: 8,
                child: GlassContainer(
                  padding: EdgeInsets.zero,
                  borderRadius: 16,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => Navigator.of(context).maybePop(),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF1F2937),
                        border: Border.all(
                          color: (isPermissionDenied
                                  ? _accent
                                  : Colors.redAccent)
                              .withValues(alpha: 0.6),
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        isPermissionDenied
                            ? Icons.no_photography_outlined
                            : Icons.error_outline_rounded,
                        color: isPermissionDenied ? _accent : Colors.redAccent,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      isPermissionDenied
                          ? 'Chưa có quyền truy cập Camera'
                          : 'Không mở được camera',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (isPermissionDenied) ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => AppSettings.openAppSettings(),
                          icon: const Icon(Icons.settings_rounded),
                          label: const Text('Mở Cài đặt'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: onRetry,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white70,
                        ),
                        child: const Text('Thử lại'),
                      ),
                    ] else
                      ElevatedButton.icon(
                        onPressed: onRetry,
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
          ],
        ),
      ),
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

class _AutoPauseOverlay extends StatefulWidget {
  final VoidCallback onResume;
  const _AutoPauseOverlay({required this.onResume});

  @override
  State<_AutoPauseOverlay> createState() => _AutoPauseOverlayState();
}

class _AutoPauseOverlayState extends State<_AutoPauseOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _pulseAnimation = Tween<double>(begin: 0.2, end: 0.6).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      builder: (context, opacity, child) {
        return Opacity(
          opacity: opacity,
          child: GestureDetector(
            onTap: widget.onResume,
            behavior: HitTestBehavior.opaque,
            child: Container(
              color: Colors.black.withValues(alpha: 0.82),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // --- Pulsing glowing icon container ---
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _scaleAnimation.value,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Outer pulsing aura
                                Container(
                                  width: 110,
                                  height: 110,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFF10B981)
                                        .withValues(alpha: _pulseAnimation.value * 0.3),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF10B981)
                                            .withValues(alpha: _pulseAnimation.value * 0.5),
                                        blurRadius: 30,
                                        spreadRadius: 10,
                                      ),
                                    ],
                                  ),
                                ),
                                // Inner glass circle
                                Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFF1F2937),
                                    border: Border.all(
                                      color: const Color(0xFF10B981)
                                          .withValues(alpha: 0.6),
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.4),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.play_arrow_rounded,
                                    color: Color(0xFF10B981),
                                    size: 44,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 28),
                      // --- Title ---
                      const Text(
                        'Máy quét đang ở chế độ chờ',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      // --- Subtitle with touch hint ---
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.touch_app_rounded,
                              color: Color(0xFF10B981),
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Chạm vào màn hình để tiếp tục quét',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
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
