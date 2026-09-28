import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:smart_scanner/smart_scanner.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SmartScannerSettings.resetForTesting();
  });

  test('vibration is on by default', () async {
    await SmartScannerSettings.load();
    expect(SmartScannerSettings.vibrateOnScan.value, isTrue);
  });

  test('the choice is saved and restored on the next launch', () async {
    await SmartScannerSettings.setVibrateOnScan(false);
    expect(SmartScannerSettings.vibrateOnScan.value, isFalse);

    // Simulate an app restart: in-memory state is gone, storage remains.
    SmartScannerSettings.resetForTesting();
    expect(SmartScannerSettings.vibrateOnScan.value, isTrue);
    await SmartScannerSettings.load();
    expect(SmartScannerSettings.vibrateOnScan.value, isFalse);
  });

  test('a change made while loading is not overwritten by the load', () async {
    await SmartScannerSettings.setVibrateOnScan(true);
    SmartScannerSettings.resetForTesting();

    final loading = SmartScannerSettings.load();
    await SmartScannerSettings.setVibrateOnScan(false);
    await loading;
    expect(SmartScannerSettings.vibrateOnScan.value, isFalse);
  });

  testWidgets('the switch reflects and updates the shared setting', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: SmartScannerVibrationSwitch())),
      ),
    );
    await tester.pump();
    final toggle = find.byType(Switch);
    expect(tester.widget<Switch>(toggle).value, isTrue);

    await tester.tap(toggle);
    await tester.pump();
    expect(SmartScannerSettings.vibrateOnScan.value, isFalse);
    expect(tester.widget<Switch>(toggle).value, isFalse);

    // Changing it from elsewhere (another screen) updates the switch too.
    await SmartScannerSettings.setVibrateOnScan(true);
    await tester.pump();
    expect(tester.widget<Switch>(toggle).value, isTrue);
  });
}
