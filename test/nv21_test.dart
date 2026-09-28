import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scanner/src/data/services/barcode_scanner_service.dart';

CameraImage frame(
  int width,
  int height,
  List<CameraImagePlane> planes, {
  ImageFormatGroup group = ImageFormatGroup.nv21,
}) {
  return CameraImage.fromPlatformInterface(
    CameraImageData(
      format: CameraImageFormat(group, raw: 17),
      width: width,
      height: height,
      planes: planes,
    ),
  );
}

void main() {
  // 4x2 frame: 8 luma bytes + 4 interleaved VU bytes.
  final nv21 = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 90, 80, 91, 81]);

  test('a packed NV21 frame from the plugin is passed through as-is', () {
    final image = frame(4, 2, [CameraImagePlane(bytes: nv21, bytesPerRow: 4)]);
    final out = cameraImageToNv21(image)!;
    expect(identical(out.bytes, image.planes.first.bytes), isTrue);
    expect(out.repacked, isFalse);
  });

  test(
    'trailing bytes (padded Y plane upstream) are trimmed without copying',
    () {
      final withTail = Uint8List.fromList([...nv21, 0, 0, 0, 0]);
      final image = frame(4, 2, [
        CameraImagePlane(bytes: withTail, bytesPerRow: 4),
      ]);
      final out = cameraImageToNv21(image)!;
      expect(out.bytes, nv21);
      expect(out.repacked, isFalse);
      // Same memory as the camera's buffer, not a copy.
      withTail[0] = 42;
      expect(out.bytes[0], 42);
    },
  );

  test('YUV_420_888 planes with row padding and pixel stride are repacked', () {
    final image = frame(4, 2, group: ImageFormatGroup.yuv420, [
      // Y rows padded to a stride of 6; the last row isn't padded.
      CameraImagePlane(
        bytes: Uint8List.fromList([1, 2, 3, 4, 0, 0, 5, 6, 7, 8]),
        bytesPerRow: 6,
        bytesPerPixel: 1,
      ),
      // U and V: one chroma row of 2 samples at pixel stride 2.
      CameraImagePlane(
        bytes: Uint8List.fromList([80, 0, 81]),
        bytesPerRow: 4,
        bytesPerPixel: 2,
      ),
      CameraImagePlane(
        bytes: Uint8List.fromList([90, 0, 91]),
        bytesPerRow: 4,
        bytesPerPixel: 2,
      ),
    ]);
    final out = cameraImageToNv21(image)!;
    expect(out.bytes, nv21);
    expect(out.repacked, isTrue);
  });

  test('a repacked frame reuses a scratch buffer of the right size', () {
    final scratch = Uint8List(12);
    final image = frame(4, 2, [
      CameraImagePlane(
        bytes: Uint8List.fromList([
          1,
          2,
          3,
          4,
          0,
          0,
          5,
          6,
          7,
          8,
          0,
          0,
          90,
          80,
          91,
          81,
        ]),
        bytesPerRow: 6,
      ),
    ]);
    final out = cameraImageToNv21(image, scratch: scratch)!;
    expect(identical(out.bytes, scratch), isTrue);
    expect(out.bytes, nv21);
  });

  test('frames that cannot be NV21 are rejected', () {
    final odd = frame(3, 2, [
      CameraImagePlane(bytes: Uint8List(9), bytesPerRow: 3),
    ]);
    expect(cameraImageToNv21(odd), isNull);
  });
}
