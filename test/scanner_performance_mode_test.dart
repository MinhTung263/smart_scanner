import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scanner/src/domain/entities/scanner_performance_mode.dart';

void main() {
  group('ScannerPerformancePolicy', () {
    test('adaptive starts from balanced intervals', () {
      final policy = ScannerPerformancePolicy(ScannerPerformanceMode.adaptive);

      expect(policy.interval(idle: false), const Duration(milliseconds: 200));
      expect(policy.interval(idle: true), const Duration(milliseconds: 500));
    });

    test('adaptive speeds up after consistently fast decoding', () {
      final policy = ScannerPerformancePolicy(ScannerPerformanceMode.adaptive);

      for (var i = 0; i < 4; i++) {
        policy.recordDecode(const Duration(milliseconds: 30));
      }

      expect(policy.interval(idle: false), const Duration(milliseconds: 120));
      expect(policy.interval(idle: true), const Duration(milliseconds: 400));
    });

    test('adaptive backs off after consistently slow decoding', () {
      final policy = ScannerPerformancePolicy(ScannerPerformanceMode.adaptive);

      for (var i = 0; i < 4; i++) {
        policy.recordDecode(const Duration(milliseconds: 220));
      }

      expect(policy.interval(idle: false), const Duration(milliseconds: 400));
      expect(policy.interval(idle: true), const Duration(milliseconds: 660));
    });

    test('explicit modes keep predictable intervals', () {
      expect(
        ScannerPerformancePolicy(
          ScannerPerformanceMode.efficiency,
        ).interval(idle: false),
        const Duration(milliseconds: 350),
      );
      expect(
        ScannerPerformancePolicy(
          ScannerPerformanceMode.performance,
        ).interval(idle: false),
        const Duration(milliseconds: 100),
      );
    });
  });

  group('ScannerPerformanceVisualPolicy', () {
    test('only performance mode keeps continuous rich effects', () {
      for (final mode in ScannerPerformanceMode.values) {
        final expected = mode == ScannerPerformanceMode.performance;
        expect(mode.usesContinuousOverlayPulse, expected);
        expect(mode.usesRichOverlayEffects, expected);
      }
    });

    test('efficiency mode hides overlay labels', () {
      expect(ScannerPerformanceMode.efficiency.showsOverlayLabels, isFalse);
      expect(ScannerPerformanceMode.adaptive.showsOverlayLabels, isTrue);
      expect(ScannerPerformanceMode.balanced.showsOverlayLabels, isTrue);
      expect(ScannerPerformanceMode.performance.showsOverlayLabels, isTrue);
    });
  });
}
