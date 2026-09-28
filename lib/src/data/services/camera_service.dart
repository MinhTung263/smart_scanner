import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CameraService {
  // Global lock to prevent overlapping camera lifecycles on rapid screen transitions
  static Future<void>? _globalDisposeFuture;

  // Default zoom on open, to help resolve small/dense barcodes without giving up
  // the fast 720p startup path. Clamped to the device's actual zoom range below.
  static const double defaultZoomLevel = 1.5;

  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  Future<void>? _stopFuture;

  List<CameraDescription> _cameras = [];
  int _cameraIndex = -1;

  double minZoomLevel = 1.0;
  double maxZoomLevel = 1.0;

  Timer? _zoomTimer;
  double _baseScale = 1.0;

  /// Whether the last [initializeCamera] failed because camera access is
  /// denied or restricted. The OS won't prompt again in that case (iOS never
  /// re-prompts; Android 11+ stops after the user declines twice), so the only
  /// way forward is for the user to enable it in the system Settings app.
  bool get isPermissionDenied => _isPermissionDenied;
  bool _isPermissionDenied = false;

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
    _isPermissionDenied = false;

    // Wait for any previous camera instance to finish disposing before starting a new one
    if (_globalDisposeFuture != null) {
      try {
        await _globalDisposeFuture;
      } catch (_) {}
    }

    if (_cameras.isEmpty) {
      if (_cachedCameras != null && _cachedCameras!.isNotEmpty) {
        _cameras = _cachedCameras!;
      } else {
        try {
          _cameras = await availableCameras();
          _cachedCameras = _cameras;
        } catch (e) {
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
      // Keep the existing ~720p preset for small labels. Bound capture FPS
      // separately from the lower decoder rate to reduce camera/ISP load.
      ResolutionPreset.high,
      enableAudio: false,
      // camera_avfoundation copies every captured frame (~3.7 MB of BGRA at
      // 720p) over to Dart regardless of how many we actually decode, so the
      // capture rate itself is a steady CPU/heat cost on iOS. Android stays at
      // 30: CameraX applies this as a fixed [fps, fps] range, and a fixed 24
      // range isn't guaranteed to be supported on every device.
      fps: Platform.isIOS ? 24 : 30,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888, // MUST be bgra8888 on iOS for ML Kit
    );
    _controller = controller;

    try {
      _initializeControllerFuture = controller.initialize();
      await _initializeControllerFuture;

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
      maxZoomLevel = nativeMax > 3.0 ? 3.0 : nativeMax;

      if (isDisposedCheck() || _controller != controller) {
        return null;
      }

      await _lockPortraitCapture(controller);
      await _ensureContinuousAutofocus(controller);
      await _applyDefaultZoom(controller, onZoomInitialized);

      if (isDisposedCheck() || _controller != controller) return null;
      await controller.startImageStream(onImageStream);
      onUpdateUI();
    } on CameraException catch (e) {
      // Fallback if NV21 is not supported on this Android device
      if (Platform.isAndroid && e.code == 'UnsupportedImageFormat') {
        // Release the failed camera before opening the YUV fallback.
        await stopLiveFeed();
        if (isDisposedCheck()) return null;
        return await _startLiveFeedFallbackYuv(
          onImageStream,
          isDisposedCheck,
          onUpdateUI,
          onZoomInitialized,
        );
      }

      switch (e.code) {
        // iOS: CameraAccessDenied when the user just declined the prompt,
        // CameraAccessDeniedWithoutPrompt on every later attempt. Android
        // reports CameraAccessDenied for both.
        case 'CameraAccessDenied':
        case 'CameraAccessDeniedWithoutPrompt':
          _isPermissionDenied = true;
          errorMsg =
              'Ứng dụng chưa được cấp quyền sử dụng Camera. Hãy mở Cài đặt, '
              'bật quyền Camera rồi quay lại để quét mã.';
          break;
        case 'CameraAccessRestricted':
          _isPermissionDenied = true;
          errorMsg =
              'Quyền Camera đang bị giới hạn trên thiết bị này (ví dụ bởi '
              'Thời gian sử dụng). Hãy kiểm tra lại trong Cài đặt.';
          break;
        default:
          errorMsg = 'Lỗi camera: ${e.description ?? e.code}';
      }
      onUpdateUI();
    } catch (e) {
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
      ResolutionPreset
          .high, // 720p: Optimal balance of sharpness and thermal efficiency
      enableAudio: false,
      fps: 30,
      imageFormatGroup:
          ImageFormatGroup.yuv420, // Must be yuv420 as this is the fallback
    );
    _controller = controller;

    try {
      _initializeControllerFuture = controller.initialize();
      await _initializeControllerFuture;

      if (isDisposedCheck() || _controller != controller) return null;

      minZoomLevel = await controller.getMinZoomLevel();
      final nativeMax = await controller.getMaxZoomLevel();
      maxZoomLevel = nativeMax > 3.0 ? 3.0 : nativeMax;

      if (isDisposedCheck() || _controller != controller) return null;

      await _lockPortraitCapture(controller);
      await _ensureContinuousAutofocus(controller);
      await _applyDefaultZoom(controller, onZoomInitialized);

      if (isDisposedCheck() || _controller != controller) return null;
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
    } catch (e) {}
  }

  /// Pins capture to portrait to match the portrait-only scanner UI. Without
  /// this, CameraPreview on Android rotates the feed by the *physical* device
  /// orientation, so tilting the phone turns the preview sideways even though
  /// the screen itself stays locked.
  Future<void> _lockPortraitCapture(CameraController controller) async {
    try {
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
    } catch (e) {}
  }

  /// Explicitly requests continuous autofocus rather than trusting whatever
  /// the platform defaults to, so the lens keeps hunting for sharpness on its
  /// own as subject distance changes (e.g. the phone moving closer) instead
  /// of only reacting to our own explicit focus-point nudges.
  Future<void> _ensureContinuousAutofocus(CameraController controller) async {
    try {
      await controller.setFocusMode(FocusMode.auto);
    } catch (e) {}
  }

  Future<void> stopLiveFeed({
    bool isDisposing = false,
    Future<void> Function()? onScannerClose,
    VoidCallback? onUpdateUI,
  }) async {
    final stopping = _stopFuture;
    if (stopping != null) {
      await stopping;
      if (onScannerClose != null) await onScannerClose();
      return;
    }
    final future = _stopLiveFeed(
      isDisposing: isDisposing,
      onUpdateUI: onUpdateUI,
    );
    _stopFuture = future;
    try {
      await future;
    } finally {
      _stopFuture = null;
      if (onScannerClose != null) await onScannerClose();
    }
  }

  Future<void> _stopLiveFeed({
    required bool isDisposing,
    VoidCallback? onUpdateUI,
  }) async {
    final cameraController = _controller;
    final initFuture = _initializeControllerFuture;

    _controller = null;
    _initializeControllerFuture = null;

    _isTorchOn = false;
    final previousDispose = _globalDisposeFuture;

    // Create a completer for the global lock
    final completer = Completer<void>();
    _globalDisposeFuture = completer.future;

    if (!isDisposing && onUpdateUI != null) onUpdateUI();

    try {
      await previousDispose;
      // Must wait for initialization to complete before disposing to prevent native camera freezes
      if (initFuture != null) {
        // Do NOT use timeout here. We MUST wait for initialize to finish completely.
        // Calling dispose() while initialize() is still running natively will permanently freeze Android cameras.
        try {
          await initFuture;
        } catch (_) {
          // Failed initialization still owns native resources that need disposal.
        }
      }

      if (cameraController != null &&
          cameraController.value.isStreamingImages) {
        // Do NOT use timeout. Bypassing this will cause native crash.
        try {
          await cameraController.stopImageStream();
        } catch (_) {}
      }
      if (cameraController != null) {
        // Do NOT use timeout. Bypassing this will cause native crash.
        await cameraController.dispose();
      }
    } catch (e) {
    } finally {
      if (!completer.isCompleted) completer.complete();
      // Nothing left to wait for once the latest disposal is done. Clearing
      // the static lock also stops it leaking a completed future — bound to
      // whatever zone created it — into later camera sessions (in widget
      // tests, a previous test's FakeAsync zone, which never runs again).
      if (identical(_globalDisposeFuture, completer.future)) {
        _globalDisposeFuture = null;
      }
    }
  }

  bool _isSettingZoom = false;
  double _lastAppliedZoom = 1.0;

  void handleScaleStart(double currentZoomLevel) {
    _baseScale = currentZoomLevel;
    _lastAppliedZoom = currentZoomLevel;
  }

  void handleScaleUpdate(
    double scale,
    void Function(double) onZoomChanged,
  ) async {
    final controller = _controller;
    if (controller == null || _cameras.isEmpty || _isSettingZoom) return;

    double zoomLevel = _baseScale * scale;
    if (zoomLevel < minZoomLevel) zoomLevel = minZoomLevel;
    if (zoomLevel > maxZoomLevel) zoomLevel = maxZoomLevel;

    if ((_lastAppliedZoom - zoomLevel).abs() < 0.02) return;

    _isSettingZoom = true;
    _lastAppliedZoom = zoomLevel;

    try {
      await controller.setZoomLevel(zoomLevel);
      onZoomChanged(zoomLevel);
    } catch (_) {
    } finally {
      _isSettingZoom = false;
    }
  }

  Future<void> setZoomLevel(
    double zoomLevel, [
    void Function(double)? onZoomChanged,
  ]) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      double zoom = zoomLevel.clamp(minZoomLevel, maxZoomLevel);
      await controller.setZoomLevel(zoom);
      if (onZoomChanged != null) onZoomChanged(zoom);
    } catch (_) {}
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
    final double dy = (scanWindow.center.dy / screenSize.height).clamp(
      0.0,
      1.0,
    );
    await focusOnPoint(Offset(dx, dy));
  }

  bool _isFocusing = false;

  Future<void> focusOnPoint(Offset? normalizedOffset) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isFocusing)
      return;

    _isFocusing = true;
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
    } catch (_) {
    } finally {
      _isFocusing = false;
    }
  }

  void cancelZoomTimer() {
    _zoomTimer?.cancel();
  }

  bool _isTorchOn = false;
  bool get isTorchOn => _isTorchOn;

  /// Toggles flash mode (torch on/off). Returns updated torch state.
  Future<bool> toggleTorch() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return false;

    try {
      _isTorchOn = !_isTorchOn;
      await controller.setFlashMode(
        _isTorchOn ? FlashMode.torch : FlashMode.off,
      );
    } catch (_) {
      _isTorchOn = false;
    }
    return _isTorchOn;
  }
}
