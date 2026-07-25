import '../entities/scanned_barcode.dart';

class BarcodeProcessorUseCase {
  final int debounceMilliseconds;

  const BarcodeProcessorUseCase({this.debounceMilliseconds = 1200});

  /// Processes newly detected barcodes against the existing list of scanned barcodes.
  /// Returns a map of the updated scanned barcodes and a boolean indicating if there was any change.
  (Map<String, ScannedBarcode>, bool) processMultiScan(
    List<String> newBarcodes,
    Map<String, ScannedBarcode> existingBarcodes,
    Set<String> previousVisibleBarcodes,
  ) {
    bool hasNewOrIncremented = false;
    final Map<String, ScannedBarcode> updatedBarcodes = Map.from(existingBarcodes);

    for (var val in newBarcodes) {
      if (!updatedBarcodes.containsKey(val)) {
        updatedBarcodes[val] = ScannedBarcode(
          value: val,
          count: 1,
          lastIncrementTime: DateTime.now(),
        );
        hasNewOrIncremented = true;
      } else {
        final existingItem = updatedBarcodes[val]!;
        final bool timeThresholdMet = DateTime.now()
                .difference(existingItem.lastIncrementTime)
                .inMilliseconds >
            debounceMilliseconds;

        if (!previousVisibleBarcodes.contains(val) || timeThresholdMet) {
          updatedBarcodes[val] = existingItem.copyWith(
            count: existingItem.count + 1,
            lastIncrementTime: DateTime.now(),
          );
          hasNewOrIncremented = true;
        }
      }
    }

    return (updatedBarcodes, hasNewOrIncremented);
  }
}
