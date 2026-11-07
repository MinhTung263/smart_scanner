# Smart Scanner

A high-performance, battery & heat-optimized Flutter package for Barcode and QR Code scanning, powered by Google ML Kit and optimized for mobile devices and Android POS terminals (Sunmi V3, Honeywell, Zebra, etc.).

[![pub package](https://img.shields.io/pub/v/smart_scanner.svg)](https.pub.dev/packages/smart_scanner)

## Key Features

- ⚡ **Stream Scanning Mode (POS Realtime)**: Continuous barcode scanning with instant async callback, intelligent frame-exit deduplication (`RescanPolicy.leaveFrame`), request batch aggregation, and non-blocking background queue drain.
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

### 4. Vibrate-on-Scan Setting

The phone vibrates on each successful scan by default. The choice is an app-wide
setting saved on the device, and every scanner follows it:

```dart
// Drop-in toggle for any settings screen:
ListTile(
  title: const Text('Vibrate on scan'),
  trailing: const SmartScannerVibrationSwitch(),
);

// Or change / read it from code:
await SmartScanner.setVibrateOnScan(false);
final isOn = SmartScanner.vibrateOnScan.value; // a ValueListenable<bool>
```

To force vibration on or off for a single scan regardless of the setting, pass
`enableVibration` (available on `scan`, `scanBarcode`, `scanQR` and `scanBasic`):

```dart
final result = await SmartScanner.scanBarcode(context, enableVibration: false);
```

### 5. Stream Scanning Mode (Realtime POS / Continuous Checkout)

Designed for POS cashier scanning, inventory intake, and continuous barcode dispatch. In this mode, barcodes are streamed to your backend / cache handler immediately in real-time, while the scanner keeps processing new codes without blocking.

#### Key Mechanisms
- **`RescanPolicy.leaveFrame`**: An item is only counted once while held in the frame. To be scanned again, it must physically exit the scan frame for a configurable number of missed frames (`missedFrames: 2` by default) before being recognized as a subsequent item.
- **Batch Aggregation & Sequential Dispatch**: While an asynchronous request for barcode `X` is in flight, any subsequent counts of barcode `X` are automatically aggregated into `quantity`. Calls for the same barcode are processed sequentially, preventing race conditions.
- **Concurrency Limiting**: Supports parallel processing for different barcodes (default `maxConcurrent: 2`).
- **Error Feedback & Rescan**: When `onScan` returns `StreamScanResponse.reject(msg)`, the app vibrates with 2 pulses, displays an auto-dismissing error chip with the exact count of items not added (`req.quantity + queued`), and cancels in-flight pending scans for that barcode so cashiers can re-scan immediately without cooldown or race conditions.
- **Layered Product Cards**: Scanned products appear as stacked layers above the finish button (up to `maxVisibleCards`, default 3), most recent scan in front. A product scanned for the first time adds a new layer; re-scanning a product already in the session slides its layer to the front and, once `onScan` accepts it, shows the new quantity (`totalInCart` from your response, or the session's accepted count if you don't return one). If a re-scan of a product that is already in the cart is rejected, its layer stays at the previous quantity and only the error chip is shown; a product that was never accepted has its layer removed.
- **Background Drain**: When the user taps "Hoàn tất" or navigates back, `await session.drained` ensures all remaining background network requests finish before transitioning to payment, returning the final `StreamScanSummary` (`acceptedQuantity` and `notAddedQuantity`).

#### Code Example

```dart
final StreamScanSession session = await SmartScanner.scanStream(
  context,
  onScan: (StreamScanRequest req) async {
    // 1. Query POS cache or remote API
    final Product? product = posCache.get(req.code) ?? await api.find(req.code);

    if (product == null) {
      return const StreamScanResponse.reject('Không tìm thấy sản phẩm');
    }

    // 2. Add to cart with aggregated quantity
    final bool ok = cart.add(product, quantity: req.quantity);
    if (!ok) {
      return const StreamScanResponse.reject('Không đủ tồn kho');
    }

    // 3. Return accepted status with title, price subtitle, and cart count
    return StreamScanResponse.accept(
      title: product.name,
      subtitle: '${product.price}đ',
      totalInCart: cart.getQuantity(product),
    );
  },
  options: const StreamScanOptions(
    rescanPolicy: RescanPolicy.leaveFrame(missedFrames: 2),
    maxCodesPerFrame: 1,
    maxConcurrent: 2,
    slowHintAfter: Duration(seconds: 3),
  ),
);

// Await any remaining background tasks before navigating to payment:
final StreamScanSummary summary = await session.drained;
print('Accepted: ${summary.acceptedQuantity}, Not added: ${summary.notAddedQuantity}');
```

## License

MIT License
