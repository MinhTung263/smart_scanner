import '../entities/scanned_barcode.dart';

class BarcodeProcessorUseCase {
  final int debounceMilliseconds;

  /// When false, re-scanning an already-scanned code leaves its count as is.
  final bool incrementOnDuplicate;

  const BarcodeProcessorUseCase({
    this.debounceMilliseconds = 1200,
    this.incrementOnDuplicate = true,
  });

  /// Processes newly detected barcodes against the existing list of scanned barcodes.
  /// Returns a map of the updated scanned barcodes and a boolean indicating if there was any change.
  /// Duplicate values within the same frame are counted only once.
  (Map<String, ScannedBarcode>, bool) processMultiScan(
    List<String> newBarcodes,
    Map<String, ScannedBarcode> existingBarcodes,
    Set<String> previousVisibleBarcodes,
  ) {
    bool hasNewOrIncremented = false;
    final Map<String, ScannedBarcode> updatedBarcodes = Map.from(existingBarcodes);
    final now = DateTime.now();

    for (final val in newBarcodes.toSet()) {
      final existingItem = updatedBarcodes[val];
      if (existingItem == null) {
        updatedBarcodes[val] = ScannedBarcode(
          value: val,
          count: 1,
          lastIncrementTime: now,
        );
        hasNewOrIncremented = true;
      } else if (incrementOnDuplicate) {
        final bool timeThresholdMet =
            now.difference(existingItem.lastIncrementTime).inMilliseconds >
            debounceMilliseconds;

        if (!previousVisibleBarcodes.contains(val) || timeThresholdMet) {
          updatedBarcodes[val] = existingItem.copyWith(
            count: existingItem.count + 1,
            lastIncrementTime: now,
          );
          hasNewOrIncremented = true;
        }
      }
    }

    return (updatedBarcodes, hasNewOrIncremented);
  }
}
