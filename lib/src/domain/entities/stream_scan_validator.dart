import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

import '../../core/constants/stream_scan_constants.dart';

/// Host rule checked before a scan is counted or sent to `onScan`.
/// Returns null when [code] is valid, else the error toast message.
typedef StreamScanValidator =
    String? Function(String code, BarcodeFormat format);

/// Ready-made validators the host may opt into; none is applied by default.
abstract final class StreamScanValidators {
  /// GS1 check digit for EAN-13, EAN-8, UPC-A, UPC-E and ITF-14.
  /// Other formats, and ITF of other lengths, always pass.
  static StreamScanValidator gs1CheckDigit({
    String message = StreamScanConstants.invalidCodeMessage,
  }) {
    return (String code, BarcodeFormat format) =>
        isGs1CheckDigitValid(code, format) ? null : message;
  }

  /// Runs [validators] in order and returns the first error found.
  static StreamScanValidator all(List<StreamScanValidator> validators) {
    final List<StreamScanValidator> rules = List<StreamScanValidator>.of(
      validators,
    );
    return (String code, BarcodeFormat format) {
      for (final StreamScanValidator rule in rules) {
        final String? error = rule(code, format);
        if (error != null) {
          return error;
        }
      }
      return null;
    };
  }

  /// Whether [code] has a correct GS1 check digit for its [format].
  static bool isGs1CheckDigitValid(String code, BarcodeFormat format) {
    switch (format) {
      case BarcodeFormat.ean13:
        return _isGtinValid(code, 13);
      case BarcodeFormat.ean8:
        return _isGtinValid(code, 8);
      case BarcodeFormat.upca:
        return _isGtinValid(code, 12);
      case BarcodeFormat.upce:
        return _isUpcEValid(code);
      case BarcodeFormat.itf:
        // Only ITF-14 carries a GS1 check digit; other ITF lengths pass.
        return code.length != 14 || _isGtinValid(code, 14);
      default:
        return true;
    }
  }

  static final RegExp _digitsOnly = RegExp(r'^\d+$');

  static bool _isGtinValid(String code, int length) {
    if (code.length != length || !_digitsOnly.hasMatch(code)) {
      return false;
    }
    final int expected = _gs1CheckDigit(code.substring(0, length - 1));
    return expected == int.parse(code[length - 1]);
  }

  /// UPC-E is expanded to UPC-A before computing the check digit.
  static bool _isUpcEValid(String code) {
    if (!_digitsOnly.hasMatch(code)) {
      return false;
    }
    // Without number system and check digit there is nothing to verify.
    if (code.length != 8) {
      return code.length == 6 || code.length == 7;
    }
    final String numberSystem = code[0];
    if (numberSystem != '0' && numberSystem != '1') {
      return false;
    }
    final String d = code.substring(1, 7);
    final String body = switch (d[5]) {
      '0' ||
      '1' ||
      '2' => '${d.substring(0, 2)}${d[5]}0000${d.substring(2, 5)}',
      '3' => '${d.substring(0, 3)}00000${d.substring(3, 5)}',
      '4' => '${d.substring(0, 4)}00000${d[4]}',
      _ => '${d.substring(0, 5)}0000${d[5]}',
    };
    return _gs1CheckDigit('$numberSystem$body') == int.parse(code[7]);
  }

  /// Weights 3,1,3,... from the rightmost data digit (GS1 mod 10).
  static int _gs1CheckDigit(String data) {
    int sum = 0;
    for (int i = 0; i < data.length; i++) {
      final int digit = data.codeUnitAt(data.length - 1 - i) - 0x30;
      sum += i.isEven ? digit * 3 : digit;
    }
    return (10 - sum % 10) % 10;
  }
}
