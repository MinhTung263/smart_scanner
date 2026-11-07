import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scanner/src/core/constants/stream_scan_constants.dart';
import 'package:smart_scanner/src/domain/entities/stream_scan_options.dart';
import 'package:smart_scanner/src/domain/entities/stream_scan_request.dart';
import 'package:smart_scanner/src/domain/entities/stream_scan_response.dart';
import 'package:smart_scanner/src/domain/usecases/stream_scan_dispatcher.dart';

void main() {
  group('StreamScanDispatcher', () {
    test('sequential calls per code and quantity aggregation', () async {
      final List<StreamScanRequest> requests = <StreamScanRequest>[];
      final List<int> queuedHistory = <int>[];
      final Completer<StreamScanResponse> firstCallCompleter =
          Completer<StreamScanResponse>();

      final StreamScanDispatcher dispatcher = StreamScanDispatcher(
        onScan: (StreamScanRequest req) async {
          requests.add(req);
          if (requests.length == 1) {
            return firstCallCompleter.future;
          }
          return const StreamScanResponse.accept(title: 'Sản phẩm A');
        },
        onQueuedCountChanged: (String code, int count) {
          queuedHistory.add(count);
        },
      );

      // Dispatch first scan for CODE_A.
      dispatcher.dispatch(const StreamScanRequest(code: 'CODE_A', quantity: 1));

      expect(dispatcher.activeCalls, 1);
      expect(requests.length, 1);
      expect(requests.first.quantity, 1);

      // Two more dispatches arrive while first is in-flight.
      dispatcher.dispatch(const StreamScanRequest(code: 'CODE_A', quantity: 1));
      dispatcher.dispatch(const StreamScanRequest(code: 'CODE_A', quantity: 1));

      // Queued count should have progressed 1 -> 2.
      expect(queuedHistory, <int>[1, 2]);
      expect(requests.length, 1);

      // Complete first call.
      firstCallCompleter.complete(
        const StreamScanResponse.accept(title: 'Sản phẩm A'),
      );
      await dispatcher.drained;

      // Second call should have aggregated quantity 2.
      expect(requests.length, 2);
      expect(requests[1].quantity, 2);
      expect(dispatcher.acceptedCount, 3);
    });

    test(
      'maxConcurrent limit and FIFO ordering across different codes',
      () async {
        final List<String> startedOrder = <String>[];
        final Map<String, Completer<StreamScanResponse>> completers =
            <String, Completer<StreamScanResponse>>{
              'CODE_A': Completer<StreamScanResponse>(),
              'CODE_B': Completer<StreamScanResponse>(),
              'CODE_C': Completer<StreamScanResponse>(),
              'CODE_D': Completer<StreamScanResponse>(),
            };

        final StreamScanDispatcher dispatcher = StreamScanDispatcher(
          options: const StreamScanOptions(maxConcurrent: 2),
          onScan: (StreamScanRequest req) {
            startedOrder.add(req.code);
            return completers[req.code]!.future;
          },
        );

        dispatcher.dispatch(const StreamScanRequest(code: 'CODE_A'));
        dispatcher.dispatch(const StreamScanRequest(code: 'CODE_B'));
        dispatcher.dispatch(const StreamScanRequest(code: 'CODE_C'));
        dispatcher.dispatch(const StreamScanRequest(code: 'CODE_D'));

        // Only 2 should start concurrently.
        expect(dispatcher.activeCalls, 2);
        expect(dispatcher.readyQueueLength, 2);
        expect(startedOrder, <String>['CODE_A', 'CODE_B']);

        // Completing CODE_A opens a slot for CODE_C (FIFO).
        completers['CODE_A']!.complete(const StreamScanResponse.accept());
        await Future<void>.delayed(Duration.zero);

        expect(dispatcher.activeCalls, 2);
        expect(startedOrder, <String>['CODE_A', 'CODE_B', 'CODE_C']);

        // Completing CODE_B opens slot for CODE_D.
        completers['CODE_B']!.complete(const StreamScanResponse.accept());
        await Future<void>.delayed(Duration.zero);

        expect(startedOrder, <String>['CODE_A', 'CODE_B', 'CODE_C', 'CODE_D']);

        // Complete remaining and drain.
        completers['CODE_C']!.complete(const StreamScanResponse.accept());
        completers['CODE_D']!.complete(const StreamScanResponse.accept());
        await dispatcher.drained;

        expect(dispatcher.isIdle, isTrue);
        expect(dispatcher.acceptedCount, 4);
      },
    );

    test(
      'reject cancels queued items and reports total unadded quantity',
      () async {
        final Completer<StreamScanResponse> completer =
            Completer<StreamScanResponse>();
        int receivedUnadded = 0;
        int onScanCalls = 0;

        final StreamScanDispatcher dispatcher = StreamScanDispatcher(
          onScan: (StreamScanRequest req) {
            onScanCalls++;
            return completer.future;
          },
          onReject:
              (
                StreamScanRequest req,
                StreamScanResponse resp,
                int totalUnadded,
              ) {
                receivedUnadded = totalUnadded;
              },
        );

        dispatcher.dispatch(
          const StreamScanRequest(code: 'CODE_A', quantity: 1),
        );
        dispatcher.dispatch(
          const StreamScanRequest(code: 'CODE_A', quantity: 1),
        );
        dispatcher.dispatch(
          const StreamScanRequest(code: 'CODE_A', quantity: 1),
        );

        // Reject current call.
        completer.complete(const StreamScanResponse.reject('Hết hàng'));
        await dispatcher.drained;

        // 1 in-flight + 2 queued = 3 total unadded.
        expect(receivedUnadded, 3);
        expect(dispatcher.rejectedCount, 3);
        // Queued items should have been cancelled without extra calls.
        expect(onScanCalls, 1);
      },
    );

    test(
      'reject with same code and message accumulates rejected count',
      () async {
        final List<int> unaddedHistory = <int>[];

        final StreamScanDispatcher dispatcher = StreamScanDispatcher(
          onScan: (StreamScanRequest req) async {
            return const StreamScanResponse.reject('Hết hàng');
          },
          onReject:
              (
                StreamScanRequest req,
                StreamScanResponse resp,
                int totalUnadded,
              ) {
                unaddedHistory.add(totalUnadded);
              },
        );

        dispatcher.dispatch(
          const StreamScanRequest(code: 'CODE_A', quantity: 2),
        );
        await dispatcher.drained;

        dispatcher.dispatch(
          const StreamScanRequest(code: 'CODE_A', quantity: 1),
        );
        await dispatcher.drained;

        expect(unaddedHistory, <int>[2, 1]);
        expect(dispatcher.rejectedCount, 3);
      },
    );

    test('rescan immediately after reject is processed normally', () async {
      int callIndex = 0;
      final StreamScanDispatcher dispatcher = StreamScanDispatcher(
        onScan: (StreamScanRequest req) async {
          callIndex++;
          if (callIndex == 1) {
            return const StreamScanResponse.reject('Lỗi tạm thời');
          }
          return const StreamScanResponse.accept(title: 'Sản phẩm A');
        },
      );

      dispatcher.dispatch(const StreamScanRequest(code: 'CODE_A'));
      await dispatcher.drained;
      expect(dispatcher.rejectedCount, 1);

      // Rescan immediately should not be blocked without cooldown.
      dispatcher.dispatch(const StreamScanRequest(code: 'CODE_A'));
      await dispatcher.drained;

      expect(dispatcher.acceptedCount, 1);
      expect(dispatcher.rejectedCount, 1);
    });

    test(
      'when listener throws exception, queued items are still processed and drained completes',
      () async {
        final List<String> processedCodes = <String>[];
        final List<FlutterErrorDetails> errorReports = <FlutterErrorDetails>[];

        final StreamScanDispatcher dispatcher = StreamScanDispatcher(
          errorReporter: (FlutterErrorDetails details) {
            errorReports.add(details);
          },
          onAccept: (StreamScanRequest req, StreamScanResponse resp) {
            if (req.code == 'CODE_FAILING_LISTENER') {
              throw Exception('Crash in onAccept listener!');
            }
          },
          onScan: (StreamScanRequest req) async {
            processedCodes.add(req.code);
            return StreamScanResponse.accept(title: req.code);
          },
        );

        dispatcher.dispatch(
          const StreamScanRequest(code: 'CODE_FAILING_LISTENER'),
        );
        dispatcher.dispatch(const StreamScanRequest(code: 'CODE_FOLLOWING_1'));
        dispatcher.dispatch(const StreamScanRequest(code: 'CODE_FOLLOWING_2'));

        // All items must complete and drained must finish.
        final StreamScanSummary summary = await dispatcher.drained;

        expect(processedCodes, <String>[
          'CODE_FAILING_LISTENER',
          'CODE_FOLLOWING_1',
          'CODE_FOLLOWING_2',
        ]);
        expect(summary.acceptedQuantity, 3);
        expect(errorReports.length, 1);
        expect(
          errorReports.first.exception.toString(),
          contains('Crash in onAccept listener!'),
        );
        expect(dispatcher.isIdle, isTrue);
      },
    );

    test('exception inside onScan callback is converted to reject', () async {
      FlutterErrorDetails? caughtDetails;
      String? rejectedMessage;

      final StreamScanDispatcher dispatcher = StreamScanDispatcher(
        errorReporter: (FlutterErrorDetails details) {
          caughtDetails = details;
        },
        onScan: (StreamScanRequest req) async {
          throw Exception('Simulated network timeout');
        },
        onReject:
            (StreamScanRequest req, StreamScanResponse resp, int totalUnadded) {
              rejectedMessage = resp.errorMessage;
            },
      );

      dispatcher.dispatch(const StreamScanRequest(code: 'CODE_ERR'));
      await dispatcher.drained;

      expect(caughtDetails, isNotNull);
      expect(rejectedMessage, StreamScanConstants.defaultErrorMessage);
      expect(dispatcher.rejectedCount, 1);
      expect(dispatcher.isIdle, isTrue);
    });

    test(
      'dispose detaches listeners while background queue drains completely',
      () async {
        int acceptCallbackCount = 0;
        final Completer<StreamScanResponse> completer =
            Completer<StreamScanResponse>();

        final StreamScanDispatcher dispatcher = StreamScanDispatcher(
          onScan: (StreamScanRequest req) => completer.future,
          onAccept: (StreamScanRequest req, StreamScanResponse resp) {
            acceptCallbackCount++;
          },
        );

        dispatcher.dispatch(
          const StreamScanRequest(code: 'CODE_A', quantity: 2),
        );

        // Detach listeners as when UI controller is disposed.
        dispatcher.detachListeners();

        // Complete background call.
        completer.complete(const StreamScanResponse.accept(title: 'A'));
        final StreamScanSummary summary = await dispatcher.drained;

        // Listener was detached so not called.
        expect(acceptCallbackCount, 0);
        // Background drain completed successfully with correct summary.
        expect(summary.acceptedQuantity, 2);
        expect(summary.notAddedQuantity, 0);
        expect(dispatcher.summary.acceptedQuantity, 2);
        expect(dispatcher.summary.notAddedQuantity, 0);
      },
    );
  });
}
