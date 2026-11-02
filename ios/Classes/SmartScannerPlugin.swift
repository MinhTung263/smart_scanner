import Flutter
import UIKit

@objc
public class SmartScannerPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    // Registered as an iOS plugin so smart_scanner.podspec automatically
    // configures MLKit build settings and Apple Silicon Simulator compatibility.
  }
}

