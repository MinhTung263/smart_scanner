import 'package:flutter/material.dart';
import 'package:smart_scanner/src/domain/entities/scanned_barcode.dart';

import '../domain/usecases/barcode_processor_usecase.dart';

class ScannerController extends ChangeNotifier {
  final BarcodeProcessorUseCase _barcodeProcessor;

  double _currentZoom = 1.0;
  bool _isProcessing = false;
  bool _isMultiScan = false;
  String _latestBarcode = 'Chưa quét được mã vạch';
  double _scanWindowSizeRatio = 0.8;
  double _baseScanWindowSizeRatio = 0.8;

  Map<String, ScannedBarcode> _scannedBarcodes = {};
  Set<String> _previousVisibleBarcodes = {};

  ScannerController({BarcodeProcessorUseCase? barcodeProcessor})
    : _barcodeProcessor = barcodeProcessor ?? const BarcodeProcessorUseCase();

  double get currentZoom => _currentZoom;
  bool get isProcessing => _isProcessing;
  bool get isMultiScan => _isMultiScan;
  String get latestBarcode => _latestBarcode;
  double get scanWindowSizeRatio => _scanWindowSizeRatio;
  Map<String, ScannedBarcode> get scannedBarcodes => _scannedBarcodes;

  void setZoom(double zoom) {
    if (_currentZoom != zoom) {
      _currentZoom = zoom;
      notifyListeners();
    }
  }

  void setMultiScan(bool value) {
    if (_isMultiScan != value) {
      _isMultiScan = value;
      if (!_isMultiScan) {
        _scannedBarcodes.clear();
        _previousVisibleBarcodes.clear();
      }
      notifyListeners();
    }
  }

  void setProcessing(bool value) {
    if (_isProcessing != value) {
      _isProcessing = value;
      notifyListeners();
    }
  }

  void setBaseScanWindowSizeRatio(double ratio) {
    _baseScanWindowSizeRatio = ratio;
  }

  void updateScanWindowSizeRatio(double scale) {
    final newRatio = (_baseScanWindowSizeRatio * (1.0 / scale)).clamp(0.4, 0.9);
    if (_scanWindowSizeRatio != newRatio) {
      _scanWindowSizeRatio = newRatio;
      notifyListeners();
    }
  }

  void setLatestBarcode(String barcode) {
    _latestBarcode = barcode;
    notifyListeners();
  }

  /// Processes newly-scanned barcode values (already extracted as strings, so
  /// this doesn't care which engine — ML Kit, ZXing, or otherwise — decoded
  /// them).
  bool processMultiScanValues(List<String> newBarcodeValues) {
    if (newBarcodeValues.isEmpty) return false;

    final (updatedBarcodes, hasNewOrIncremented) = _barcodeProcessor
        .processMultiScan(
          newBarcodeValues,
          _scannedBarcodes,
          _previousVisibleBarcodes,
        );

    _previousVisibleBarcodes = newBarcodeValues.toSet();

    if (hasNewOrIncremented) {
      _scannedBarcodes = updatedBarcodes;
      _latestBarcode = newBarcodeValues.last;
      notifyListeners();
    }

    return hasNewOrIncremented;
  }
}
