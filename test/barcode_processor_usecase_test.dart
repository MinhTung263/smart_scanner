import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scanner/src/domain/entities/scanned_barcode.dart';
import 'package:smart_scanner/src/domain/usecases/barcode_processor_usecase.dart';

void main() {
  const useCase = BarcodeProcessorUseCase(debounceMilliseconds: 1000);

  test('adds a new barcode with count 1', () {
    final (map, changed) = useCase.processMultiScan(['A'], {}, {});
    expect(changed, isTrue);
    expect(map['A']!.count, 1);
  });

  test('duplicates within one frame count once', () {
    final (map, _) = useCase.processMultiScan(['A', 'A'], {}, {});
    expect(map['A']!.count, 1);
  });

  test('already visible barcode within debounce is not incremented', () {
    final existing = {
      'A': ScannedBarcode(
        value: 'A',
        count: 1,
        lastIncrementTime: DateTime.now(),
      ),
    };
    final (map, changed) = useCase.processMultiScan(['A'], existing, {'A'});
    expect(changed, isFalse);
    expect(map['A']!.count, 1);
  });

  test('barcode that left the view is incremented when seen again', () {
    final existing = {
      'A': ScannedBarcode(
        value: 'A',
        count: 1,
        lastIncrementTime: DateTime.now(),
      ),
    };
    final (map, changed) = useCase.processMultiScan(['A'], existing, {});
    expect(changed, isTrue);
    expect(map['A']!.count, 2);
  });

  test('visible barcode is incremented after debounce elapses', () {
    final existing = {
      'A': ScannedBarcode(
        value: 'A',
        count: 1,
        lastIncrementTime: DateTime.now().subtract(
          const Duration(seconds: 2),
        ),
      ),
    };
    final (map, _) = useCase.processMultiScan(['A'], existing, {'A'});
    expect(map['A']!.count, 2);
  });
}
