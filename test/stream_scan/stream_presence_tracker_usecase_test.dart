import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:smart_scanner/src/core/constants/stream_scan_constants.dart';
import 'package:smart_scanner/src/domain/entities/stream_frame_report.dart';
import 'package:smart_scanner/src/domain/entities/stream_scan_options.dart';
import 'package:smart_scanner/src/domain/usecases/stream_presence_tracker_usecase.dart';

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
  group('StreamPresenceTrackerUseCase', () {
    test('initial detection counts a new barcode', () {
      final StreamPresenceTrackerUseCase tracker =
          StreamPresenceTrackerUseCase();
      final Barcode barcode = _createTestBarcode('8938505963014');

      final List<Barcode> result = tracker.processFrame(
        StreamFrameReport(barcodes: <Barcode>[barcode]),
      );

      expect(result.length, 1);
      expect(result.first.rawValue, '8938505963014');
      expect(tracker.isCodePresent('8938505963014'), isTrue);
    });

    test(
      'keeping barcode static across consecutive frames does not count again',
      () {
        final StreamPresenceTrackerUseCase tracker =
            StreamPresenceTrackerUseCase();
        final Barcode barcode = _createTestBarcode('8938505963014');

        final List<Barcode> first = tracker.processFrame(
          StreamFrameReport(barcodes: <Barcode>[barcode]),
        );
        expect(first.length, 1);

        // Remaining frames should return empty list.
        for (int i = 0; i < 10; i++) {
          final List<Barcode> subsequent = tracker.processFrame(
            StreamFrameReport(barcodes: <Barcode>[barcode]),
          );
          expect(subsequent, isEmpty);
        }
      },
    );

    test(
      'two new barcodes in same frame only counts nearest and marks both present',
      () {
        final StreamPresenceTrackerUseCase tracker =
            StreamPresenceTrackerUseCase();
        final Barcode barcodeA = _createTestBarcode('CODE_A');
        final Barcode barcodeB = _createTestBarcode('CODE_B');

        // Frame 1 has both codes with A closer to center.
        final List<Barcode> frame1 = tracker.processFrame(
          StreamFrameReport(barcodes: <Barcode>[barcodeA, barcodeB]),
        );

        expect(frame1.length, 1);
        expect(frame1.first.rawValue, 'CODE_A');
        expect(tracker.isCodePresent('CODE_A'), isTrue);
        expect(tracker.isCodePresent('CODE_B'), isTrue);

        // Frame 2 has B closer to center, neither should be counted.
        final List<Barcode> frame2 = tracker.processFrame(
          StreamFrameReport(barcodes: <Barcode>[barcodeB, barcodeA]),
        );

        expect(frame2, isEmpty);
      },
    );

    test('skipping N - 1 missed frames does not cause rescan', () {
      final StreamPresenceTrackerUseCase tracker =
          StreamPresenceTrackerUseCase();
      final Barcode barcode = _createTestBarcode('CODE_A');

      // Initial detection counts code.
      tracker.processFrame(StreamFrameReport(barcodes: <Barcode>[barcode]));

      // 1 missed frame (N - 1 where N = 2).
      final List<Barcode> emptyFrame = tracker.processFrame(
        const StreamFrameReport(barcodes: <Barcode>[]),
      );
      expect(emptyFrame, isEmpty);
      expect(tracker.isCodePresent('CODE_A'), isTrue);

      // Reappears immediately without leaving frame.
      final List<Barcode> returnFrame = tracker.processFrame(
        StreamFrameReport(barcodes: <Barcode>[barcode]),
      );
      expect(returnFrame, isEmpty);
    });

    test(
      'missing >= N frames marks barcode absent and rescans upon return',
      () {
        final StreamPresenceTrackerUseCase tracker =
            StreamPresenceTrackerUseCase();
        final Barcode barcode = _createTestBarcode('CODE_A');

        // Initial detection.
        tracker.processFrame(StreamFrameReport(barcodes: <Barcode>[barcode]));

        // Frame 1 absent.
        tracker.processFrame(const StreamFrameReport(barcodes: <Barcode>[]));
        // Frame 2 absent, reaching threshold N = 2.
        tracker.processFrame(const StreamFrameReport(barcodes: <Barcode>[]));
        expect(tracker.isCodePresent('CODE_A'), isFalse);

        // Re-entry counts as new scan.
        final List<Barcode> returnFrame = tracker.processFrame(
          StreamFrameReport(barcodes: <Barcode>[barcode]),
        );
        expect(returnFrame.length, 1);
        expect(returnFrame.first.rawValue, 'CODE_A');
      },
    );

    test(
      'ignoreBlurryOrGlareMisses false treats blurry or glare frames as absent',
      () {
        // Default policy has ignoreBlurryOrGlareMisses = false.
        final StreamPresenceTrackerUseCase tracker =
            StreamPresenceTrackerUseCase();
        final Barcode barcode = _createTestBarcode('CODE_A');

        tracker.processFrame(StreamFrameReport(barcodes: <Barcode>[barcode]));

        // Blurry empty frame 1.
        tracker.processFrame(
          const StreamFrameReport(barcodes: <Barcode>[], isBlurry: true),
        );

        // Glare empty frame 2, reaching N = 2.
        tracker.processFrame(
          const StreamFrameReport(barcodes: <Barcode>[], hasGlare: true),
        );
        expect(tracker.isCodePresent('CODE_A'), isFalse);

        // Returns and gets counted.
        final List<Barcode> returnFrame = tracker.processFrame(
          StreamFrameReport(barcodes: <Barcode>[barcode]),
        );
        expect(returnFrame.length, 1);
      },
    );

    test(
      'ignoreBlurryOrGlareMisses true ignores up to K frames then marks absent',
      () {
        const RescanPolicy policy = RescanPolicy.leaveFrame(
          missedFrames: StreamScanConstants.defaultMissedFrames,
          ignoreBlurryOrGlareMisses: true,
          maxIgnoredMisses: StreamScanConstants.defaultMaxIgnoredMisses,
        );
        final StreamPresenceTrackerUseCase tracker =
            StreamPresenceTrackerUseCase(
              options: const StreamScanOptions(rescanPolicy: policy),
            );
        final Barcode barcode = _createTestBarcode('CODE_A');

        tracker.processFrame(StreamFrameReport(barcodes: <Barcode>[barcode]));

        // 2 consecutive blurry empty frames ignored.
        tracker.processFrame(
          const StreamFrameReport(barcodes: <Barcode>[], isBlurry: true),
        );
        tracker.processFrame(
          const StreamFrameReport(barcodes: <Barcode>[], hasGlare: true),
        );

        // Still present because misses were ignored.
        expect(tracker.isCodePresent('CODE_A'), isTrue);

        // Third blurry frame cannot be ignored (K = 2 exceeded).
        tracker.processFrame(
          const StreamFrameReport(barcodes: <Barcode>[], isBlurry: true),
        );
        // Fourth blurry frame counts as second miss (N = 2 reached).
        tracker.processFrame(
          const StreamFrameReport(barcodes: <Barcode>[], isBlurry: true),
        );
        expect(tracker.isCodePresent('CODE_A'), isFalse);

        // Re-entry counts again.
        final List<Barcode> returnFrame = tracker.processFrame(
          StreamFrameReport(barcodes: <Barcode>[barcode]),
        );
        expect(returnFrame.length, 1);
      },
    );

    test('state is preserved across pause and resume', () {
      final StreamPresenceTrackerUseCase tracker =
          StreamPresenceTrackerUseCase();
      final Barcode barcode = _createTestBarcode('CODE_A');

      tracker.processFrame(StreamFrameReport(barcodes: <Barcode>[barcode]));
      expect(tracker.isCodePresent('CODE_A'), isTrue);

      tracker.pause();
      expect(tracker.isPaused, isTrue);

      // Frames processed while paused are dropped.
      final List<Barcode> pausedResult = tracker.processFrame(
        const StreamFrameReport(barcodes: <Barcode>[]),
      );
      expect(pausedResult, isEmpty);
      expect(tracker.isCodePresent('CODE_A'), isTrue);

      tracker.resume();
      expect(tracker.isPaused, isFalse);

      // Code was still present, not counted again.
      final List<Barcode> resumedResult = tracker.processFrame(
        StreamFrameReport(barcodes: <Barcode>[barcode]),
      );
      expect(resumedResult, isEmpty);
    });

    test('reset clears all tracked presence states', () {
      final StreamPresenceTrackerUseCase tracker =
          StreamPresenceTrackerUseCase();
      final Barcode barcode = _createTestBarcode('CODE_A');

      tracker.processFrame(StreamFrameReport(barcodes: <Barcode>[barcode]));
      expect(tracker.isCodePresent('CODE_A'), isTrue);

      tracker.reset();
      expect(tracker.isCodePresent('CODE_A'), isFalse);

      final List<Barcode> afterReset = tracker.processFrame(
        StreamFrameReport(barcodes: <Barcode>[barcode]),
      );
      expect(afterReset.length, 1);
    });
  });
}
