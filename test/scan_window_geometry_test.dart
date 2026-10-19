import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scanner/src/presentation/pages/smart_scanner_page.dart';

void main() {
  const screenSize = Size(400, 800);

  test('barcode scan window is 10px wider and 1.5x taller', () {
    final window = calculateScanWindow(
      screenSize: screenSize,
      sizeRatio: 0.8,
      isQRMode: false,
    );

    expect(window.width, 330);
    expect(window.height, closeTo(216, 0.001));
    expect(window.center, const Offset(200, 340));
  });

  test('QR scan window uses the same width and height expansion', () {
    final window = calculateScanWindow(
      screenSize: screenSize,
      sizeRatio: 0.8,
      isQRMode: true,
    );

    expect(window.width, 330);
    expect(window.height, 480);
    expect(window.center, const Offset(200, 340));
  });

  test('landscape barcode window stays horizontal and inside the screen', () {
    final window = calculateScanWindow(
      screenSize: const Size(800, 400),
      sizeRatio: 0.8,
      isQRMode: false,
    );

    expect(window.width, 650);
    expect(window.height, 260);
    expect(window.center, const Offset(400, 200));
    expect(window.left, greaterThanOrEqualTo(0));
    expect(window.top, greaterThanOrEqualTo(0));
    expect(window.right, lessThanOrEqualTo(800));
    expect(window.bottom, lessThanOrEqualTo(400));
  });

  test('landscape QR window is based on the shorter screen axis', () {
    final window = calculateScanWindow(
      screenSize: const Size(800, 400),
      sizeRatio: 0.8,
      isQRMode: true,
    );

    expect(window.width, 330);
    expect(window.height, 300);
    expect(window.center, const Offset(400, 200));
  });
}
