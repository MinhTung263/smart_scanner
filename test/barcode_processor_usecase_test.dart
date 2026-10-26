import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scanner/src/domain/entities/scanned_barcode.dart';
import 'package:smart_scanner/src/domain/usecases/barcode_processor_usecase.dart';

void main() {
  group('BarcodeProcessorUseCase', () {
    test('reuses the existing map when a visible barcode is unchanged', () {
      final existing = <String, ScannedBarcode>{
        'held': ScannedBarcode(
          value: 'held',
          lastIncrementTime: DateTime.now(),
        ),
      };

      final (result, changed) = const BarcodeProcessorUseCase(
        debounceMilliseconds: 60000,
      ).processMultiScan(['held'], existing, {'held'});

      expect(changed, isFalse);
      expect(identical(result, existing), isTrue);
    });

    test('copies on first change without mutating the input map', () {
      final existingItem = ScannedBarcode(
        value: 'repeat',
        count: 3,
        lastIncrementTime: DateTime.now().subtract(const Duration(seconds: 2)),
      );
      final existing = <String, ScannedBarcode>{'repeat': existingItem};

      final (result, changed) = const BarcodeProcessorUseCase(
        debounceMilliseconds: 100,
      ).processMultiScan(['repeat'], existing, {'repeat'});

      expect(changed, isTrue);
      expect(identical(result, existing), isFalse);
      expect(result['repeat']?.count, 4);
      expect(existing['repeat'], same(existingItem));
      expect(existing['repeat']?.count, 3);
    });

    test('uses one timestamp for all additions in the same frame', () {
      final (result, changed) = const BarcodeProcessorUseCase()
          .processMultiScan(['first', 'second'], {}, {});

      expect(changed, isTrue);
      expect(
        result['first']?.lastIncrementTime,
        result['second']?.lastIncrementTime,
      );
    });
  });
}
