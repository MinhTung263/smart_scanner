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

  test('QR scan window is a square as wide as the barcode window', () {
    final window = calculateScanWindow(
      screenSize: screenSize,
      sizeRatio: 0.8,
      isQRMode: true,
    );

    expect(window.width, 330);
    expect(window.height, 330);
    expect(window.center, const Offset(200, 340));
  });

  test('QR scan window stays square at every pinch ratio', () {
    for (final double ratio in <double>[0.4, 0.6, 0.8, 0.9]) {
      final window = calculateScanWindow(
        screenSize: const Size(393, 873),
        sizeRatio: ratio,
        isQRMode: true,
      );
      expect(window.width, window.height);
    }
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

  group('controls row top', () {
    test('keeps the old position when it does not reach the top bar', () {
      // Barcode mode: window is low, row sits 52px above it as before.
      expect(
        calculateControlsTop(highestScanWindowTop: 243, safeAreaTop: 40),
        243 - 52,
      );
      // No status bar inset: the old 68px minimum still applies.
      expect(
        calculateControlsTop(highestScanWindowTop: 100, safeAreaTop: 0),
        68,
      );
    });

    test('moves below the top bar when a tall QR window pushes it up', () {
      // Tall QR window on a notched phone: old value 68 overlapped the bar.
      final double top = calculateControlsTop(
        highestScanWindowTop: 111,
        safeAreaTop: 40,
      );
      // Top bar ends at safeAreaTop + 8 padding + 42 button = 90.
      expect(top, greaterThanOrEqualTo(90));
      expect(top, 96);
    });
  });

  test('landscape QR window is a square limited by the shorter axis', () {
    final window = calculateScanWindow(
      screenSize: const Size(800, 400),
      sizeRatio: 0.8,
      isQRMode: true,
    );

    // 330 wide from the shorter axis, capped at 75% of the 400px height.
    expect(window.width, 300);
    expect(window.height, 300);
    expect(window.center, const Offset(400, 200));
  });
}
