import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CameraService {
  // Global lock to prevent overlapping camera lifecycles on rapid screen transitions
  static Future<void>? _globalDisposeFuture;

  // Default zoom on open, to help resolve small/dense barcodes without giving up
  // the fast 720p startup path. Clamped to the device's actual zoom range below.
  static const double defaultZoomLevel = 1.5;

  CameraController? _controller;
  Future<void>? _initializeControllerFuture;

  List<CameraDescription> _cameras = [];
  int _cameraIndex = -1;

  double minZoomLevel = 1.0;
  double maxZoomLevel = 1.0;

  // Throttle variable for zoom
  int _lastZoomTime = 0;
  Timer? _zoomTimer;
  double _baseScale = 1.0;

  CameraController? get controller => _controller;
  bool get isInitialized =>
      _controller != null && _controller!.value.isInitialized;
  CameraDescription? get currentCamera =>
      _cameraIndex >= 0 && _cameras.isNotEmpty ? _cameras[_cameraIndex] : null;

  static List<CameraDescription>? _cachedCameras;

  static Future<void> preloadCameras() async {
    if (_cachedCameras == null || _cachedCameras!.isEmpty) {
      try {
        _cachedCameras = await availableCameras();
      } catch (_) {}
    }
  }

  /// Initializes the camera and starts the live feed.
  /// Returns an error string if something goes wrong, or null on success.
  Future<String?> initializeCamera({
    required void Function(CameraImage image) onImageStream,
    required bool Function() isDisposedCheck,
    required VoidCallback onUpdateUI,
    void Function(double zoom)? onZoomInitialized,
  }) async {
    final sw = Stopwatch()..start();
    debugPrint('[SmartScanner][perf] initializeCamera() start');

    // Wait for any previous camera instance to finish disposing before starting a new one
    if (_globalDisposeFuture != null) {
      try {
        await _globalDisposeFuture;
      } catch (_) {}
    }
    debugPrint('[SmartScanner][perf] dispose-wait done: ${sw.elapsedMilliseconds}ms');

    if (_cameras.isEmpty) {
      if (_cachedCameras != null && _cachedCameras!.isNotEmpty) {
        _cameras = _cachedCameras!;
        debugPrint('[SmartScanner][perf] camera list from warm cache: ${sw.elapsedMilliseconds}ms');
      } else {
        try {
          _cameras = await availableCameras();
          _cachedCameras = _cameras;
          debugPrint('[SmartScanner][perf] availableCameras() (cold, not warmed up) resolved: ${sw.elapsedMilliseconds}ms');
        } catch (e) {
          debugPrint('Error getting cameras: $e');
          return 'Lỗi truy cập camera: $e';
        }
      }
    }

    if (isDisposedCheck()) return null;

    if (_cameras.isEmpty) {
      return 'Thiết bị không có camera khả dụng';
    }

    for (int i = 0; i < _cameras.length; i++) {
      if (_cameras[i].lensDirection == CameraLensDirection.back) {
        _cameraIndex = i;
        break;
      }
    }
    if (_cameraIndex == -1) _cameraIndex = 0;

    return await _startLiveFeed(
      onImageStream,
      isDisposedCheck,
      onUpdateUI,
      onZoomInitialized,
      sw,
    );
  }

  Future<String?> _startLiveFeed(
    void Function(CameraImage image) onImageStream,
    bool Function() isDisposedCheck,
    VoidCallback onUpdateUI, [
    void Function(double zoom)? onZoomInitialized,
    Stopwatch? sw,
  ]) async {
    if (isDisposedCheck()) return null;

    final camera = _cameras[_cameraIndex];
    String? errorMsg;

    final controller = CameraController(
      camera,
      // 1080p: repeated real-world testing showed small/dense barcodes
      // (product tags, IMEI labels) failing to decode at 720p — the extra
      // pixels matter more than the small camera-init time difference.
      ResolutionPreset.veryHigh,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888, // MUST be bgra8888 on iOS for ML Kit
    );
    _controller = controller;

    try {
      _initializeControllerFuture = controller.initialize();
      await _initializeControllerFuture;
      debugPrint('[SmartScanner][perf] controller.initialize() done: ${sw?.elapsedMilliseconds}ms');

      // If stopLiveFeed was called during initialization (e.g., app went to background for permission dialog),
      // _controller will be null. We must abort to prevent using a disposed controller.
      if (isDisposedCheck() || _controller != controller) {
        return null;
      }

      final zoomLevels = await Future.wait([
        controller.getMinZoomLevel(),
        controller.getMaxZoomLevel(),
      ]);
      minZoomLevel = zoomLevels[0];
      final nativeMax = zoomLevels[1];
      maxZoomLevel = nativeMax > 2.5 ? 2.5 : nativeMax;
      debugPrint('[SmartScanner][perf] zoom levels fetched: ${sw?.elapsedMilliseconds}ms');

      if (isDisposedCheck() || _controller != controller) {
        return null;
      }

      await _ensureContinuousAutofocus(controller);
      await _applyDefaultZoom(controller, onZoomInitialized);
      debugPrint('[SmartScanner][perf] default zoom applied: ${sw?.elapsedMilliseconds}ms');

      await controller.startImageStream(onImageStream);
      debugPrint('[SmartScanner][perf] startImageStream() done, preview should show now: ${sw?.elapsedMilliseconds}ms');
      onUpdateUI();
    } on CameraException catch (e) {
      debugPrint('CameraException: ${e.code}: ${e.description}');

      // Fallback if NV21 is not supported on this Android device
      if (Platform.isAndroid && e.code == 'UnsupportedImageFormat') {
        // Try falling back to default YUV420
        return await _startLiveFeedFallbackYuv(
          onImageStream,
          isDisposedCheck,
          onUpdateUI,
          onZoomInitialized,
        );
      }

      switch (e.code) {
        case 'CameraAccessDenied':
          errorMsg = 'Bạn cần cấp quyền sử dụng Camera trong Cài đặt';
          break;
        case 'CameraAccessDeniedWithoutPrompt':
          errorMsg =
              'Quyền Camera bị từ chối vĩnh viễn, vui lòng mở Cài đặt để cấp lại';
          break;
        default:
          errorMsg = 'Lỗi camera: ${e.description ?? e.code}';
      }
      onUpdateUI();
    } catch (e) {
      debugPrint('Error initializing camera: $e');
      if (!e.toString().contains('used after being disposed')) {
        errorMsg = 'Lỗi hệ thống camera: $e';
        onUpdateUI();
      }
    }

    return errorMsg;
  }

  Future<String?> _startLiveFeedFallbackYuv(
    void Function(CameraImage image) onImageStream,
    bool Function() isDisposedCheck,
    VoidCallback onUpdateUI, [
    void Function(double zoom)? onZoomInitialized,
  ]) async {
    if (isDisposedCheck()) return null;

    final camera = _cameras[_cameraIndex];
    String? errorMsg;

    final controller = CameraController(
      camera,
      ResolutionPreset.veryHigh, // 1080p: Perfect balance of sharpness for tiny barcodes and 60FPS speed
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420, // Must be yuv420 as this is the fallback
    );
    _controller = controller;

    try {
      _initializeControllerFuture = controller.initialize();
      await _initializeControllerFuture;

      if (isDisposedCheck() || _controller != controller) return null;

      minZoomLevel = await controller.getMinZoomLevel();
      final nativeMax = await controller.getMaxZoomLevel();
      maxZoomLevel = nativeMax > 2.5 ? 2.5 : nativeMax;

      if (isDisposedCheck() || _controller != controller) return null;

      await _ensureContinuousAutofocus(controller);
      await _applyDefaultZoom(controller, onZoomInitialized);

      await controller.startImageStream(onImageStream);
      onUpdateUI();
    } catch (e) {
      errorMsg = 'Lỗi camera (YUV): $e';
      onUpdateUI();
    }

    return errorMsg;
  }

  Future<void> _applyDefaultZoom(
    CameraController controller,
    void Function(double zoom)? onZoomInitialized,
  ) async {
    final zoom = defaultZoomLevel.clamp(minZoomLevel, maxZoomLevel);
    try {
      await controller.setZoomLevel(zoom);
      onZoomInitialized?.call(zoom);
    } catch (e) {
      debugPrint('Error applying default zoom: $e');
    }
  }

  /// Explicitly requests continuous autofocus rather than trusting whatever
  /// the platform defaults to, so the lens keeps hunting for sharpness on its
  /// own as subject distance changes (e.g. the phone moving closer) instead
  /// of only reacting to our own explicit focus-point nudges.
  Future<void> _ensureContinuousAutofocus(CameraController controller) async {
    try {
      await controller.setFocusMode(FocusMode.auto);
    } catch (e) {
      debugPrint('Error setting continuous autofocus: $e');
    }
  }

  Future<void> stopLiveFeed({
    bool isDisposing = false,
    Future<void> Function()? onScannerClose,
    VoidCallback? onUpdateUI,
  }) async {
    final cameraController = _controller;
    final initFuture = _initializeControllerFuture;

    _controller = null;
    _initializeControllerFuture = null;

    // Create a completer for the global lock
    final completer = Completer<void>();
    _globalDisposeFuture = completer.future;

    if (!isDisposing && onUpdateUI != null) onUpdateUI();

    try {
      // Must wait for initialization to complete before disposing to prevent native camera freezes
      if (initFuture != null) {
        // Do NOT use timeout here. We MUST wait for initialize to finish completely.
        // Calling dispose() while initialize() is still running natively will permanently freeze Android cameras.
        await initFuture;
      }

      if (cameraController != null &&
          cameraController.value.isStreamingImages) {
        // Do NOT use timeout. Bypassing this will cause native crash.
        await cameraController.stopImageStream();
      }
      if (cameraController != null) {
        // Do NOT use timeout. Bypassing this will cause native crash.
        await cameraController.dispose();
      }
    } catch (e) {
      debugPrint('Error disposing camera: $e');
    } finally {
      if (onScannerClose != null) {
        try {
          await onScannerClose().timeout(const Duration(milliseconds: 1000));
        } catch (_) {}
      }
      if (!completer.isCompleted) completer.complete();
    }
  }

  void handleScaleStart(double currentZoomLevel) {
    _baseScale = currentZoomLevel;
  }

  void handleScaleUpdate(double scale, void Function(double) onZoomChanged) {
    if (_controller == null || _cameras.isEmpty) return;

    // Throttle zoom events
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastZoomTime < 50) return;
    _lastZoomTime = now;

    double zoomLevel = _baseScale * scale;
    if (zoomLevel < minZoomLevel) zoomLevel = minZoomLevel;
    if (zoomLevel > maxZoomLevel) zoomLevel = maxZoomLevel;

    _controller!.setZoomLevel(zoomLevel);
    onZoomChanged(zoomLevel);
  }

  Future<void> focusOnScreenPosition(
    BuildContext context,
    TapDownDetails? details,
  ) async {
    if (details == null) {
      await focusOnPoint(null);
      return;
    }
    final size = MediaQuery.of(context).size;
    final double dx = (details.localPosition.dx / size.width).clamp(0.0, 1.0);
    final double dy = (details.localPosition.dy / size.height).clamp(0.0, 1.0);
    await focusOnPoint(Offset(dx, dy));
  }

  /// Focuses and meters exposure on the center of the visible scan window
  /// (the white guide frame) instead of resetting to the camera's default
  /// whole-frame auto point, so the barcode area itself stays sharp.
  Future<void> focusOnScanWindow(Rect scanWindow, Size screenSize) async {
    if (screenSize.width == 0 || screenSize.height == 0) {
      await focusOnPoint(null);
      return;
    }
    final double dx = (scanWindow.center.dx / screenSize.width).clamp(0.0, 1.0);
    final double dy = (scanWindow.center.dy / screenSize.height).clamp(0.0, 1.0);
    await focusOnPoint(Offset(dx, dy));
  }

  Future<void> focusOnPoint(Offset? normalizedOffset) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      if (normalizedOffset != null) {
        // Clear first so a repeat request at the same point (e.g. the
        // periodic re-focus nudge) can't be treated as a no-op and skipped —
        // this forces a genuinely fresh autofocus scan every time, which
        // matters most right after the phone moves closer to the subject.
        await controller.setFocusPoint(null);
        await controller.setFocusPoint(normalizedOffset);
        await controller.setExposurePoint(normalizedOffset);
      } else {
        await controller.setFocusPoint(null);
        await controller.setExposurePoint(null);
      }
    } catch (e) {
      debugPrint('Error during refocus: $e');
    }
  }

  void cancelZoomTimer() {
    _zoomTimer?.cancel();
  }
}
