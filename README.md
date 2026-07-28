# Smart Scanner

A high-performance Flutter package for Barcode and QR Code scanning, powered by Google ML Kit and optimized for mobile devices and Android POS terminals (Sunmi V3, Honeywell, Zebra, etc.).

## Features

- **High-Performance Scanning**: Powered by Google ML Kit with zero-allocation memory buffers (60 FPS UI performance).
- **Adaptive Contrast Enhancement**: Auto-stretches low-contrast image frames to detect small or blurry 1D/2D barcodes.
- **POS & Sunmi V3 Hardware Ready**: Supports physical haptic vibration feedback on Sunmi V3 and Android POS devices.
- **Multi-Scan & Single Scan**: Built-in UI for single scan return or multi-item inventory scanning.
- **Gallery Image Picker**: Option to scan barcodes directly from gallery images.

## Setup

### Android

Add the Camera and Vibration permissions to your `android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Required permissions for Camera and Vibration (Sunmi V3 / Android POS) -->
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.VIBRATE" />

    <application ...>
```

Ensure your `android/app/build.gradle` has `minSdkVersion 21`:

```groovy
android {
    defaultConfig {
        minSdkVersion 21
    }
}
```

### iOS

Add the Camera usage description to your `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Ứng dụng cần quyền sử dụng Camera để quét mã vạch và mã QR.</string>
```

## Quick Usage

### 1. Single Barcode Scan

```dart
final result = await SmartScanner.scanBarcode(context);
if (result != null && !result.isMultiScan) {
  print('Barcode: ${result.singleBarcode}');
}
```

### 2. QR Code Scan

```dart
final result = await SmartScanner.scanQR(context);
if (result != null && !result.isMultiScan) {
  print('QR Code: ${result.singleBarcode}');
}
```

### 3. Multi-Scan Mode (Inventory / Stock taking)

```dart
final result = await SmartScanner.scanBarcode(
  context,
  showMultiScanToggle: true,
);

if (result != null && result.isMultiScan) {
  final Map<String, int> barcodes = result.multiBarcodes;
  barcodes.forEach((barcode, count) {
    print('$barcode: $count pcs');
  });
}
```
