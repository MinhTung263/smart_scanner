import 'dart:io';
import 'dart:math' show Point;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

class BarcodeScannerService {
  BarcodeScanner? _barcodeScanner;

  BarcodeScannerService({List<BarcodeFormat> formats = const [BarcodeFormat.all]}) {
    _barcodeScanner = BarcodeScanner(formats: formats);
  }

  /// Restricting formats lets ML Kit skip decoders for formats we don't need,
  /// which speeds up detection per frame (verified against the plugin's native
  /// Android BarcodeScannerOptions.setBarcodeFormats call).
  Future<void> updateFormats(List<BarcodeFormat> formats) async {
    final oldScanner = _barcodeScanner;
    _barcodeScanner = BarcodeScanner(formats: formats);
    await oldScanner?.close();
  }

  Future<void> close() async {
    await _barcodeScanner?.close();
    _barcodeScanner = null;
  }

  /// Converts CameraImage to InputImage for ML Kit
  Uint8List? _reusableBuffer;

  /// Stretches a low-contrast Y-plane (luma) toward the full black/white range
  /// so ML Kit has more signal to work with on small or washed-out barcodes.
  /// Skipped when the frame already has decent contrast, to avoid the extra
  /// pass on every frame.
  void _applyAdaptiveContrastStretch(Uint8List nv21Bytes, int yPlaneLength) {
    int lo = 255;
    int hi = 0;
    for (int i = 0; i < yPlaneLength; i++) {
      final int v = nv21Bytes[i];
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }

    final int range = hi - lo;
    if (range <= 0 || range >= 180) return;

    final double scale = 255.0 / range;
    for (int i = 0; i < yPlaneLength; i++) {
      final int stretched = ((nv21Bytes[i] - lo) * scale).round();
      nv21Bytes[i] = stretched < 0 ? 0 : (stretched > 255 ? 255 : stretched);
    }
  }

  // --- Camera motion detection (for refocus-on-settle and the adaptive
  // frame-rate throttle in CustomBarcodeScannerState) ---
  Uint8List? _motionSampleBuffer;
  int _quietFrameStreak = 0;
  bool _armedForRefocus = false;
  bool _justSettled = false;
  bool _isMoving = true; // safe default (assume active) until first check runs

  static const int _motionSampleStep = 61; // sparse sampling keeps this cheap
  static const int _motionStillThreshold = 6; // avg per-sample luma delta
  static const int _quietFramesToSettle = 6; // consecutive quiet frames required

  /// Compares a sparse sample of the Y-plane against the previous frame to
  /// detect physical camera motion. [justSettled] is true exactly once, on
  /// the frame where the camera is judged to have just settled after being
  /// in motion, so the caller can trigger a fresh autofocus while the phone
  /// is held steady over a barcode. [isMoving] reflects the current frame
  /// and feeds the adaptive throttle (stay fast while the phone is being
  /// panned around looking for a code, back off once it's been still with
  /// nothing found for a while).
  ({bool isMoving, bool justSettled}) _checkMotion(Uint8List nv21Bytes, int yPlaneLength) {
    final int sampleCount = yPlaneLength ~/ _motionSampleStep;
    if (sampleCount < 2) return (isMoving: true, justSettled: false);

    if (_motionSampleBuffer == null || _motionSampleBuffer!.length != sampleCount) {
      _motionSampleBuffer = Uint8List(sampleCount);
      for (int i = 0; i < sampleCount; i++) {
        _motionSampleBuffer![i] = nv21Bytes[i * _motionSampleStep];
      }
      _quietFrameStreak = 0;
      _armedForRefocus = true;
      return (isMoving: true, justSettled: false);
    }

    int totalDelta = 0;
    for (int i = 0; i < sampleCount; i++) {
      final int idx = i * _motionSampleStep;
      final int current = nv21Bytes[idx];
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
  ({int cropLeft, int cropTop, int cropWidth, int cropHeight, Offset mlkitOffset})?
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
    final double mlkitWidth = isPortrait ? previewSize.height : previewSize.width;
    final double mlkitHeight = isPortrait ? previewSize.width : previewSize.height;

    final double scale = screenSize.width / mlkitWidth > screenSize.height / mlkitHeight
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
    if (_reusableCropBuffer == null || _reusableCropBuffer!.length != cropSize) {
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
      final int srcRowStart = srcUvOffset + (uvCropTop + row) * srcWidth + cropLeft;
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
          .map((p) => Point<int>(
                (p.x + offset.dx).round(),
                (p.y + offset.dy).round(),
              ))
          .toList(),
    );
  }

  InputImage? _inputImageFromCameraImage(
    CameraImage image,
    CameraDescription camera, {
    Rect? scanWindow,
    Size? screenSize,
  }) {
    final sensorOrientation = camera.sensorOrientation;
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation = 0;
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation = (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    
    if (rotation == null) return null;
    if (image.planes.isEmpty) return null;

    final format = Platform.isIOS ? InputImageFormat.bgra8888 : InputImageFormat.nv21;

    final Uint8List bytes;
    if (Platform.isIOS) {
      // Zero-copy optimization for iOS (BGRA8888)
      bytes = image.planes.first.bytes;
    } else {
      // Android Zero-Allocation Optimization:
      // Reuse _reusableBuffer to prevent Garbage Collection (GC) churn and device lag.
      final int width = image.width;
      final int height = image.height;
      final int nv21Size = (width * height * 1.5).toInt();
      
      if (_reusableBuffer == null || _reusableBuffer!.length != nv21Size) {
        _reusableBuffer = Uint8List(nv21Size);
      }
      final Uint8List nv21Bytes = _reusableBuffer!;
      
      final Plane yPlane = image.planes[0];
      final int bytesPerRow = yPlane.bytesPerRow;
      
      if (bytesPerRow == width) {
        // Fast path: Y plane is already tightly packed
        nv21Bytes.setRange(0, width * height, yPlane.bytes);
      } else {
        // Slow path: Strip row padding by copying row by row
        for (int y = 0; y < height; y++) {
          nv21Bytes.setRange(y * width, (y + 1) * width, yPlane.bytes, y * bytesPerRow);
        }
      }

      // Check motion on the raw luma before contrast-stretching it, since the
      // stretch factor varies frame to frame and would add noise to the delta.
      final motion = _checkMotion(nv21Bytes, width * height);
      _isMoving = motion.isMoving;
      _justSettled = motion.justSettled;

      _applyAdaptiveContrastStretch(nv21Bytes, width * height);

      // Pack UV planes if present
      if (image.planes.length >= 2) {
        final Plane uvPlane = image.planes[1];
        final int uvBytesPerRow = uvPlane.bytesPerRow;
        final int uvOffset = width * height;

        if (image.planes.length == 2) {
          // NV21 format with 2 planes (Plane 0: Y, Plane 1: VU)
          if (uvBytesPerRow == width) {
            final int copyLen = (uvPlane.bytes.length).clamp(0, nv21Size - uvOffset);
            nv21Bytes.setRange(uvOffset, uvOffset + copyLen, uvPlane.bytes);
          } else {
            final int uvHeight = height ~/ 2;
            for (int y = 0; y < uvHeight; y++) {
              final int srcStart = y * uvBytesPerRow;
              final int dstStart = uvOffset + y * width;
              if (srcStart < uvPlane.bytes.length) {
                final int copyLen = (width).clamp(0, uvPlane.bytes.length - srcStart);
                if (dstStart + copyLen <= nv21Size) {
                  nv21Bytes.setRange(dstStart, dstStart + copyLen, uvPlane.bytes, srcStart);
                }
              }
            }
          }
        } else if (image.planes.length >= 3) {
          // YUV_420_888 with 3 planes (Y, U, V) -> interleave V and U into NV21
          final Plane uPlane = image.planes[1];
          final Plane vPlane = image.planes[2];
          final int uRowStride = uPlane.bytesPerRow;
          final int vRowStride = vPlane.bytesPerRow;
          final int uPixelStride = uPlane.bytesPerPixel ?? 1;
          final int vPixelStride = vPlane.bytesPerPixel ?? 1;

          int dstIdx = uvOffset;
          final int uvHeight = height ~/ 2;
          final int uvWidth = width ~/ 2;

          for (int y = 0; y < uvHeight; y++) {
            for (int x = 0; x < uvWidth; x++) {
              final int uIdx = y * uRowStride + x * uPixelStride;
              final int vIdx = y * vRowStride + x * vPixelStride;

              if (vIdx < vPlane.bytes.length && uIdx < uPlane.bytes.length && dstIdx + 1 < nv21Size) {
                nv21Bytes[dstIdx++] = vPlane.bytes[vIdx];
                nv21Bytes[dstIdx++] = uPlane.bytes[uIdx];
              }
            }
          }
        }
      } else {
        // Fallback: fill UV planes with 128 (neutral chroma) for 1D barcode contrast
        nv21Bytes.fillRange(width * height, nv21Size, 128);
      }

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
              size: Size(cropRegion.cropWidth.toDouble(), cropRegion.cropHeight.toDouble()),
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

  /// Process the image and return the recognized barcodes, plus motion state
  /// (Android only; both flags default to "active" on iOS's zero-copy path
  /// since it skips the Y-plane sampling below):
  /// - [justSettled] is true exactly once, when the camera just stopped
  ///   moving after being panned around.
  /// - [isMoving] reflects the current frame, for callers that want to slow
  ///   down frame processing while the camera is idle and speed back up the
  ///   moment it's picked up again.
  ///
  /// [scanWindow] and [screenSize], when provided, let this crop the frame
  /// down to roughly the visible scan window before decoding (Android only;
  /// see _computeCropRegion). Returned barcodes are always translated back to
  /// full-frame-relative coordinates, so callers don't need to know whether
  /// cropping happened.
  Future<(List<Barcode> barcodes, bool justSettled, bool isMoving)> processCameraImage(
    CameraImage image,
    CameraDescription camera, {
    Rect? scanWindow,
    Size? screenSize,
  }) async {
    if (_barcodeScanner == null) return (<Barcode>[], false, true);

    _justSettled = false;
    _isMoving = true;
    final inputImage = _inputImageFromCameraImage(
      image,
      camera,
      scanWindow: scanWindow,
      screenSize: screenSize,
    );
    final justSettled = _justSettled;
    final isMoving = _isMoving;
    final cropOffset = _lastCropOffset;
    if (inputImage == null) return (<Barcode>[], justSettled, isMoving);

    try {
      final results = await _barcodeScanner!.processImage(inputImage);
      final translated = cropOffset == null
          ? results
          : results.map((b) => _translateBarcode(b, cropOffset)).toList();
      return (translated, justSettled, isMoving);
    } catch (e) {
      debugPrint('Error scanning barcodes: $e');
      return (<Barcode>[], justSettled, isMoving);
    }
  }

  /// Maps raw ML Kit bounding box coordinates to Screen coordinates with proper Android 90deg rotation transform
  static Rect mapMlKitRectToScreen({
    required Rect rawRect,
    required Size previewSize, // raw preview size e.g. 1920x1080
    required Size screenSize,
  }) {
    final bool isPortrait = screenSize.height > screenSize.width;

    final double mlkitWidth = isPortrait ? previewSize.height : previewSize.width;
    final double mlkitHeight = isPortrait ? previewSize.width : previewSize.height;

    final double scale = screenSize.width / mlkitWidth > screenSize.height / mlkitHeight
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

        return !effectiveScanWindow.contains(mappedRect.center);
      });
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

      final aDist = (aRect.center.dx - center.dx) * (aRect.center.dx - center.dx) +
          (aRect.center.dy - center.dy) * (aRect.center.dy - center.dy);
      final bDist = (bRect.center.dx - center.dx) * (bRect.center.dx - center.dx) +
          (bRect.center.dy - center.dy) * (bRect.center.dy - center.dy);

      return aDist.compareTo(bDist);
    });

    return barcodes;
  }
}
