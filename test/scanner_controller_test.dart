import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scanner/src/controllers/scanner_controller.dart';

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
}