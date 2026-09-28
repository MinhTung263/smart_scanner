import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:camera/camera.dart';

/// Reuses one worker for YUV packing and contrast recovery. Only one frame may
/// be in flight; callers drop incoming frames while waiting for a conversion.
class Nv21Converter {
  Isolate? _isolate;
  Future<void>? _starting;
  final ReceivePort _responses = ReceivePort();
  final Completer<SendPort> _requests = Completer<SendPort>();
  Completer<Uint8List>? _pending;
  bool _closed = false;

  Nv21Converter() {
    _responses.listen((message) {
      if (message is SendPort) {
        _requests.complete(message);
      } else if (message is TransferableTypedData) {
        _pending?.complete(message.materialize().asUint8List());
        _pending = null;
      } else {
        _pending?.completeError(StateError('Invalid camera frame: $message'));
        _pending = null;
      }
    });
  }

  Future<void> _start() async {
    _isolate = await Isolate.spawn(_run, _responses.sendPort);
  }

  Future<Uint8List> convert(
    CameraImage image, {
    bool enhanceContrast = false,
  }) async {
    if (_closed) throw StateError('Converter is closed');
    // CameraX can supply an already packed NV21 plane. Preserve its VU data
    // and avoid copying it or starting a worker on the normal decode path.
    if (!enhanceContrast &&
        image.planes.length == 1 &&
        image.planes.first.bytesPerRow == image.width &&
        image.planes.first.bytes.length ==
            image.width * image.height * 3 ~/ 2) {
      return image.planes.first.bytes;
    }
    await (_starting ??= _start());
    if (_closed) throw StateError('Converter is closed');
    final port = await _requests.future;
    if (_pending != null) throw StateError('Conversion already in progress');
    final result = Completer<Uint8List>();
    _pending = result;
    port.send((image, enhanceContrast));
    return result.future;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _starting;
      await _pending?.future;
    } finally {
      _isolate?.kill(priority: Isolate.immediate);
      _responses.close();
    }
  }

  static void _run(SendPort responses) {
    final requests = ReceivePort();
    responses.send(requests.sendPort);
    requests.listen((message) {
      try {
        final (image, enhance) = message as (CameraImage, bool);
        final bytes = packNv21(image, enhanceContrast: enhance);
        responses.send(TransferableTypedData.fromList([bytes]));
      } catch (error) {
        responses.send(error.toString());
      }
    });
  }
}

/// Packs padded YUV420 / NV21 planes. Kept independent of platform channels so
/// conversion can run on the worker and be verified with synthetic frames.
Uint8List packNv21(CameraImage image, {bool enhanceContrast = false}) {
  final width = image.width;
  final height = image.height;
  if (width.isOdd || height.isOdd || image.planes.isEmpty) {
    throw ArgumentError('NV21 requires even dimensions and a luma plane');
  }
  final yLength = width * height;
  final bytes = Uint8List(yLength * 3 ~/ 2);
  final yPlane = image.planes.first;
  for (var row = 0; row < height; row++) {
    bytes.setRange(
      row * width,
      (row + 1) * width,
      yPlane.bytes,
      row * yPlane.bytesPerRow,
    );
  }
  if (image.planes.length == 1) {
    final uvStart = yPlane.bytesPerRow * height;
    if (yPlane.bytes.length >= uvStart + yLength ~/ 2) {
      for (var row = 0; row < height ~/ 2; row++) {
        bytes.setRange(
          yLength + row * width,
          yLength + (row + 1) * width,
          yPlane.bytes,
          uvStart + row * yPlane.bytesPerRow,
        );
      }
    } else {
      bytes.fillRange(yLength, bytes.length, 128);
    }
  } else if (image.planes.length == 2) {
    final vu = image.planes[1];
    for (var row = 0; row < height ~/ 2; row++) {
      bytes.setRange(
        yLength + row * width,
        yLength + (row + 1) * width,
        vu.bytes,
        row * vu.bytesPerRow,
      );
    }
  } else {
    final u = image.planes[1];
    final v = image.planes[2];
    var destination = yLength;
    for (var row = 0; row < height ~/ 2; row++) {
      for (var col = 0; col < width ~/ 2; col++) {
        bytes[destination++] =
            v.bytes[row * v.bytesPerRow + col * (v.bytesPerPixel ?? 1)];
        bytes[destination++] =
            u.bytes[row * u.bytesPerRow + col * (u.bytesPerPixel ?? 1)];
      }
    }
  }
  if (enhanceContrast) _stretchContrast(bytes, yLength);
  return bytes;
}

void _stretchContrast(Uint8List bytes, int yLength) {
  final histogram = List<int>.filled(256, 0);
  // A bounded sample is sufficient to estimate the 1st/99th percentiles.
  final step = (yLength ~/ 2048).clamp(1, yLength);
  var samples = 0;
  for (var i = 0; i < yLength; i += step) {
    histogram[bytes[i]]++;
    samples++;
  }
  final clip = (samples * 0.01).round();
  var lo = 0;
  var hi = 255;
  var count = 0;
  while (lo < 255 && count + histogram[lo] <= clip) {
    count += histogram[lo++];
  }
  count = 0;
  while (hi > lo && count + histogram[hi] <= clip) {
    count += histogram[hi--];
  }
  final range = hi - lo;
  if (range <= 0 || range >= 180) return;
  final lookup = List<int>.generate(
    256,
    (value) => ((value - lo) * 255 / range).round().clamp(0, 255),
  );
  for (var i = 0; i < yLength; i++) {
    bytes[i] = lookup[bytes[i]];
  }
}
