import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:smart_scanner/smart_scanner.dart';

Barcode _createTestBarcode(
  String code, {
  BarcodeFormat format = BarcodeFormat.ean13,
}) {
  return Barcode(
    type: BarcodeType.text,
    format: format,
    displayValue: code,
    rawValue: code,
    rawBytes: null,
    boundingBox: Rect.zero,
    cornerPoints: const <Point<int>>[],
    value: null,
  );
}

void main() {
  group('CustomBarcodeScanner hook & initialZoom tests', () {
    testWidgets('mounts normally with default null hook and zoom', (
      WidgetTester tester,
    ) async {
      final CustomBarcodeScanner scanner = CustomBarcodeScanner(
        onDetect: (List<Barcode> barcodes) {},
      );

      expect(scanner.onFrameProcessed, isNull);
      expect(scanner.initialZoom, isNull);

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: scanner)));

      expect(find.byType(CustomBarcodeScanner), findsOneWidget);
    });

    testWidgets('retains onFrameProcessed and initialZoom when provided', (
      WidgetTester tester,
    ) async {
      void dummyCallback(StreamFrameReport report) {}

      final CustomBarcodeScanner scanner = CustomBarcodeScanner(
        onDetect: (List<Barcode> barcodes) {},
        onFrameProcessed: dummyCallback,
        initialZoom: 2.0,
      );

      expect(scanner.onFrameProcessed, equals(dummyCallback));
      expect(scanner.initialZoom, 2.0);
    });

    testWidgets('dispatchFrameReport does not throw when hook is null', (
      WidgetTester tester,
    ) async {
      final GlobalKey<CustomBarcodeScannerState> key =
          GlobalKey<CustomBarcodeScannerState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomBarcodeScanner(
              key: key,
              onDetect: (List<Barcode> barcodes) {},
            ),
          ),
        ),
      );

      final CustomBarcodeScannerState? state = key.currentState;
      expect(state, isNotNull);

      final Barcode testBarcode = _createTestBarcode('8938505963014');
      expect(
        () => state!.dispatchFrameReport(
          filteredBarcodes: <Barcode>[testBarcode],
          isBlurry: false,
          hasGlare: false,
          isMoving: false,
        ),
        returnsNormally,
      );
    });

    testWidgets('dispatchFrameReport delivers report with accurate data', (
      WidgetTester tester,
    ) async {
      final GlobalKey<CustomBarcodeScannerState> key =
          GlobalKey<CustomBarcodeScannerState>();
      StreamFrameReport? capturedReport;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomBarcodeScanner(
              key: key,
              onDetect: (List<Barcode> barcodes) {},
              onFrameProcessed: (StreamFrameReport report) {
                capturedReport = report;
              },
            ),
          ),
        ),
      );

      final CustomBarcodeScannerState? state = key.currentState;
      expect(state, isNotNull);

      final Barcode testBarcode = _createTestBarcode('8938505963014');
      state!.dispatchFrameReport(
        filteredBarcodes: <Barcode>[testBarcode],
        isBlurry: true,
        hasGlare: false,
        isMoving: true,
      );

      expect(capturedReport, isNotNull);
      expect(capturedReport!.barcodes.length, 1);
      expect(capturedReport!.barcodes.first.rawValue, '8938505963014');
      expect(capturedReport!.isBlurry, isTrue);
      expect(capturedReport!.hasGlare, isFalse);
      expect(capturedReport!.isMoving, isTrue);
    });

    testWidgets('dispatchFrameReport delivers report for empty frame', (
      WidgetTester tester,
    ) async {
      final GlobalKey<CustomBarcodeScannerState> key =
          GlobalKey<CustomBarcodeScannerState>();
      StreamFrameReport? capturedReport;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomBarcodeScanner(
              key: key,
              onDetect: (List<Barcode> barcodes) {},
              onFrameProcessed: (StreamFrameReport report) {
                capturedReport = report;
              },
            ),
          ),
        ),
      );

      final CustomBarcodeScannerState? state = key.currentState;
      expect(state, isNotNull);

      state!.dispatchFrameReport(
        filteredBarcodes: const <Barcode>[],
        isBlurry: false,
        hasGlare: true,
        isMoving: false,
      );

      expect(capturedReport, isNotNull);
      expect(capturedReport!.barcodes, isEmpty);
      expect(capturedReport!.isBlurry, isFalse);
      expect(capturedReport!.hasGlare, isTrue);
      expect(capturedReport!.isMoving, isFalse);
    });

    testWidgets('initialZoom is preserved on widget state', (
      WidgetTester tester,
    ) async {
      final GlobalKey<CustomBarcodeScannerState> defaultKey =
          GlobalKey<CustomBarcodeScannerState>();
      final GlobalKey<CustomBarcodeScannerState> customZoomKey =
          GlobalKey<CustomBarcodeScannerState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomBarcodeScanner(
              key: defaultKey,
              onDetect: (List<Barcode> barcodes) {},
            ),
          ),
        ),
      );

      expect(defaultKey.currentState?.widget.initialZoom, isNull);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomBarcodeScanner(
              key: customZoomKey,
              onDetect: (List<Barcode> barcodes) {},
              initialZoom: 2.0,
            ),
          ),
        ),
      );

      expect(customZoomKey.currentState?.widget.initialZoom, 2.0);
    });
  });
}
