import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scanner/src/core/constants/stream_scan_constants.dart';
import 'package:smart_scanner/src/presentation/components/stream_scan_error_chip_component.dart';
import 'package:smart_scanner/src/presentation/components/stream_scan_result_card_component.dart';
import 'package:smart_scanner/src/presentation/components/stream_scan_slow_network_component.dart';
import 'package:smart_scanner/src/presentation/controllers/stream_scan_controller.dart';
import 'package:smart_scanner/src/presentation/pages/stream_scan_page.dart';
import 'package:smart_scanner/src/smart_scanner.dart';

Widget _buildTestApp(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  group('StreamScanResultCardComponent', () {
    testWidgets('renders SizedBox.shrink when recentCards is empty', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = StreamScanController(
        onScan: (StreamScanRequest req) async =>
            const StreamScanResponse.accept(),
      );

      await tester.pumpWidget(
        _buildTestApp(StreamScanResultCardComponent(controller: controller)),
      );

      expect(find.byType(StreamScanResultCardComponent), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);

      controller.dispose();
    });

    testWidgets('renders processing card with spinner and pending badge', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = StreamScanController(
        onScan: (StreamScanRequest req) async =>
            const StreamScanResponse.accept(),
      );

      controller.recentCards.value = <StreamScanCardItem>[
        StreamScanCardItem(
          code: 'PROD_100',
          pendingQuantity: 2,
          timestamp: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(StreamScanResultCardComponent(controller: controller)),
      );

      expect(find.text('PROD_100'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('+2 đang xử lý'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('renders accepted card with title, subtitle, and cart count', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = StreamScanController(
        onScan: (StreamScanRequest req) async =>
            const StreamScanResponse.accept(),
      );

      controller.recentCards.value = <StreamScanCardItem>[
        StreamScanCardItem(
          code: '8938505963014',
          title: 'Trà ô long 450ml',
          subtitle: '12.000đ',
          totalInCart: 4,
          acceptedQuantity: 1,
          timestamp: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(StreamScanResultCardComponent(controller: controller)),
      );

      expect(find.text('Trà ô long 450ml'), findsOneWidget);
      expect(find.text('12.000đ'), findsOneWidget);
      expect(find.text('x4'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

      controller.dispose();
    });

    testWidgets('re-scanned product keeps its quantity and shows pending', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = StreamScanController(
        onScan: (StreamScanRequest req) async =>
            const StreamScanResponse.accept(),
      );

      controller.recentCards.value = <StreamScanCardItem>[
        StreamScanCardItem(
          code: 'WATER',
          title: 'Nước suối 500ml',
          totalInCart: 3,
          acceptedQuantity: 3,
          pendingQuantity: 1,
          timestamp: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(StreamScanResultCardComponent(controller: controller)),
      );

      expect(find.text('x3'), findsOneWidget);
      expect(find.text('+1 đang xử lý'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      controller.dispose();
    });

    testWidgets('stacks layers with the most recent scan in front', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = StreamScanController(
        onScan: (StreamScanRequest req) async =>
            const StreamScanResponse.accept(),
      );

      // recentCards is ordered most recent first.
      controller.recentCards.value = <StreamScanCardItem>[
        StreamScanCardItem(code: 'NEWEST', timestamp: DateTime.now()),
        StreamScanCardItem(code: 'MIDDLE', timestamp: DateTime.now()),
        StreamScanCardItem(code: 'OLDEST', timestamp: DateTime.now()),
      ];

      await tester.pumpWidget(
        _buildTestApp(StreamScanResultCardComponent(controller: controller)),
      );

      final List<AnimatedPositioned> layers = tester
          .widgetList<AnimatedPositioned>(find.byType(AnimatedPositioned))
          .toList();
      expect(layers.length, 3);

      // Painted back to front: the newest layer is the last child.
      expect(layers.last.key, const ValueKey<String>('layer_NEWEST'));
      expect(layers.first.key, const ValueKey<String>('layer_OLDEST'));

      // Front layer anchored lowest and full width; older layers peek above.
      const double offset = StreamScanConstants.layerOffsetY;
      expect(layers.last.top, 2 * offset);
      expect(layers.last.left, 0.0);
      expect(layers.first.top, 0.0);
      expect(layers.first.left, 2 * StreamScanConstants.layerInsetX);

      controller.dispose();
    });

    testWidgets('renders up to maxVisibleCards items', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = StreamScanController(
        options: const StreamScanOptions(maxVisibleCards: 2),
        onScan: (StreamScanRequest req) async =>
            const StreamScanResponse.accept(),
      );

      controller.recentCards.value = <StreamScanCardItem>[
        StreamScanCardItem(code: 'C_1', timestamp: DateTime.now()),
        StreamScanCardItem(code: 'C_2', timestamp: DateTime.now()),
        StreamScanCardItem(code: 'C_3', timestamp: DateTime.now()),
      ];

      await tester.pumpWidget(
        _buildTestApp(StreamScanResultCardComponent(controller: controller)),
      );

      expect(find.text('C_1'), findsOneWidget);
      expect(find.text('C_2'), findsOneWidget);
      expect(find.text('C_3'), findsNothing);

      controller.dispose();
    });

    testWidgets('supports customBuilder override', (WidgetTester tester) async {
      final StreamScanController controller = StreamScanController(
        onScan: (StreamScanRequest req) async =>
            const StreamScanResponse.accept(),
      );

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

  group('StreamScanErrorChipComponent', () {
    testWidgets('renders SizedBox.shrink when errorChips is empty', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = StreamScanController(
        onScan: (StreamScanRequest req) async =>
            const StreamScanResponse.accept(),
      );

      await tester.pumpWidget(
        _buildTestApp(StreamScanErrorChipComponent(controller: controller)),
      );

      expect(find.byType(StreamScanErrorChipComponent), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);

      controller.dispose();
    });

    testWidgets('renders error chip with message without retry button', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = StreamScanController(
        onScan: (StreamScanRequest req) async =>
            const StreamScanResponse.accept(),
      );

      controller.errorChips.value = <StreamScanErrorChipItem>[
        StreamScanErrorChipItem(
          id: 'chip_1',
          code: 'ERR_1',
          message: 'Không tìm thấy mã',
          unaddedQuantity: 2,
          timestamp: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(StreamScanErrorChipComponent(controller: controller)),
      );

      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(
        find.text(
          '⚠ Không tìm thấy mã · 2 SP (ERR_1) chưa thêm vào giỏ, hãy quét lại',
        ),
        findsOneWidget,
      );
      // No retry button should be present.
      expect(find.byType(TextButton), findsNothing);

      controller.dispose();
    });

    testWidgets('supports error chip customBuilder', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = StreamScanController(
        onScan: (StreamScanRequest req) async =>
            const StreamScanResponse.accept(),
      );

      controller.errorChips.value = <StreamScanErrorChipItem>[
        StreamScanErrorChipItem(
          id: 'chip_cb',
          code: 'CODE_X',
          message: 'Error custom',
          unaddedQuantity: 1,
          timestamp: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        _buildTestApp(
          StreamScanErrorChipComponent(
            controller: controller,
            customBuilder: (
              BuildContext context,
              StreamScanErrorChipItem item,
            ) {
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
      final StreamScanController controller = StreamScanController(
        onScan: (StreamScanRequest req) async =>
            const StreamScanResponse.accept(),
      );

      await tester.pumpWidget(
        _buildTestApp(StreamScanSlowNetworkComponent(controller: controller)),
      );

      expect(find.byType(StreamScanSlowNetworkComponent), findsOneWidget);
      expect(find.byKey(const ValueKey('slow_network_indicator')), findsNothing);

      controller.dispose();
    });

    testWidgets('renders slow network indicator when isNetworkSlow is true', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = StreamScanController(
        onScan: (StreamScanRequest req) async =>
            const StreamScanResponse.accept(),
      );

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
      final StreamScanController controller = StreamScanController(
        onScan: (StreamScanRequest req) async =>
            const StreamScanResponse.accept(),
      );

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
    testWidgets('renders page structure and finish button pops', (
      WidgetTester tester,
    ) async {
      final StreamScanController controller = StreamScanController(
        onScan: (StreamScanRequest req) async =>
            const StreamScanResponse.accept(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              return ElevatedButton(
                onPressed: () async {
                  await Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (BuildContext ctx) => StreamScanPage(
                        controller: controller,
                        onScan: (StreamScanRequest req) async =>
                            const StreamScanResponse.accept(),
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

      // Open scanner page.
      await tester.tap(find.text('Mở Scanner'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(StreamScanPage), findsOneWidget);
      expect(
        find.text(StreamScanConstants.defaultFinishButtonText),
        findsOneWidget,
      );

      // Tap finish button.
      await tester.tap(
        find.text(StreamScanConstants.defaultFinishButtonText),
      );
      await tester.pumpAndSettle();

      expect(find.byType(StreamScanPage), findsNothing);

      controller.dispose();
    });

    testWidgets('back button pops', (WidgetTester tester) async {
      final StreamScanController controller = StreamScanController(
        onScan: (StreamScanRequest req) async =>
            const StreamScanResponse.accept(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              return ElevatedButton(
                onPressed: () async {
                  await Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (BuildContext ctx) => StreamScanPage(
                        controller: controller,
                        onScan: (StreamScanRequest req) async =>
                            const StreamScanResponse.accept(),
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

      // Open scanner page.
      await tester.tap(find.text('Mở Scanner'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(StreamScanPage), findsOneWidget);

      // Tap back button overlay in top bar.
      await tester.tap(
        find.byKey(const ValueKey<String>('stream_scan_back_btn')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(StreamScanPage), findsNothing);

      controller.dispose();
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
        final StreamScanPageState state =
            tester.state<StreamScanPageState>(find.byType(StreamScanPage));
        final StreamScanController pageController = state.controller;
        pageController.dispatcher.dispatch(
          const StreamScanRequest(code: 'PENDING_1', quantity: 2),
        );
        await tester.pump();

        // Close route with Navigator.pop(context) without passing any result.
        final BuildContext pageContext = tester.element(find.byType(StreamScanPage));
        Navigator.of(pageContext).pop();
        await tester.pumpAndSettle();

        // Screen is closed and session was returned by SmartScanner.scanStream.
        expect(find.byType(StreamScanPage), findsNothing);
        expect(capturedSession, isNotNull);

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
      },
    );
  });
}
