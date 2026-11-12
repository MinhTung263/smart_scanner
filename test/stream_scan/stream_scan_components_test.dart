import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scanner/src/core/constants/stream_scan_constants.dart';
import 'package:smart_scanner/src/presentation/components/stream_scan_counter_component.dart';
import 'package:smart_scanner/src/presentation/components/stream_scan_error_chip_component.dart';
import 'package:smart_scanner/src/presentation/components/stream_scan_result_card_component.dart';
import 'package:smart_scanner/src/presentation/components/stream_scan_slow_network_component.dart';
import 'package:smart_scanner/src/presentation/controllers/stream_scan_controller.dart';
import 'package:smart_scanner/src/presentation/pages/stream_scan_page.dart';
import 'package:smart_scanner/src/smart_scanner.dart';

Widget _buildTestApp(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

StreamScanController _acceptingController() {
  return StreamScanController(
    onScan: (StreamScanRequest req) async => const StreamScanResponse.accept(),
  );
}

/// Opens [StreamScanPage] from a button and records the popped result.
Future<List<StreamScanExitReason?>> _openPage(
  WidgetTester tester,
  StreamScanController controller,
) async {
  final List<StreamScanExitReason?> results = <StreamScanExitReason?>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (BuildContext context) {
          return ElevatedButton(
            onPressed: () async {
              results.add(
                await Navigator.of(context).push<StreamScanExitReason>(
                  MaterialPageRoute<StreamScanExitReason>(
                    builder: (BuildContext ctx) =>
                        StreamScanPage(controller: controller),
                  ),
                ),
              );
            },
            child: const Text('Mở Scanner'),
          );
        },
      ),
    ),
  );
  await tester.tap(find.text('Mở Scanner'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.byType(StreamScanPage), findsOneWidget);
  return results;
}

void main() {
  group('StreamScanResultCardComponent', () {
    testWidgets('renders no card at all before the first scan', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = _acceptingController();

      await tester.pumpWidget(
        _buildTestApp(StreamScanResultCardComponent(controller: controller)),
      );

      expect(
        tester.getSize(find.byType(StreamScanResultCardComponent)).height,
        0.0,
      );
      expect(
        find.descendant(
          of: find.byType(StreamScanResultCardComponent),
          matching: find.byType(Stack),
        ),
        findsNothing,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);

      controller.dispose();
    });

    testWidgets('draws at most 3 stacked layers, newest in front', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = _acceptingController();

      // Five cards in the controller; the stack only draws the newest three.
      controller.recentCards.value = <StreamScanCardItem>[
        for (final String code in <String>['E', 'D', 'C', 'B', 'A'])
          StreamScanCardItem(
            code: code,
            title: 'SP $code',
            acceptedQuantity: 1,
            timestamp: DateTime.now(),
          ),
      ];

      await tester.pumpWidget(
        _buildTestApp(StreamScanResultCardComponent(controller: controller)),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(StreamScanResultCardComponent),
          matching: find.byType(AnimatedPositioned),
        ),
        findsNWidgets(StreamScanConstants.stackVisibleLayers),
      );
      // Only the front (newest) card shows its content.
      expect(find.text('SP E'), findsOneWidget);
      expect(find.text('SP D'), findsNothing);

      // A newer card slides the older ones back; still 3 layers.
      controller.recentCards.value = <StreamScanCardItem>[
        StreamScanCardItem(
          code: 'F',
          title: 'SP F',
          acceptedQuantity: 1,
          timestamp: DateTime.now(),
        ),
        ...controller.recentCards.value,
      ];
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(StreamScanResultCardComponent),
          matching: find.byType(AnimatedPositioned),
        ),
        findsNWidgets(StreamScanConstants.stackVisibleLayers),
      );
      expect(find.text('SP F'), findsOneWidget);
      expect(find.text('SP E'), findsNothing);

      controller.dispose();
    });

    testWidgets('shows lookup state while the first scan is in flight', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = _acceptingController();

      controller.recentCards.value = <StreamScanCardItem>[
        StreamScanCardItem(
          code: '8935049510013',
          pendingQuantity: 1,
          timestamp: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(StreamScanResultCardComponent(controller: controller)),
      );

      expect(
        find.text(StreamScanConstants.defaultProcessingLabel),
        findsOneWidget,
      );
      expect(find.text('8935049510013'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      controller.dispose();
    });

    testWidgets('shows name, barcode and "+N" scanned quantity', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = _acceptingController();

      controller.recentCards.value = <StreamScanCardItem>[
        StreamScanCardItem(
          code: '8935049510013',
          title: 'Sữa tươi Vinamilk 100% hộp 1L',
          totalInCart: 7,
          acceptedQuantity: 2,
          timestamp: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(StreamScanResultCardComponent(controller: controller)),
      );

      expect(find.text('Sữa tươi Vinamilk 100% hộp 1L'), findsOneWidget);
      expect(find.text('8935049510013'), findsOneWidget);
      // Badge is the session scan count, not the cart total.
      expect(find.text('+2'), findsOneWidget);
      expect(find.text('+7'), findsNothing);

      controller.dispose();
    });

    testWidgets('shows only the most recent product on the card', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = _acceptingController();

      controller.recentCards.value = <StreamScanCardItem>[
        StreamScanCardItem(
          code: 'NEWEST',
          title: 'Newest',
          acceptedQuantity: 1,
          timestamp: DateTime.now(),
        ),
        StreamScanCardItem(
          code: 'OLDER',
          title: 'Older',
          acceptedQuantity: 1,
          timestamp: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(StreamScanResultCardComponent(controller: controller)),
      );

      expect(find.text('Newest'), findsOneWidget);
      expect(find.text('Older'), findsNothing);

      controller.dispose();
    });

    testWidgets('supports customBuilder override', (WidgetTester tester) async {
      final StreamScanController controller = _acceptingController();

      controller.recentCards.value = <StreamScanCardItem>[
        StreamScanCardItem(
          code: 'CUSTOM_CODE',
          title: 'Custom Title',
          timestamp: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(
          StreamScanResultCardComponent(
            controller: controller,
            customBuilder: (BuildContext ctx, StreamScanCardItem item) {
              return Text('Custom: ${item.code}');
            },
          ),
        ),
      );

      expect(find.text('Custom: CUSTOM_CODE'), findsOneWidget);

      controller.dispose();
    });
  });

  group('StreamScanCounterComponent', () {
    testWidgets('shows distinct items and total quantity', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = _acceptingController();

      await tester.pumpWidget(
        _buildTestApp(StreamScanCounterComponent(controller: controller)),
      );
      // Hidden until the first product is accepted.
      expect(
        find.text('${StreamScanConstants.counterItemsLabel} '),
        findsNothing,
      );

      for (final String code in <String>['A', 'A', 'B']) {
        controller.dispatcher.dispatch(StreamScanRequest(code: code));
        await tester.pump();
      }
      await tester.pump();

      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      controller.dispose();
    });

    testWidgets('is hidden while the continuous toggle is off', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = _acceptingController();

      await tester.pumpWidget(
        _buildTestApp(StreamScanCounterComponent(controller: controller)),
      );
      final Finder itemsLabel = find.text(
        '${StreamScanConstants.counterItemsLabel} ',
      );
      controller.dispatcher.dispatch(const StreamScanRequest(code: 'A'));
      await tester.pump();
      await tester.pump();
      expect(itemsLabel, findsOneWidget);

      controller.setContinuousMode(false);
      await tester.pump();
      expect(itemsLabel, findsNothing);

      controller.setContinuousMode(true);
      await tester.pump();
      expect(itemsLabel, findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      controller.dispose();
    });
  });

  group('StreamScanErrorChipComponent', () {
    testWidgets('renders nothing when there are no chips', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = _acceptingController();

      await tester.pumpWidget(
        _buildTestApp(StreamScanErrorChipComponent(controller: controller)),
      );

      expect(find.byIcon(Icons.error_outline_rounded), findsNothing);

      controller.dispose();
    });

    testWidgets('renders the host message only, without retry button', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = _acceptingController();

      controller.errorChips.value = <StreamScanErrorChipItem>[
        StreamScanErrorChipItem(
          id: 'chip_1',
          code: 'ERR_1',
          message: 'Mã không hợp lệ',
          unaddedQuantity: 2,
          timestamp: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(StreamScanErrorChipComponent(controller: controller)),
      );

      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.text('Mã không hợp lệ'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);

      controller.dispose();
    });

    testWidgets('renders info chips with the info icon', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = _acceptingController();

      controller.errorChips.value = <StreamScanErrorChipItem>[
        StreamScanErrorChipItem(
          id: 'info_1',
          code: '',
          message: StreamScanConstants.continuousOnMessage,
          kind: StreamScanChipKind.info,
          timestamp: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(StreamScanErrorChipComponent(controller: controller)),
      );

      expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
      expect(
        find.text(StreamScanConstants.continuousOnMessage),
        findsOneWidget,
      );

      controller.dispose();
    });

    testWidgets('renders success chips with the check icon', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = _acceptingController();

      controller.errorChips.value = <StreamScanErrorChipItem>[
        StreamScanErrorChipItem(
          id: 'success_1',
          code: '',
          message: StreamScanConstants.successToastMessage,
          kind: StreamScanChipKind.success,
          timestamp: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(StreamScanErrorChipComponent(controller: controller)),
      );

      expect(find.byIcon(Icons.check_circle_outline_rounded), findsOneWidget);
      expect(
        find.text(StreamScanConstants.successToastMessage),
        findsOneWidget,
      );

      controller.dispose();
    });

    testWidgets('supports error chip customBuilder', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = _acceptingController();

      controller.errorChips.value = <StreamScanErrorChipItem>[
        StreamScanErrorChipItem(
          id: 'chip_cb',
          code: 'CODE_X',
          message: 'Error custom',
          timestamp: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(
          StreamScanErrorChipComponent(
            controller: controller,
            customBuilder:
                (BuildContext context, StreamScanErrorChipItem item) {
                  return Text('CustomChip: ${item.code}');
                },
          ),
        ),
      );

      expect(find.text('CustomChip: CODE_X'), findsOneWidget);

      controller.dispose();
    });
  });

  group('StreamScanSlowNetworkComponent', () {
    testWidgets('renders SizedBox.shrink when isNetworkSlow is false', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = _acceptingController();

      await tester.pumpWidget(
        _buildTestApp(StreamScanSlowNetworkComponent(controller: controller)),
      );

      expect(find.byType(StreamScanSlowNetworkComponent), findsOneWidget);
      expect(
        find.byKey(const ValueKey('slow_network_indicator')),
        findsNothing,
      );

      controller.dispose();
    });

    testWidgets('renders slow network indicator when isNetworkSlow is true', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = _acceptingController();

      controller.isNetworkSlow.value = true;

      await tester.pumpWidget(
        _buildTestApp(StreamScanSlowNetworkComponent(controller: controller)),
      );

      expect(
        find.text(StreamScanConstants.defaultSlowNetworkMessage),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      controller.dispose();
    });

    testWidgets('supports slow network customBuilder', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = _acceptingController();

      controller.isNetworkSlow.value = true;

      await tester.pumpWidget(
        _buildTestApp(
          StreamScanSlowNetworkComponent(
            controller: controller,
            customBuilder: (BuildContext context) {
              return const Text('Mạng rất chậm');
            },
          ),
        ),
      );

      expect(find.text('Mạng rất chậm'), findsOneWidget);

      controller.dispose();
    });
  });

  group('StreamScanPage', () {
    testWidgets('shows spec layout: toggle, no card, no counter, no finish', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = _acceptingController();
      await _openPage(tester, controller);

      expect(
        find.text(StreamScanConstants.continuousToggleLabel),
        findsOneWidget,
      );
      expect(find.byType(StreamScanCounterComponent), findsOneWidget);
      expect(
        find.text('${StreamScanConstants.counterItemsLabel} '),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(StreamScanResultCardComponent),
          matching: find.byType(Stack),
        ),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('stream_scan_finish_btn')),
        findsNothing,
      );

      controller.dispose();
    });

    testWidgets('back leaves at once, without asking, even after scanning', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = _acceptingController();
      final List<StreamScanExitReason?> results = await _openPage(
        tester,
        controller,
      );

      controller.dispatcher.dispatch(const StreamScanRequest(code: 'P1'));
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey<String>('stream_scan_back_btn')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(StreamScanPage), findsNothing);
      expect(results, <StreamScanExitReason?>[StreamScanExitReason.back]);

      controller.dispose();
    });

    testWidgets('tapping the product card exits with cardTap', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = _acceptingController();
      final List<StreamScanExitReason?> results = await _openPage(
        tester,
        controller,
      );

      controller.dispatcher.dispatch(const StreamScanRequest(code: 'P1'));
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey<String>('stream_scan_card_tap')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(StreamScanPage), findsNothing);
      expect(results, <StreamScanExitReason?>[StreamScanExitReason.cardTap]);

      controller.dispose();
    });

    testWidgets('scanStream reports cardTap and keeps accepted quantities', (
      WidgetTester tester,
    ) async {
      StreamScanSession? session;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              return ElevatedButton(
                onPressed: () async {
                  session = await SmartScanner.scanStream(
                    context,
                    onScan: (StreamScanRequest req) async =>
                        const StreamScanResponse.accept(),
                  );
                },
                child: const Text('Mở scanStream'),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Mở scanStream'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final StreamScanPageState state = tester.state<StreamScanPageState>(
        find.byType(StreamScanPage),
      );
      state.controller.dispatcher.dispatch(
        const StreamScanRequest(code: 'P1', quantity: 2),
      );
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey<String>('stream_scan_card_tap')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(StreamScanPage), findsNothing);
      expect(session!.exitReason, StreamScanExitReason.cardTap);
      final StreamScanSummary summary = await session!.drained;
      expect(summary.acceptedByCode, <String, int>{'P1': 2});
    });

    testWidgets(
      'popping route with Navigator.pop() while onScan is in-flight leaves drained incomplete until onScan completes',
      (WidgetTester tester) async {
        final Completer<StreamScanResponse> completer =
            Completer<StreamScanResponse>();
        StreamScanSession? capturedSession;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (BuildContext context) {
                return ElevatedButton(
                  onPressed: () async {
                    capturedSession = await SmartScanner.scanStream(
                      context,
                      onScan: (StreamScanRequest req) => completer.future,
                    );
                  },
                  child: const Text('Mở scanStream'),
                );
              },
            ),
          ),
        );

        // Open scanStream.
        await tester.tap(find.text('Mở scanStream'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(StreamScanPage), findsOneWidget);

        // Access the state's controller and dispatch a scan so onScan runs.
        final StreamScanPageState state = tester.state<StreamScanPageState>(
          find.byType(StreamScanPage),
        );
        final StreamScanController pageController = state.controller;
        pageController.dispatcher.dispatch(
          const StreamScanRequest(code: 'PENDING_1', quantity: 2),
        );
        await tester.pump();

        // Close route with Navigator.pop(context) without passing any result.
        final BuildContext pageContext = tester.element(
          find.byType(StreamScanPage),
        );
        Navigator.of(pageContext).pop();
        await tester.pumpAndSettle();

        // Screen is closed and session was returned by SmartScanner.scanStream.
        expect(find.byType(StreamScanPage), findsNothing);
        expect(capturedSession, isNotNull);
        // Host-initiated close counts as a plain back.
        expect(capturedSession!.exitReason, StreamScanExitReason.back);

        // drained MUST NOT be completed yet because onScan is still awaiting completer!
        bool isDrainedDone = false;
        unawaited(
          capturedSession!.drained.then((_) {
            isDrainedDone = true;
          }),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(isDrainedDone, isFalse);

        // Now complete onScan.
        completer.complete(const StreamScanResponse.accept(title: 'Item'));
        await tester.pump(const Duration(milliseconds: 100));

        // Now drained must complete with correct summary!
        final StreamScanSummary summary = await capturedSession!.drained;
        expect(isDrainedDone, isTrue);
        expect(summary.acceptedQuantity, 2);
        expect(summary.notAddedQuantity, 0);
        expect(summary.acceptedByCode, <String, int>{'PENDING_1': 2});
      },
    );
  });
}
