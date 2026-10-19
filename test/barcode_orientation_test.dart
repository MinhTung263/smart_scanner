import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:smart_scanner/src/data/services/barcode_scanner_service.dart';

void main() {
  group('Android back-camera image rotation', () {
    const sensorOrientation = 90;

    final expectedRotations = {
      DeviceOrientation.portraitUp: InputImageRotation.rotation90deg,
      DeviceOrientation.landscapeLeft: InputImageRotation.rotation0deg,
      DeviceOrientation.portraitDown: InputImageRotation.rotation270deg,
      DeviceOrientation.landscapeRight: InputImageRotation.rotation180deg,
    };

    for (final entry in expectedRotations.entries) {
      test('${entry.key.name} maps to ${entry.value.name}', () {
        final rotation = BarcodeScannerService.inputImageRotation(
          sensorOrientation: sensorOrientation,
          lensDirection: CameraLensDirection.back,
          deviceOrientation: entry.key,
          isIOS: false,
        );

        expect(rotation, entry.value);
      });
    }
  });
}
