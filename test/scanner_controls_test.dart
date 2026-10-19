import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scanner/src/presentation/widgets/scanner_controls.dart';

void main() {
  testWidgets('zoom button cycles through 1.5x after starting at 1x', (
    tester,
  ) async {
    double zoom = 1.0;

    Widget buildTopBar() {
      return MaterialApp(
        home: Scaffold(
          body: ScannerTopBar(
            currentZoom: zoom,
            onZoomChanged: (value) => zoom = value,
          ),
        ),
      );
    }

    await tester.pumpWidget(buildTopBar());
    expect(find.text('1x'), findsOneWidget);

    await tester.tap(find.text('1x'));
    await tester.pumpWidget(buildTopBar());
    await tester.pumpAndSettle();

    expect(zoom, 1.5);
    expect(find.text('1.5x'), findsOneWidget);
  });
}
