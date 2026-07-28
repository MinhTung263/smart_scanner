class SmartScannerResult {
  /// Indicates whether the result is from a multi-scan (continuous scanning) session.
  final bool isMultiScan;
  
  /// The single scanned barcode. Will be null if [isMultiScan] is true.
  final String? singleBarcode;
  
  /// The map of scanned barcodes and their quantities. Will be null if [isMultiScan] is false.
  final Map<String, int>? multiBarcodes;

  SmartScannerResult.single(String barcode)
      : isMultiScan = false,
        singleBarcode = barcode,
        multiBarcodes = null;

  SmartScannerResult.multi(Map<String, int> barcodes)
      : isMultiScan = true,
        singleBarcode = null,
        multiBarcodes = barcodes;
}
