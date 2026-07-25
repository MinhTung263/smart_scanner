# Smart Scanner

A powerful Flutter package for barcode and QR code scanning, powered by Google ML Kit.

## Features

- High-performance barcode and QR code scanning.
- Built-in UI components (camera preview, custom overlays, glassmorphic design).
- Easy to integrate into any Flutter app.
- Full control over camera and scanning behavior via `ScannerController`.
- Designed for both single scan and continuous scanning use cases.

## Installation

Add `smart_scanner` to your `pubspec.yaml`:

```yaml
dependencies:
  smart_scanner: ^0.0.1
```

## Setup

### iOS
Requires iOS 12.0 or higher. Add the following key to your `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>We need access to your camera to scan barcodes and QR codes.</string>
```

### Android
Minimum SDK version is 21. Ensure your `android/app/build.gradle` has:

```gradle
android {
    defaultConfig {
        minSdkVersion 21
    }
}
```

## Usage

Check out the `smart_scanner_app` directory for a complete working example.
