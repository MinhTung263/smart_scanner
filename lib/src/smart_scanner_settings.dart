import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide scanner preferences, saved on the device.
///
/// Every scan opened through [SmartScanner] follows these unless the call
/// overrides them explicitly, so a toggle placed anywhere in the host app —
/// e.g. [SmartScannerVibrationSwitch] on a settings screen — applies to all
/// scanners at once and survives app restarts.
class SmartScannerSettings {
  SmartScannerSettings._();

  static const _vibrateOnScanKey = 'smart_scanner.vibrate_on_scan';

  static final ValueNotifier<bool> _vibrateOnScan = ValueNotifier(true);
  static Future<void>? _loading;
  static bool _changedLocally = false;

  /// Whether the phone vibrates when a code is scanned. `true` until a saved
  /// value has been loaded; listen to it to rebuild UI on changes.
  static ValueListenable<bool> get vibrateOnScan => _vibrateOnScan;

  /// Loads the saved preferences. Runs automatically when a scanner or a
  /// settings widget from this package is first shown; call it yourself (e.g.
  /// in `main`) only if you read [vibrateOnScan] before that. Safe to call
  /// any number of times.
  static Future<void> load() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      final saved = await SharedPreferencesAsync().getBool(_vibrateOnScanKey);
      // A change made while loading is newer than what was on disk.
      if (saved != null && !_changedLocally) _vibrateOnScan.value = saved;
    } catch (_) {
      // No persistent storage available: keep the defaults.
    }
  }

  /// Turns scan vibration on or off for every scanner and saves the choice.
  static Future<void> setVibrateOnScan(bool value) async {
    _changedLocally = true;
    _vibrateOnScan.value = value;
    try {
      await SharedPreferencesAsync().setBool(_vibrateOnScanKey, value);
    } catch (_) {
      // Still applies for this session even if it couldn't be saved.
    }
  }

  /// Forgets in-memory state so the next [load] reads storage again.
  @visibleForTesting
  static void resetForTesting() {
    _loading = null;
    _changedLocally = false;
    _vibrateOnScan.value = true;
  }
}
