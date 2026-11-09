import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:smart_scanner/src/core/constants/stream_scan_constants.dart';
import 'package:smart_scanner/src/domain/entities/stream_scan_validator.dart';

bool _valid(String code, BarcodeFormat format) =>
    StreamScanValidators.isGs1CheckDigitValid(code, format);

void main() {
  group('GS1 check digit', () {
    test('EAN-13 accepts a correct check digit and rejects a wrong one', () {
      expect(_valid('4006381333931', BarcodeFormat.ean13), isTrue);
      expect(_valid('8935049510013', BarcodeFormat.ean13), isFalse);
      expect(_valid('4006381333932', BarcodeFormat.ean13), isFalse);
    });

    test('EAN-13 rejects wrong length and non-digits', () {
      expect(_valid('400638133393', BarcodeFormat.ean13), isFalse);
      expect(_valid('40063813339A1', BarcodeFormat.ean13), isFalse);
    });

    test('EAN-8', () {
      expect(_valid('96385074', BarcodeFormat.ean8), isTrue);
      expect(_valid('96385075', BarcodeFormat.ean8), isFalse);
    });

    test('UPC-A', () {
      expect(_valid('036000291452', BarcodeFormat.upca), isTrue);
      expect(_valid('036000291453', BarcodeFormat.upca), isFalse);
    });

    test('UPC-E is expanded to UPC-A before checking', () {
      // 01234565 expands to UPC-A 012345000065.
      expect(_valid('01234565', BarcodeFormat.upce), isTrue);
      expect(_valid('01234566', BarcodeFormat.upce), isFalse);
      // 04252614 expands to UPC-A 042100005264.
      expect(_valid('04252614', BarcodeFormat.upce), isTrue);
      // Number system must be 0 or 1.
      expect(_valid('21234565', BarcodeFormat.upce), isFalse);
      // Six digits carry no check digit: nothing to verify.
      expect(_valid('123456', BarcodeFormat.upce), isTrue);
    });

    test('ITF-14 is checked, other ITF lengths pass', () {
      expect(_valid('15400141288763', BarcodeFormat.itf), isTrue);
      expect(_valid('15400141288764', BarcodeFormat.itf), isFalse);
      expect(_valid('123456', BarcodeFormat.itf), isTrue);
    });

    test('formats without a GS1 check digit always pass', () {
      expect(_valid('ABC-123', BarcodeFormat.code128), isTrue);
      expect(_valid('ANYTHING', BarcodeFormat.code39), isTrue);
    });
  });

  group('StreamScanValidators', () {
    test('gs1CheckDigit returns the default or custom message', () {
      expect(
        StreamScanValidators.gs1CheckDigit()(
          '4006381333932',
          BarcodeFormat.ean13,
        ),
        StreamScanConstants.invalidCodeMessage,
      );
      expect(
        StreamScanValidators.gs1CheckDigit(message: 'Sai mã')(
          '4006381333932',
          BarcodeFormat.ean13,
        ),
        'Sai mã',
      );
      expect(
        StreamScanValidators.gs1CheckDigit()(
          '4006381333931',
          BarcodeFormat.ean13,
        ),
        isNull,
      );
    });

    test('all returns the first error in order', () {
      final StreamScanValidator rule =
          StreamScanValidators.all(<StreamScanValidator>[
            StreamScanValidators.gs1CheckDigit(),
            (String code, BarcodeFormat format) =>
                code.startsWith('2') ? 'Mã cân chưa hỗ trợ' : null,
          ]);
      expect(rule('4006381333932', BarcodeFormat.ean13), 'Mã không hợp lệ');
      expect(rule('2000000000008', BarcodeFormat.ean13), 'Mã cân chưa hỗ trợ');
      expect(rule('4006381333931', BarcodeFormat.ean13), isNull);
    });
  });
}
