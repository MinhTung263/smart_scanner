# Smart Scanner

A high-performance, battery & heat-optimized Flutter package for Barcode and QR Code scanning, powered by Google ML Kit and optimized for mobile devices and Android POS terminals (Sunmi V3, Honeywell, Zebra, etc.).

[![pub package](https://img.shields.io/pub/v/smart_scanner.svg)](https.pub.dev/packages/smart_scanner)

## Key Features

- ⚡ **High-Performance Scanning**: Powered by Google ML Kit with zero-allocation memory buffers (50+ FPS active UI performance).
- ❄️ **Battery & Thermal Efficiency**:
  - **720p Optimized Stream**: Cuts pixel processing and memory channel transfer load by >50%.
  - **Adaptive Throttling**: Automatically backs off frame decoding to ~4 FPS when stationary, springing instantly back to 50 FPS on motion.
  - **Auto-Sleep / Inactivity Pause**: Pauses camera stream after 60s of idle time with a tap-to-resume glassmorphism overlay.
- 🎯 **Modern Top AppBar Controls**:
  - **Single-Tap Cycle Zoom**: Centered `1x` ➔ `2x` ➔ `3x` ➔ `1x` cycle button with a modern viewfinder lens icon (`Icons.center_focus_strong_rounded`).
  - **Amber Glow Flash Button**: Modern minimalist bolt icon with soft golden glow when active.
- 🔍 **Adaptive Contrast Enhancement**: Auto-stretches low-contrast image frames to detect small or washed-out 1D/2D barcodes.
- 📱 **POS & Sunmi V3 Hardware Ready**: Supports physical haptic vibration feedback on Sunmi V3 and Android POS devices.
- 📦 **Multi-Scan & Single Scan**: Built-in UI for single scan return or multi-item inventory scanning.
- 🖼️ **Gallery Image Picker**: Scan barcodes directly from photos in the gallery.

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

## Usage

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

## License

MIT License
