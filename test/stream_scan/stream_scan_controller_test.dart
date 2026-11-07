import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:smart_scanner/src/core/constants/stream_scan_constants.dart';
import 'package:smart_scanner/src/data/services/stream_vibration_service.dart';
import 'package:smart_scanner/src/domain/entities/stream_frame_report.dart';
import 'package:smart_scanner/src/domain/entities/stream_scan_card_item.dart';
import 'package:smart_scanner/src/domain/entities/stream_scan_options.dart';
import 'package:smart_scanner/src/domain/entities/stream_scan_request.dart';
import 'package:smart_scanner/src/domain/entities/stream_scan_response.dart';
import 'package:smart_scanner/src/presentation/controllers/stream_scan_controller.dart';

class _FakeVibrationService extends StreamVibrationService {
  int successVibrations = 0;
  int errorVibrations = 0;

  _FakeVibrationService() : super(enableVibration: true);

  @override
  Future<void> vibrateSuccess() async {
    successVibrations++;
  }

  @override
  Future<void> vibrateError() async {
    errorVibrations++;
  }
}

void main() {
  group('StreamScanController lifecycle and state', () {
    testWidgets('initial state has empty lists and false network slow', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = StreamScanController(
        onScan: (StreamScanRequest req) async {
          return const StreamScanResponse.accept();
        },
      );

      expect(controller.recentCards.value.isEmpty, isTrue);
      expect(controller.errorChips.value.isEmpty, isTrue);
      expect(controller.isNetworkSlow.value, isFalse);

      controller.dispose();
    });

    testWidgets('processing card added and updated on accept', (
      WidgetTester tester,
    ) async {
      final _FakeVibrationService vibrationService = _FakeVibrationService();
      final Completer<StreamScanResponse> completer =
          Completer<StreamScanResponse>();

      final StreamScanController controller = StreamScanController(
        onScan: (StreamScanRequest req) => completer.future,
        vibrationService: vibrationService,
      );

      // Dispatch request to trigger processing state.
      controller.dispatcher.dispatch(
        const StreamScanRequest(code: 'PROD_1', quantity: 1),
      );
      await tester.pump();

      expect(controller.recentCards.value.length, 1);
      final StreamScanCardItem processingItem =
          controller.recentCards.value.first;
      expect(processingItem.code, 'PROD_1');
      expect(processingItem.isProcessing, isTrue);

      // Complete request with accept response.
      completer.complete(
        const StreamScanResponse.accept(
          title: 'Sữa tươi 1L',
          subtitle: '30.000đ',
          totalInCart: 3,
        ),
      );
      await tester.pump();

      expect(controller.recentCards.value.length, 1);
      final StreamScanCardItem acceptedItem =
          controller.recentCards.value.first;
      expect(acceptedItem.isAccepted, isTrue);
      expect(acceptedItem.title, 'Sữa tươi 1L');
      expect(acceptedItem.subtitle, '30.000đ');
      expect(acceptedItem.totalInCart, 3);
      expect(vibrationService.successVibrations, 1);

      controller.dispose();
    });

    testWidgets('re-scans while in flight add to pendingQuantity', (
      WidgetTester tester,
    ) async {
      final Completer<StreamScanResponse> completer =
          Completer<StreamScanResponse>();

      final StreamScanController controller = StreamScanController(
        onScan: (StreamScanRequest req) => completer.future,
      );

      controller.dispatcher.dispatch(
        const StreamScanRequest(code: 'PROD_2', quantity: 1),
      );
      await tester.pump();
      expect(controller.recentCards.value.first.pendingQuantity, 1);

      // Two more scans of the same code while the first is in flight.
      controller.dispatcher.dispatch(
        const StreamScanRequest(code: 'PROD_2', quantity: 1),
      );
      controller.dispatcher.dispatch(
        const StreamScanRequest(code: 'PROD_2', quantity: 1),
      );
      await tester.pump();

      expect(controller.recentCards.value.length, 1);
      expect(controller.recentCards.value.first.pendingQuantity, 3);

      // First call (1) then merged call (2) both accepted.
      completer.complete(const StreamScanResponse.accept());
      await tester.pump();
      await tester.pump();

      final StreamScanCardItem item = controller.recentCards.value.first;
      expect(item.pendingQuantity, 0);
      expect(item.acceptedQuantity, 3);
      expect(item.isAccepted, isTrue);

      controller.dispose();
    });

    testWidgets('every scan brings its product layer to the front', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = StreamScanController(
        onScan: (StreamScanRequest req) async =>
            const StreamScanResponse.accept(),
        vibrationService: _FakeVibrationService(),
      );

      for (final String code in <String>['A', 'B', 'C']) {
        controller.dispatcher.dispatch(StreamScanRequest(code: code));
        await tester.pump();
      }
      expect(
        controller.recentCards.value.map((StreamScanCardItem c) => c.code),
        <String>['C', 'B', 'A'],
      );

      // Re-scanning A moves it to the front without adding a new layer.
      controller.dispatcher.dispatch(const StreamScanRequest(code: 'A'));
      await tester.pump();
      expect(
        controller.recentCards.value.map((StreamScanCardItem c) => c.code),
        <String>['A', 'C', 'B'],
      );
      expect(controller.recentCards.value.first.acceptedQuantity, 2);

      controller.dispose();
    });

    testWidgets('product pushed out of view is still known when re-scanned', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = StreamScanController(
        options: const StreamScanOptions(maxVisibleCards: 2),
        onScan: (StreamScanRequest req) async =>
            const StreamScanResponse.accept(),
        vibrationService: _FakeVibrationService(),
      );

      for (final String code in <String>['A', 'B', 'C']) {
        controller.dispatcher.dispatch(StreamScanRequest(code: code));
        await tester.pump();
      }
      expect(
        controller.recentCards.value.map((StreamScanCardItem c) => c.code),
        <String>['C', 'B'],
      );

      controller.dispatcher.dispatch(const StreamScanRequest(code: 'A'));
      await tester.pump();

      final StreamScanCardItem front = controller.recentCards.value.first;
      expect(front.code, 'A');
      expect(front.acceptedQuantity, 2);
      // No totalInCart from host: fall back to the session count.
      expect(front.displayQuantity, 2);

      controller.dispose();
    });

    testWidgets('counter counts distinct accepted products and quantity', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = StreamScanController(
        onScan: (StreamScanRequest req) async => req.code == 'BAD'
            ? const StreamScanResponse.reject('Không tìm thấy')
            : const StreamScanResponse.accept(),
        vibrationService: _FakeVibrationService(),
      );

      for (final String code in <String>['A', 'A', 'B', 'BAD']) {
        controller.dispatcher.dispatch(StreamScanRequest(code: code));
        await tester.pump();
      }

      expect(controller.counter.value.itemCount, 2);
      expect(controller.counter.value.totalQuantity, 3);

      await tester.pump(const Duration(seconds: 6));
      controller.dispose();
    });

    testWidgets('scan frame flashes green on accept and red on reject', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = StreamScanController(
        onScan: (StreamScanRequest req) async => req.code == 'BAD'
            ? const StreamScanResponse.reject('Mã không hợp lệ')
            : const StreamScanResponse.accept(),
        vibrationService: _FakeVibrationService(),
      );

      controller.dispatcher.dispatch(const StreamScanRequest(code: 'OK'));
      await tester.pump();
      expect(controller.frameFlash.value, StreamScanFrameFlash.success);
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.frameFlash.value, StreamScanFrameFlash.none);

      controller.dispatcher.dispatch(const StreamScanRequest(code: 'BAD'));
      await tester.pump();
      expect(controller.frameFlash.value, StreamScanFrameFlash.error);

      await tester.pump(const Duration(seconds: 6));
      controller.dispose();
    });

    testWidgets('toggle off pauses after one accepted code until tap', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = StreamScanController(
        onScan: (StreamScanRequest req) async =>
            const StreamScanResponse.accept(),
        vibrationService: _FakeVibrationService(),
      );

      controller.setContinuousMode(false);
      expect(controller.isContinuous.value, isFalse);
      expect(
        controller.errorChips.value.first.message,
        StreamScanConstants.continuousOffMessage,
      );

      controller.dispatcher.dispatch(const StreamScanRequest(code: 'A'));
      await tester.pump();

      expect(controller.isWaitingForTap.value, isTrue);
      expect(controller.presenceTracker.isPaused, isTrue);

      // "Chạm để quét tiếp" resumes counting.
      controller.continueScanning();
      expect(controller.isWaitingForTap.value, isFalse);
      expect(controller.presenceTracker.isPaused, isFalse);

      await tester.pump(const Duration(seconds: 3));
      controller.dispose();
    });

    testWidgets('toggle off: a rejected code does not pause scanning', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = StreamScanController(
        onScan: (StreamScanRequest req) async =>
            const StreamScanResponse.reject('Không tìm thấy'),
        vibrationService: _FakeVibrationService(),
      );

      controller.setContinuousMode(false);
      controller.dispatcher.dispatch(const StreamScanRequest(code: 'X'));
      await tester.pump();

      expect(controller.isWaitingForTap.value, isFalse);
      expect(controller.presenceTracker.isPaused, isFalse);

      await tester.pump(const Duration(seconds: 6));
      controller.dispose();
    });

    testWidgets('turning the toggle back on clears the single-mode pause', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = StreamScanController(
        onScan: (StreamScanRequest req) async =>
            const StreamScanResponse.accept(),
        vibrationService: _FakeVibrationService(),
      );

      controller.setContinuousMode(false);
      controller.dispatcher.dispatch(const StreamScanRequest(code: 'A'));
      await tester.pump();
      expect(controller.isWaitingForTap.value, isTrue);

      controller.setContinuousMode(true);
      expect(controller.isWaitingForTap.value, isFalse);
      expect(controller.presenceTracker.isPaused, isFalse);
      expect(
        controller.errorChips.value.first.message,
        StreamScanConstants.continuousOnMessage,
      );

      await tester.pump(const Duration(seconds: 3));
      controller.dispose();
    });

    testWidgets('reject of a product already in cart keeps its layer', (
      WidgetTester tester,
    ) async {
      int calls = 0;
      final _FakeVibrationService vibrationService = _FakeVibrationService();
      final StreamScanController controller = StreamScanController(
        onScan: (StreamScanRequest req) async {
          calls++;
          return calls == 1
              ? const StreamScanResponse.accept(
                  title: 'Nước suối 500ml',
                  totalInCart: 3,
                )
              : const StreamScanResponse.reject('Hết hàng');
        },
        vibrationService: vibrationService,
      );

      controller.dispatcher.dispatch(const StreamScanRequest(code: 'WATER'));
      await tester.pump();
      controller.dispatcher.dispatch(const StreamScanRequest(code: 'WATER'));
      await tester.pump();

      // Layer stays with the previous cart quantity; chip explains the error.
      expect(controller.recentCards.value.length, 1);
      final StreamScanCardItem item = controller.recentCards.value.first;
      expect(item.code, 'WATER');
      expect(item.isAccepted, isTrue);
      expect(item.pendingQuantity, 0);
      expect(item.displayQuantity, 3);
      expect(controller.errorChips.value.single.message, 'Hết hàng');
      expect(vibrationService.successVibrations, 1);
      expect(vibrationService.errorVibrations, 1);

      controller.dispose();
    });

    testWidgets('reject removes card and creates error chip', (
      WidgetTester tester,
    ) async {
      final _FakeVibrationService vibrationService = _FakeVibrationService();

      final StreamScanController controller = StreamScanController(
        onScan: (StreamScanRequest req) async {
          return const StreamScanResponse.reject('Hết hàng');
        },
        vibrationService: vibrationService,
      );

      controller.dispatcher.dispatch(
        const StreamScanRequest(code: 'OUT_STOCK', quantity: 1),
      );
      await tester.pump();

      expect(controller.recentCards.value.isEmpty, isTrue);
      expect(controller.errorChips.value.length, 1);
      final StreamScanErrorChipItem chip = controller.errorChips.value.first;
      expect(chip.code, 'OUT_STOCK');
      expect(chip.message, 'Hết hàng');
      expect(vibrationService.errorVibrations, 1);

      controller.dispose();
    });

    testWidgets(
      'reject with same code and message accumulates quantity and resets timer',
      (WidgetTester tester) async {
        final StreamScanController controller = StreamScanController(
          onScan: (StreamScanRequest req) async {
            return const StreamScanResponse.reject('Lỗi quét');
          },
        );

        controller.dispatcher.dispatch(
          const StreamScanRequest(code: 'DUP_ERR', quantity: 2),
        );
        await tester.pump();
        expect(controller.errorChips.value.first.unaddedQuantity, 2);

        // Advance 3 seconds (less than 5s auto-hide).
        await tester.pump(const Duration(seconds: 3));
        expect(controller.errorChips.value.length, 1);

        // Duplicate reject occurs, resets timer and accumulates quantity.
        controller.dispatcher.dispatch(
          const StreamScanRequest(code: 'DUP_ERR', quantity: 3),
        );
        await tester.pump();

        expect(controller.errorChips.value.length, 1);
        expect(controller.errorChips.value.first.unaddedQuantity, 5);

        // Advance 3 seconds again: chip should still be present because timer was reset.
        await tester.pump(const Duration(seconds: 3));
        expect(controller.errorChips.value.length, 1);

        // Advance past 5s from the reset: chip hides.
        await tester.pump(const Duration(seconds: 3));
        expect(controller.errorChips.value.isEmpty, isTrue);

        controller.dispose();
      },
    );

    testWidgets('auto-hide removes error chip after 5 seconds', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = StreamScanController(
        onScan: (StreamScanRequest req) async {
          return const StreamScanResponse.reject('Lỗi nhẹ');
        },
      );

      controller.dispatcher.dispatch(
        const StreamScanRequest(code: 'AUTO_1', quantity: 1),
      );
      await tester.pump();
      expect(controller.errorChips.value.length, 1);

      // Advance clock by 3 seconds: chip should remain.
      await tester.pump(const Duration(seconds: 3));
      expect(controller.errorChips.value.length, 1);

      // Advance clock past 5 seconds total: chip should auto hide.
      await tester.pump(const Duration(seconds: 3));
      expect(controller.errorChips.value.isEmpty, isTrue);

      controller.dispose();
    });

    testWidgets('slow network flag activates after slowHintAfter duration', (
      WidgetTester tester,
    ) async {
      final Completer<StreamScanResponse> completer =
          Completer<StreamScanResponse>();

      final StreamScanController controller = StreamScanController(
        onScan: (StreamScanRequest req) => completer.future,
      );

      controller.dispatcher.dispatch(
        const StreamScanRequest(code: 'SLOW_CODE', quantity: 1),
      );
      await tester.pump();

      expect(controller.isNetworkSlow.value, isFalse);

      // Advance clock by 2.5 seconds: still within 3s threshold.
      await tester.pump(const Duration(milliseconds: 2500));
      expect(controller.isNetworkSlow.value, isFalse);

      // Advance past 3 seconds: slow network flag activates.
      await tester.pump(const Duration(milliseconds: 1000));
      expect(controller.isNetworkSlow.value, isTrue);

      // Complete request: flag resets.
      completer.complete(const StreamScanResponse.accept());
      await tester.pump();
      expect(controller.isNetworkSlow.value, isFalse);

      controller.dispose();
    });

    testWidgets('dispose detaches UI listeners while background queue drains', (
      WidgetTester tester,
    ) async {
      final Completer<StreamScanResponse> completer =
          Completer<StreamScanResponse>();

      final StreamScanController controller = StreamScanController(
        onScan: (StreamScanRequest req) => completer.future,
      );

      controller.dispatcher.dispatch(
        const StreamScanRequest(code: 'DRAIN_CODE', quantity: 1),
      );
      await tester.pump();
      expect(controller.recentCards.value.length, 1);

      // Dispose controller while call is in-flight.
      controller.dispose();

      // Complete call in background.
      completer.complete(
        const StreamScanResponse.accept(title: 'Nền thành công'),
      );
      await controller.dispatcher.drained;

      // Dispatcher accepted count reflects background completion.
      expect(controller.dispatcher.acceptedCount, 1);
    });

    testWidgets('onFrameProcessed delegates to tracker and dispatches', (
      WidgetTester tester,
    ) async {
      final List<String> receivedCodes = <String>[];

      final StreamScanController controller = StreamScanController(
        onScan: (StreamScanRequest req) async {
          receivedCodes.add(req.code);
          return const StreamScanResponse.accept();
        },
      );

      final StreamFrameReport report = StreamFrameReport(
        barcodes: <Barcode>[
          Barcode(
            type: BarcodeType.text,
            format: BarcodeFormat.code128,
            displayValue: 'FRAME_CODE_1',
            rawValue: 'FRAME_CODE_1',
            rawBytes: null,
            boundingBox: Rect.zero,
            cornerPoints: const <Point<int>>[],
            value: null,
          ),
        ],
      );

      controller.onFrameProcessed(report);
      await tester.pump();

      expect(receivedCodes, <String>['FRAME_CODE_1']);

      controller.dispose();
    });
  });
}
