import 'dart:io';
import 'nv21_converter.dart';
import 'dart:math' show Point, max;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

class BarcodeScannerService {
  BarcodeScanner? _barcodeScanner;

  BarcodeScannerService({
    List<BarcodeFormat> formats = const [BarcodeFormat.all],
  }) {
    _barcodeScanner = BarcodeScanner(formats: formats);
  }

  /// Restricting formats lets ML Kit skip decoders for formats we don't need,
  /// which speeds up detection per frame (verified against the plugin's native
  /// Android BarcodeScannerOptions.setBarcodeFormats call).
  Future<void> updateFormats(List<BarcodeFormat> formats) async {
    _pendingFormats = List.of(formats);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _processing;
    } finally {
      try {
        await _converter.close();
      } finally {
        await _barcodeScanner?.close();
        _barcodeScanner = null;
      }
    }
  }

  final Nv21Converter _converter = Nv21Converter();
  final Stopwatch _clock = Stopwatch()..start();
  int _lastContrastAttemptMs = 0;
  int _missedFrames = 0;
  bool _closed = false;
  Future<(List<Barcode>, bool, bool, bool, bool)>? _processing;
  List<BarcodeFormat>? _pendingFormats;

  // --- Camera motion detection (for refocus-on-settle and the adaptive
  // frame-rate throttle in CustomBarcodeScannerState) ---
  Uint8List? _motionSampleBuffer;
  int _quietFrameStreak = 0;
  bool _armedForRefocus = false;
  bool _justSettled = false;
  bool _isMoving = true; // safe default (assume active) until first check runs
  bool _isBlurry = false; // safe default (assume sharp) until first check runs
  bool _hasGlare =
      false; // safe default (assume no glare) until first check runs

  static const int _motionSampleStep = 61; // sparse sampling keeps this cheap
  static const int _motionStillThreshold = 6; // avg per-sample luma delta
  static const int _quietFramesToSettle =
      6; // consecutive quiet frames required

  /// Compares a sparse sample of the Y-plane against the previous frame to
  /// detect physical camera motion. [justSettled] is true exactly once, on
  /// the frame where the camera is judged to have just settled after being
  /// in motion, so the caller can trigger a fresh autofocus while the phone
  /// is held steady over a barcode. [isMoving] reflects the current frame
  /// and feeds the adaptive throttle (stay fast while the phone is being
  /// panned around looking for a code, back off once it's been still with
  /// nothing found for a while).
  ({bool isMoving, bool justSettled}) _checkMotion(
    Uint8List bytes,
    int width,
    int height, {
    int pixelStride = 1,
    int bytesPerRow = 0,
  }) {
    final int effectiveBytesPerRow = bytesPerRow > 0
        ? bytesPerRow
        : width * pixelStride;
    final int yPlaneLength = width * height;
    final int sampleStep = max(_motionSampleStep, yPlaneLength ~/ 2048);
    final int sampleCount = yPlaneLength ~/ sampleStep;
    if (sampleCount < 2) return (isMoving: true, justSettled: false);

    if (_motionSampleBuffer == null ||
        _motionSampleBuffer!.length != sampleCount) {
      _motionSampleBuffer = Uint8List(sampleCount);
      for (int i = 0; i < sampleCount; i++) {
        final int sampleIdx = i * sampleStep;
        final int x = sampleIdx % width;
        final int y = sampleIdx ~/ width;
        final int byteIdx = y * effectiveBytesPerRow + x * pixelStride;
        _motionSampleBuffer![i] = bytes[byteIdx];
      }
      _quietFrameStreak = 0;
      _armedForRefocus = true;
      return (isMoving: true, justSettled: false);
    }

    int totalDelta = 0;
    for (int i = 0; i < sampleCount; i++) {
      final int sampleIdx = i * sampleStep;
      final int x = sampleIdx % width;
      final int y = sampleIdx ~/ width;
      final int byteIdx = y * effectiveBytesPerRow + x * pixelStride;
      final int current = bytes[byteIdx];
      totalDelta += (current - _motionSampleBuffer![i]).abs();
      _motionSampleBuffer![i] = current;
    }
    final double avgDelta = totalDelta / sampleCount;

    if (avgDelta > _motionStillThreshold) {
      // Still moving: reset the streak and arm a refocus for once it settles.
      _quietFrameStreak = 0;
      _armedForRefocus = true;
      return (isMoving: true, justSettled: false);
    }

    if (!_armedForRefocus) return (isMoving: false, justSettled: false);

    _quietFrameStreak++;
    if (_quietFrameStreak >= _quietFramesToSettle) {
      _armedForRefocus = false;
      _quietFrameStreak = 0;
      return (isMoving: false, justSettled: true);
    }
    return (isMoving: false, justSettled: false);
  }

  // --- Sharpness estimation (for the "you're too close, back away a bit"
  // hint — the phone's lens has a minimum focus distance no amount of
  // autofocus retriggering can overcome once crossed). ---
  static const int _sharpnessSampleStride =
      47; // sparse sampling keeps this cheap
  static const int _sharpnessGap =
      3; // pixel gap used to measure a local gradient
  static const double _blurySharpnessThreshold =
      5.0; // avg local gradient below this ~= blurry

  /// Average local horizontal gradient over a sparse grid of the Y-plane, as
  /// a cheap proxy for "how much crisp edge detail is in this frame". Sharp,
  /// in-focus frames have strong edges (high value); blurry ones are soft
  /// (low value). Stays within each row so the gradient reflects real
  /// neighboring pixels instead of an accidental wrap to the next scanline.
  bool _estimateIsBlurry(
    Uint8List bytes,
    int width,
    int height, {
    int pixelStride = 1,
    int bytesPerRow = 0,
  }) {
    final int effectiveBytesPerRow = bytesPerRow > 0
        ? bytesPerRow
        : width * pixelStride;
    final int yPlaneLength = width * height;
    int totalGradient = 0;
    int samples = 0;

    final sampleStep = max(_sharpnessSampleStride, yPlaneLength ~/ 2048);
    for (int i = 0; i + _sharpnessGap < yPlaneLength; i += sampleStep) {
      final int col = i % width;
      if (col + _sharpnessGap >= width) continue;
      final int row = i ~/ width;
      final int idx1 = row * effectiveBytesPerRow + col * pixelStride;
      final int idx2 =
          row * effectiveBytesPerRow + (col + _sharpnessGap) * pixelStride;
      totalGradient += (bytes[idx1] - bytes[idx2]).abs();
      samples++;
    }

    if (samples == 0) return false; // not enough data — don't false-flag blur
    final double avgGradient = totalGradient / samples;
    return avgGradient < _blurySharpnessThreshold;
  }

  // --- Glare estimation (backing away or changing angle reduces a specular
  // reflection's share of the frame and often clears it entirely — same
  // "back away" remedy as the blur hint, different cause). ---
  static const int _glareSampleStep =
      5; // denser than motion/sharpness sampling: glare can be a small hotspot
  static const int _glareBrightThreshold = 248; // near-saturated luma
  static const double _glareAreaRatio =
      0.035; // >3.5% of sampled pixels blown out ~= meaningful glare

  /// Fraction of a sparse sample of the Y-plane that's blown-out bright, as a
  /// cheap proxy for "is there a specular reflection hot enough to wash out
  /// part of the frame". A glare edge is still a sharp edge, so this needs to
  /// be checked independently of the blur/sharpness estimate above — a glared
  /// frame can look perfectly "sharp" by that metric while still failing to
  /// decode.
  bool _estimateHasGlare(
    Uint8List bytes,
    int width,
    int height, {
    int pixelStride = 1,
    int bytesPerRow = 0,
  }) {
    final int effectiveBytesPerRow = bytesPerRow > 0
        ? bytesPerRow
        : width * pixelStride;
    final int yPlaneLength = width * height;
    final sampleStep = max(_glareSampleStep, yPlaneLength ~/ 2048);
    final int sampleCount = (yPlaneLength + sampleStep - 1) ~/ sampleStep;
    if (sampleCount == 0) return false;

    int brightCount = 0;
    for (int i = 0; i < yPlaneLength; i += sampleStep) {
      final int x = i % width;
      final int y = i ~/ width;
      final int idx = y * effectiveBytesPerRow + x * pixelStride;
      if (bytes[idx] >= _glareBrightThreshold) brightCount++;
    }

    return (brightCount / sampleCount) > _glareAreaRatio;
  }

  // --- Crop-to-scan-window (Android/NV21 only) ---
  // Feeding ML Kit only the (padded) visible scan window instead of the full
  // frame both cuts decode time (less data) and effectively magnifies small
  // barcodes within the analyzed region. This only handles the back-camera,
  // 90deg/270deg sensor rotation cases — the only ones this portrait-only
  // scanner UI targets and the only ones verified against the existing
  // screen-mapping code in this file. Any other case safely falls back to
  // processing the full, uncropped frame.
  Uint8List? _reusableCropBuffer;
  Offset? _lastCropOffset;

  /// Computes the raw NV21 pixel bounds to crop to, plus the offset (in the
  /// full frame's ML-Kit/rotated coordinate space) that must be added back to
  /// whatever ML Kit returns for the cropped image, so all downstream code
  /// keeps working with full-frame-relative coordinates unaware cropping ever
  /// happened.
  ({
    int cropLeft,
    int cropTop,
    int cropWidth,
    int cropHeight,
    Offset mlkitOffset,
  })?
  _computeCropRegion({
    required Rect scanWindow,
    required Size screenSize,
    required Size previewSize,
    required InputImageRotation rotation,
    required CameraLensDirection lensDirection,
  }) {
    if (lensDirection != CameraLensDirection.back) return null;
    if (rotation != InputImageRotation.rotation90deg &&
        rotation != InputImageRotation.rotation270deg) {
      return null;
    }
    if (screenSize.width <= 0 || screenSize.height <= 0) return null;

    final bool isPortrait = screenSize.height > screenSize.width;
    final double mlkitWidth = isPortrait
        ? previewSize.height
        : previewSize.width;
    final double mlkitHeight = isPortrait
        ? previewSize.width
        : previewSize.height;

    final double scale =
        screenSize.width / mlkitWidth > screenSize.height / mlkitHeight
        ? screenSize.width / mlkitWidth
        : screenSize.height / mlkitHeight;
    final double scaledWidth = mlkitWidth * scale;
    final double scaledHeight = mlkitHeight * scale;
    final double offsetX = (scaledWidth - screenSize.width) / 2;
    final double offsetY = (scaledHeight - screenSize.height) / 2;

    // Inverse of mapMlKitRectToScreen: screen space -> ML-Kit/rotated space.
    double mlLeft = (scanWindow.left + offsetX) / scale;
    double mlTop = (scanWindow.top + offsetY) / scale;
    double mlRight = (scanWindow.right + offsetX) / scale;
    double mlBottom = (scanWindow.bottom + offsetY) / scale;

    // Generous padding so minor imprecision or a code peeking past the
    // window edge doesn't get clipped out of the analyzed region.
    final double padX = (mlRight - mlLeft) * 0.3;
    final double padY = (mlBottom - mlTop) * 0.3;
    mlLeft = (mlLeft - padX).clamp(0.0, mlkitWidth);
    mlTop = (mlTop - padY).clamp(0.0, mlkitHeight);
    mlRight = (mlRight + padX).clamp(0.0, mlkitWidth);
    mlBottom = (mlBottom + padY).clamp(0.0, mlkitHeight);

    if (mlRight - mlLeft < 20 || mlBottom - mlTop < 20) return null;

    final double rawW = previewSize.width;
    final double rawH = previewSize.height;

    // Convert the ML-Kit/rotated-space rect into raw sensor-space pixel
    // bounds, inverting whichever 90deg rotation ML Kit was told to apply.
    double rawLeft, rawTop, rawRight, rawBottom;
    if (rotation == InputImageRotation.rotation90deg) {
      // Forward: rotated = (H-1-raw.y, raw.x). Inverse: raw.x = rotated.y; raw.y = H-1-rotated.x.
      rawLeft = mlTop;
      rawRight = mlBottom;
      rawTop = rawH - mlRight;
      rawBottom = rawH - mlLeft;
    } else {
      // rotation270deg. Forward: rotated = (raw.y, W-1-raw.x). Inverse: raw.x = W-1-rotated.y; raw.y = rotated.x.
      rawLeft = rawW - mlBottom;
      rawRight = rawW - mlTop;
      rawTop = mlLeft;
      rawBottom = mlRight;
    }

    int cropLeft = rawLeft.floor();
    int cropTop = rawTop.floor();
    int cropRight = rawRight.ceil();
    int cropBottom = rawBottom.ceil();

    // Even alignment, required for NV21 4:2:0 chroma subsampling.
    cropLeft -= cropLeft % 2;
    cropTop -= cropTop % 2;
    cropRight += cropRight % 2;
    cropBottom += cropBottom % 2;

    cropLeft = cropLeft.clamp(0, rawW.toInt());
    cropTop = cropTop.clamp(0, rawH.toInt());
    cropRight = cropRight.clamp(0, rawW.toInt());
    cropBottom = cropBottom.clamp(0, rawH.toInt());

    final int cropWidth = cropRight - cropLeft;
    final int cropHeight = cropBottom - cropTop;
    if (cropWidth < 16 || cropHeight < 16) return null;

    // Re-derive the ML-Kit-space offset from the FINAL (rounded/clamped) raw
    // crop bounds, via the forward rotation, so the translate-back step is
    // exactly consistent with the bytes actually sliced out below.
    final Offset mlkitOffset = rotation == InputImageRotation.rotation90deg
        ? Offset(rawH - cropBottom, cropLeft.toDouble())
        : Offset(cropTop.toDouble(), rawW - cropRight);

    return (
      cropLeft: cropLeft,
      cropTop: cropTop,
      cropWidth: cropWidth,
      cropHeight: cropHeight,
      mlkitOffset: mlkitOffset,
    );
  }

  /// Slices a rectangular region out of a full-frame NV21 buffer into a
  /// reusable smaller buffer (Y plane + interleaved VU plane).
  Uint8List _cropNv21(
    Uint8List src,
    int srcWidth,
    int srcHeight,
    int cropLeft,
    int cropTop,
    int cropWidth,
    int cropHeight,
  ) {
    final int cropSize = (cropWidth * cropHeight * 1.5).toInt();
    if (_reusableCropBuffer == null ||
        _reusableCropBuffer!.length != cropSize) {
      _reusableCropBuffer = Uint8List(cropSize);
    }
    final Uint8List dst = _reusableCropBuffer!;

    for (int row = 0; row < cropHeight; row++) {
      final int srcRowStart = (cropTop + row) * srcWidth + cropLeft;
      final int dstRowStart = row * cropWidth;
      dst.setRange(dstRowStart, dstRowStart + cropWidth, src, srcRowStart);
    }

    final int srcUvOffset = srcWidth * srcHeight;
    final int dstUvOffset = cropWidth * cropHeight;
    final int uvCropTop = cropTop ~/ 2;
    final int uvRows = cropHeight ~/ 2;
    for (int row = 0; row < uvRows; row++) {
      final int srcRowStart =
          srcUvOffset + (uvCropTop + row) * srcWidth + cropLeft;
      final int dstRowStart = dstUvOffset + row * cropWidth;
      dst.setRange(dstRowStart, dstRowStart + cropWidth, src, srcRowStart);
    }

    return dst;
  }

  /// Shifts a barcode's bounding box and corner points by [offset], to
  /// translate coordinates from a cropped image back into full-frame space.
  Barcode _translateBarcode(Barcode b, Offset offset) {
    return Barcode(
      type: b.type,
      format: b.format,
      value: b.value,
      displayValue: b.displayValue,
      rawValue: b.rawValue,
      rawBytes: b.rawBytes,
      boundingBox: b.boundingBox.shift(offset),
      cornerPoints: b.cornerPoints
          .map(
            (p) => Point<int>(
              (p.x + offset.dx).round(),
              (p.y + offset.dy).round(),
            ),
          )
          .toList(),
    );
  }

  Future<InputImage?> _inputImageFromCameraImage(
    CameraImage image,
    CameraDescription camera, {
    Rect? scanWindow,
    Size? screenSize,
  }) async {
    _lastCropOffset = null;
    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation = 0;
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation =
            (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }

    if (rotation == null) return null;
    if (image.planes.isEmpty) return null;

    final format = Platform.isIOS
        ? InputImageFormat.bgra8888
        : InputImageFormat.nv21;

    final Uint8List bytes;
    if (Platform.isIOS) {
      // Zero-copy optimization for iOS (BGRA8888)
      final plane0 = image.planes.first;
      bytes = plane0.bytes;
      final int pixelStride = plane0.bytesPerPixel ?? 4;
      final int bytesPerRow = plane0.bytesPerRow;

      final motion = _checkMotion(
        bytes,
        image.width,
        image.height,
        pixelStride: pixelStride > 0 ? pixelStride : 4,
        bytesPerRow: bytesPerRow,
      );
      _isMoving = motion.isMoving;
      _justSettled = motion.justSettled;
      _isBlurry = _estimateIsBlurry(
        bytes,
        image.width,
        image.height,
        pixelStride: pixelStride > 0 ? pixelStride : 4,
        bytesPerRow: bytesPerRow,
      );
      _hasGlare = _estimateHasGlare(
        bytes,
        image.width,
        image.height,
        pixelStride: pixelStride > 0 ? pixelStride : 4,
        bytesPerRow: bytesPerRow,
      );
    } else {
      final width = image.width;
      final height = image.height;
      // Try the unmodified image first. Contrast recovery is an occasional
      // fallback after misses, performed off the UI isolate.
      final now = _clock.elapsedMilliseconds;
      final enhance = _missedFrames >= 3 && now - _lastContrastAttemptMs >= 800;
      if (enhance) _lastContrastAttemptMs = now;
      final nv21Bytes = await _converter.convert(
        image,
        enhanceContrast: enhance,
      );
      // Use raw luma for diagnostics so contrast changes don't look like motion.
      final luma = image.planes.first;
      final motion = _checkMotion(
        luma.bytes,
        width,
        height,
        bytesPerRow: luma.bytesPerRow,
      );
      _isMoving = motion.isMoving;
      _justSettled = motion.justSettled;
      _isBlurry = _estimateIsBlurry(
        luma.bytes,
        width,
        height,
        bytesPerRow: luma.bytesPerRow,
      );
      _hasGlare = _estimateHasGlare(
        luma.bytes,
        width,
        height,
        bytesPerRow: luma.bytesPerRow,
      );

      // Try to crop down to (a padded margin around) the visible scan window
      // before handing frames to ML Kit — see _computeCropRegion for why.
      _lastCropOffset = null;
      if (scanWindow != null && screenSize != null) {
        final cropRegion = _computeCropRegion(
          scanWindow: scanWindow,
          screenSize: screenSize,
          previewSize: Size(width.toDouble(), height.toDouble()),
          rotation: rotation,
          lensDirection: camera.lensDirection,
        );
        if (cropRegion != null) {
          final croppedBytes = _cropNv21(
            nv21Bytes,
            width,
            height,
            cropRegion.cropLeft,
            cropRegion.cropTop,
            cropRegion.cropWidth,
            cropRegion.cropHeight,
          );
          _lastCropOffset = cropRegion.mlkitOffset;
          return InputImage.fromBytes(
            bytes: croppedBytes,
            metadata: InputImageMetadata(
              size: Size(
                cropRegion.cropWidth.toDouble(),
                cropRegion.cropHeight.toDouble(),
              ),
              rotation: rotation,
              format: format,
              bytesPerRow: cropRegion.cropWidth,
            ),
          );
        }
      }

      bytes = nv21Bytes;
    }

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: Platform.isIOS ? image.planes[0].bytesPerRow : image.width,
      ),
    );
  }

  /// Process the image and return the recognized barcodes, plus motion state:
  /// - [justSettled] is true exactly once, when the camera just stopped
  ///   moving after being panned around.
  /// - [isMoving] reflects the current frame, for callers that want to slow
  ///   down frame processing while the camera is idle and speed back up the
  ///   moment it's picked up again.
  /// - [isBlurry] reflects the current frame's sharpness, so callers can hint
  ///   the user to back away once they're closer than the lens's minimum
  ///   focus distance (a hardware limit no amount of autofocus retriggering
  ///   can overcome).
  /// - [hasGlare] reflects a bright specular reflection washing out part of
  ///   the frame — a different failure mode than blur (a glare edge is still
  ///   a sharp edge), but the same remedy applies: backing away or changing
  ///   the scan angle reduces or clears it.
  ///
  /// [scanWindow] and [screenSize], when provided, let this crop the frame
  /// down to roughly the visible scan window before decoding (Android only;
  /// see _computeCropRegion). Returned barcodes are always translated back to
  /// full-frame-relative coordinates, so callers don't need to know whether
  /// cropping happened.
  Future<
    (
      List<Barcode> barcodes,
      bool justSettled,
      bool isMoving,
      bool isBlurry,
      bool hasGlare,
    )
  >
  processCameraImage(
    CameraImage image,
    CameraDescription camera, {
    Rect? scanWindow,
    Size? screenSize,
  }) async {
    if (_closed || _processing != null)
      return (<Barcode>[], false, true, false, false);
    try {
      final future = _processCameraImage(
        image,
        camera,
        scanWindow: scanWindow,
        screenSize: screenSize,
      );
      _processing = future;
      return await future;
    } finally {
      _processing = null;
    }
  }

  Future<(List<Barcode>, bool, bool, bool, bool)> _processCameraImage(
    CameraImage image,
    CameraDescription camera, {
    Rect? scanWindow,
    Size? screenSize,
  }) async {
    final formats = _pendingFormats;
    if (formats != null) {
      _pendingFormats = null;
      await _barcodeScanner?.close();
      _barcodeScanner = BarcodeScanner(formats: formats);
    }
    if (_closed || _barcodeScanner == null)
      return (<Barcode>[], false, true, false, false);

    _justSettled = false;
    _isMoving = true;
    _isBlurry = false;
    _hasGlare = false;
    final inputImage = await _inputImageFromCameraImage(
      image,
      camera,
      scanWindow: scanWindow,
      screenSize: screenSize,
    );
    final justSettled = _justSettled;
    final isMoving = _isMoving;
    final isBlurry = _isBlurry;
    final hasGlare = _hasGlare;
    final cropOffset = _lastCropOffset;
    if (inputImage == null)
      return (<Barcode>[], justSettled, isMoving, isBlurry, hasGlare);

    try {
      if (_closed) return (<Barcode>[], false, true, false, false);
      final results = await _barcodeScanner!.processImage(inputImage);
      _missedFrames = results.isEmpty ? _missedFrames + 1 : 0;
      final translated = cropOffset == null
          ? results
          : results.map((b) => _translateBarcode(b, cropOffset)).toList();
      return (translated, justSettled, isMoving, isBlurry, hasGlare);
    } catch (e) {
      return (<Barcode>[], justSettled, isMoving, isBlurry, hasGlare);
    }
  }

  /// Maps raw ML Kit bounding box coordinates to Screen coordinates with proper Android 90deg rotation transform
  static Rect mapMlKitRectToScreen({
    required Rect rawRect,
    required Size previewSize, // raw preview size e.g. 1920x1080
    required Size screenSize,
  }) {
    final bool isPortrait = screenSize.height > screenSize.width;

    final double mlkitWidth = isPortrait
        ? previewSize.height
        : previewSize.width;
    final double mlkitHeight = isPortrait
        ? previewSize.width
        : previewSize.height;

    final double scale =
        screenSize.width / mlkitWidth > screenSize.height / mlkitHeight
        ? screenSize.width / mlkitWidth
        : screenSize.height / mlkitHeight;

    final double scaledWidth = mlkitWidth * scale;
    final double scaledHeight = mlkitHeight * scale;

    final double offsetX = (scaledWidth - screenSize.width) / 2;
    final double offsetY = (scaledHeight - screenSize.height) / 2;

    return Rect.fromLTRB(
      (rawRect.left * scale) - offsetX,
      (rawRect.top * scale) - offsetY,
      (rawRect.right * scale) - offsetX,
      (rawRect.bottom * scale) - offsetY,
    );
  }

  /// Filters barcodes based on a scan window and sorts them by proximity to the center
  List<Barcode> filterAndSortBarcodes(
    List<Barcode> barcodes,
    Size imageSize, // raw camera image size
    Size previewSize, // raw preview size from camera controller
    Size screenSize,
    Rect? scanWindow,
  ) {
    if (barcodes.isEmpty) return [];

    if (scanWindow != null) {
      // Tolerance scales with the window itself (20% per side) so it never
      // vanishes when the window is pinched down small, while still keeping
      // detection scoped to roughly the visible frame rather than the whole
      // screen. A fixed-pixel tolerance would either be too loose on a large
      // window or too tight (near zero) on a small one.
      final double toleranceX = scanWindow.width * 0.2;
      final double toleranceY = scanWindow.height * 0.2;
      final Rect effectiveScanWindow = Rect.fromLTRB(
        scanWindow.left - toleranceX,
        scanWindow.top - toleranceY,
        scanWindow.right + toleranceX,
        scanWindow.bottom + toleranceY,
      );

      barcodes.removeWhere((barcode) {
        final mappedRect = mapMlKitRectToScreen(
          rawRect: barcode.boundingBox,
          previewSize: previewSize,
          screenSize: screenSize,
        );

        final bool inside = effectiveScanWindow.contains(mappedRect.center);
        return !inside;
      });

      // The 20% padding is meant to forgive imprecision for a single code —
      // but with several codes packed close together (e.g. adjacent barcodes
      // on the same label), that same padding makes it easy to accidentally
      // pick up a neighbor instead of the one actually centered. When more
      // than one candidate survives, re-check against the raw (unpadded)
      // window to disambiguate; only fall back to the padded set if that
      // strict check would eliminate every candidate.
      if (barcodes.length > 1) {
        final strictMatches = barcodes.where((barcode) {
          final mappedRect = mapMlKitRectToScreen(
            rawRect: barcode.boundingBox,
            previewSize: previewSize,
            screenSize: screenSize,
          );
          return scanWindow.contains(mappedRect.center);
        }).toList();

        if (strictMatches.isNotEmpty) {
          barcodes = strictMatches;
        }
      }
    }

    if (barcodes.isEmpty) return [];
    // Only one candidate left after filtering to the scan window; no need to sort.
    if (barcodes.length == 1) return barcodes;

    final center = Offset(screenSize.width / 2, screenSize.height / 2);

    // Sort remaining barcodes by physical distance to the center of the screen
    barcodes.sort((a, b) {
      final aRect = mapMlKitRectToScreen(
        rawRect: a.boundingBox,
        previewSize: previewSize,
        screenSize: screenSize,
      );
      final bRect = mapMlKitRectToScreen(
        rawRect: b.boundingBox,
        previewSize: previewSize,
        screenSize: screenSize,
      );

      final aDist =
          (aRect.center.dx - center.dx) * (aRect.center.dx - center.dx) +
          (aRect.center.dy - center.dy) * (aRect.center.dy - center.dy);
      final bDist =
          (bRect.center.dx - center.dx) * (bRect.center.dx - center.dx) +
          (bRect.center.dy - center.dy) * (bRect.center.dy - center.dy);

      return aDist.compareTo(bDist);
    });

    return barcodes;
  }
}
