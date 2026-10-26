import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scanner/src/controllers/scanner_controller.dart';
import 'package:smart_scanner/src/data/services/camera_service.dart';

void main() {
  group('ScannerController multi-scan initialization', () {
    test('defaults to single-scan mode', () {
      final controller = ScannerController();
      addTearDown(controller.dispose);

      expect(controller.isMultiScan, isFalse);
    });

    test('can start in multi-scan mode', () {
      final controller = ScannerController(isMultiScan: true);
      addTearDown(controller.dispose);

      expect(controller.isMultiScan, isTrue);
    });
  });

  group('scanner zoom initialization', () {
    test('controller and camera both start at 1x', () {
      final controller = ScannerController();
      addTearDown(controller.dispose);

      expect(controller.currentZoom, 1.0);
      expect(CameraService.defaultZoomLevel, 1.0);
    });
  });
}
