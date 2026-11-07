import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scanner/src/data/services/camera_service.dart';

/// Records the platform calls made by [CameraService.applyFocusPoint].
class _FakeCamera {
  final List<String> calls = <String>[];

  Future<void> setFocusPoint(Offset? point) async =>
      calls.add('focus(${point == null ? 'null' : '${point.dx},${point.dy}'})');

  Future<void> setExposurePoint(Offset? point) async => calls.add(
    'exposure(${point == null ? 'null' : '${point.dx},${point.dy}'})',
  );
}

Future<List<String>> _run(Offset point, Offset? currentExposure) async {
  final _FakeCamera camera = _FakeCamera();
  await CameraService.applyFocusPoint(
    point: point,
    currentExposurePoint: currentExposure,
    setFocusPoint: camera.setFocusPoint,
    setExposurePoint: camera.setExposurePoint,
  );
  return camera.calls;
}

void main() {
  const Offset center = Offset(0.5, 0.4);

  test('refocus at the same point sends a single focus request', () async {
    // Previously: focus(null), focus(p), exposure(p) = two AF sweeps.
    expect(await _run(center, center), <String>['focus(0.5,0.4)']);
  });

  test('first focus sets exposure without sweeping, then focuses once', () async {
    expect(await _run(center, null), <String>[
      'focus(null)',
      'exposure(0.5,0.4)',
      'focus(0.5,0.4)',
    ]);
  });

  test('a moved point re-sends exposure before the single focus', () async {
    expect(await _run(const Offset(0.5, 0.6), center), <String>[
      'focus(null)',
      'exposure(0.5,0.6)',
      'focus(0.5,0.6)',
    ]);
  });

  test('tiny movement within tolerance keeps the exposure point', () async {
    expect(await _run(const Offset(0.505, 0.4), center), <String>[
      'focus(0.505,0.4)',
    ]);
  });
}
