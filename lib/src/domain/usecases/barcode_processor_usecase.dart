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
    Map<String, ScannedBarcode>? updatedBarcodes;
    final now = DateTime.now();

    for (final val in newBarcodes) {
      final currentBarcodes = updatedBarcodes ?? existingBarcodes;
      final existingItem = currentBarcodes[val];

      if (existingItem == null) {
        updatedBarcodes ??= Map<String, ScannedBarcode>.from(existingBarcodes);
        updatedBarcodes[val] = ScannedBarcode(
          value: val,
          count: 1,
          lastIncrementTime: now,
        );
      } else {
        final bool timeThresholdMet =
            now.difference(existingItem.lastIncrementTime).inMilliseconds >
            debounceMilliseconds;

        if (!previousVisibleBarcodes.contains(val) || timeThresholdMet) {
          updatedBarcodes ??= Map<String, ScannedBarcode>.from(
            existingBarcodes,
          );
          updatedBarcodes[val] = existingItem.copyWith(
            count: existingItem.count + 1,
            lastIncrementTime: now,
          );
        }
      }
    }

    // Keep the original map instance when the frame contains no logical
    // changes. Large inventory sessions can contain thousands of entries, so
    // eagerly cloning it for every decoded frame becomes progressively costly.
    return (updatedBarcodes ?? existingBarcodes, updatedBarcodes != null);
  }
}
