#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
#

# Auto-configure CocoaPods in host projects so consumers of smart_scanner do not
# need manual Podfile workarounds for:
# 1. iOS 15.5 minimum deployment target required by google_mlkit_barcode_scanning
# 2. GTMSessionFetcher/Core version lock conflicts with Firebase
# 3. Apple Silicon (arm64) iOS Simulator builds (MLImage & MLKit* fat frameworks
#    only ship device arm64 + intel x86_64 simulator slices and inject
#    EXCLUDED_ARCHS[sdk=iphonesimulator*] = arm64 into Pods-Runner).
if defined?(Pod::Config) && defined?(Pod::Installer) && !defined?(SmartScannerCocoaPodsHook)
  module SmartScannerCocoaPodsHook
    MIN_IOS_VERSION = '15.5'.freeze
    MLKIT_DEVICE_FRAMEWORKS = [
      '-framework "MLImage"',
      '-framework "MLKitBarcodeScanning"',
      '-framework "MLKitCommon"',
      '-framework "MLKitVision"'
    ].freeze

    def self.apply_pre_resolution_fixes!
      config = Pod::Config.instance
      return unless config && config.podfile

      # 1. Ensure all iOS targets in Podfile have deployment target >= 15.5
      config.podfile.target_definition_list.each do |td|
        if td.platform && td.platform.name == :ios && td.platform.deployment_target < Pod::Version.new(MIN_IOS_VERSION)
          td.send(:set_platform, :ios, MIN_IOS_VERSION)
        end
      end

      # 2. Patch plugin sources in .symlinks/plugins
      patch_symlinks_plugins!(config.installation_root.to_s) if config.installation_root
    rescue => _e
      # Never break podspec loading if CocoaPods internals differ
    end

    def self.patch_symlinks_plugins!(ios_root)
      plugins_dir = File.join(ios_root, '.symlinks', 'plugins')
      return unless File.directory?(plugins_dir)

      # Fix flutter_zxing 2.4.0 invalid podspec if present
      zxing_podspec = File.join(plugins_dir, 'flutter_zxing', 'ios', 'flutter_zxing.podspec')
      if File.exist?(zxing_podspec)
        content = File.read(zxing_podspec)
        if content.include?('s.pod_target_xcconfig.merge')
          fixed = content.gsub(
            /s\.pod_target_xcconfig\s*=\s*\{\s*'DEFINES_MODULE'\s*=>\s*'YES',\s*'EXCLUDED_ARCHS\[sdk=iphonesimulator\*\]'\s*=>\s*'i386'\s*\}\s*s\.swift_version\s*=\s*'5\.0'\s*(?:#[^\n]*\n\s*)*s\.pod_target_xcconfig\s*=\s*s\.pod_target_xcconfig\.merge\(\{\s*'GCC_PREPROCESSOR_DEFINITIONS\[config=Release\]'\s*=>\s*'\$\(inherited\) NDEBUG=1',\s*'GCC_PREPROCESSOR_DEFINITIONS\[config=Profile\]'\s*=>\s*'\$\(inherited\) NDEBUG=1',\s*\}\)/m,
            "s.pod_target_xcconfig = {\n    'DEFINES_MODULE' => 'YES',\n    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',\n    'GCC_PREPROCESSOR_DEFINITIONS[config=Release]' => '$(inherited) NDEBUG=1',\n    'GCC_PREPROCESSOR_DEFINITIONS[config=Profile]' => '$(inherited) NDEBUG=1',\n  }\n  s.swift_version = '5.0'"
          )
          File.write(zxing_podspec, fixed) if fixed != content
        end
      end

      # Guard google_mlkit_commons Swift files with #if !targetEnvironment(simulator)
      mlkit_commons_dir = File.join(plugins_dir, 'google_mlkit_commons', 'ios', 'Classes')
      if File.directory?(mlkit_commons_dir)
        ['GenericModelManager.swift', 'MLKVisionImage+FlutterPlugin.swift'].each do |fname|
          fpath = File.join(mlkit_commons_dir, fname)
          next unless File.exist?(fpath)
          fc = File.read(fpath)
          unless fc.include?('targetEnvironment(simulator)')
            File.write(fpath, "#if !targetEnvironment(simulator)\n#{fc}\n#endif\n")
          end
        end

        commons_plugin = File.join(mlkit_commons_dir, 'GoogleMlKitCommonsPlugin.swift')
        if File.exist?(commons_plugin)
          fc = File.read(commons_plugin)
          unless fc.include?('targetEnvironment(simulator)')
            File.write(commons_plugin, fc.gsub('import MLKitVision', "#if !targetEnvironment(simulator)\nimport MLKitVision\n#endif"))
          end
        end
      end

      # Guard google_mlkit_barcode_scanning Swift file with #if targetEnvironment(simulator) stub
      mlkit_barcode_plugin = File.join(plugins_dir, 'google_mlkit_barcode_scanning', 'ios', 'Classes', 'GoogleMlKitBarcodeScanningPlugin.swift')
      if File.exist?(mlkit_barcode_plugin)
        fc = File.read(mlkit_barcode_plugin)
        unless fc.include?('targetEnvironment(simulator)')
          sim_stub = <<~'SWIFT'
            import Flutter
            #if targetEnvironment(simulator)
            @objc
            public class GoogleMlKitBarcodeScanningPlugin: NSObject, FlutterPlugin {
              public static func register(with registrar: FlutterPluginRegistrar) {
                let channel = FlutterMethodChannel(
                  name: "google_mlkit_barcode_scanning",
                  binaryMessenger: registrar.messenger()
                )
                let instance = GoogleMlKitBarcodeScanningPlugin()
                registrar.addMethodCallDelegate(instance, channel: channel)
              }

              public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
                switch call.method {
                case "vision#startBarcodeScanner":
                  result([])
                case "vision#closeBarcodeScanner":
                  result(nil)
                default:
                  result(FlutterMethodNotImplemented)
                }
              }
            }
            #else
            import MLKitVision
          SWIFT
          patched = fc.sub("import Flutter\nimport MLKitVision", sim_stub.chomp) + "\n#endif\n"
          File.write(mlkit_barcode_plugin, patched)
        end
      end
    rescue => _e
    end

    def self.apply_post_integrate_fixes!(installer)
      ios_root = installer.config.installation_root.to_s
      patch_symlinks_plugins!(ios_root)

      # 1. Update Pods project & user projects build settings
      projects = ([installer.pods_project] + installer.aggregate_targets.map(&:user_project)).compact.uniq
      projects.each do |project|
        project.build_configurations.each do |config|
          if config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'].to_f < MIN_IOS_VERSION.to_f
            config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = MIN_IOS_VERSION
          end
          config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'i386'
        end

        project.targets.each do |target|
          target.build_configurations.each do |config|
            if config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'].to_f < MIN_IOS_VERSION.to_f
              config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = MIN_IOS_VERSION
            end
            config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'i386'
          end
        end
        project.save
      end

      # 2. Update all pod target xcconfig files
      support_files_dir = File.join(installer.sandbox.root.to_s, 'Target Support Files')
      if File.directory?(support_files_dir)
        Dir.glob(File.join(support_files_dir, '**', '*.xcconfig')).each do |xcconfig_path|
          next unless File.exist?(xcconfig_path)
          xcconfig = File.read(xcconfig_path)
          updated = xcconfig.dup
          updated.gsub!(/DT_TOOLCHAIN_DIR/, 'TOOLCHAIN_DIR')
          updated.gsub!(/^EXCLUDED_ARCHS\[sdk=iphonesimulator\*\]\s*=.*$/, 'EXCLUDED_ARCHS[sdk=iphonesimulator*] = i386')
          updated.gsub!(/^IPHONEOS_DEPLOYMENT_TARGET\s*=\s*1[0-4]\.\d+\s*$/, "IPHONEOS_DEPLOYMENT_TARGET = #{MIN_IOS_VERSION}")
          updated.gsub!(/^IPHONEOS_DEPLOYMENT_TARGET\s*=\s*15\.[0-4]\s*$/, "IPHONEOS_DEPLOYMENT_TARGET = #{MIN_IOS_VERSION}")
          File.write(xcconfig_path, updated) if updated != xcconfig
        end
      end

      # 3. Update aggregate target xcconfig files (Pods-Runner.*.xcconfig)
      installer.aggregate_targets.each do |target|
        target.xcconfigs.each_key do |config_name|
          xcconfig_path = target.xcconfig_path(config_name)
          next unless File.exist?(xcconfig_path)
          xcconfig = File.read(xcconfig_path)
          updated = xcconfig.dup
          updated.gsub!(/^EXCLUDED_ARCHS\[sdk=iphonesimulator\*\]\s*=.*$/, 'EXCLUDED_ARCHS[sdk=iphonesimulator*] = i386')

          MLKIT_DEVICE_FRAMEWORKS.each do |flag|
            updated.gsub!(" #{flag}", '')
          end
          unless updated.include?('OTHER_LDFLAGS[sdk=iphoneos*]')
            updated << "\nOTHER_LDFLAGS[sdk=iphoneos*] = $(inherited) #{MLKIT_DEVICE_FRAMEWORKS.join(' ')}\n"
          end
          unless updated.include?('${PODS_CONFIGURATION_BUILD_DIR}')
            if updated =~ /^FRAMEWORK_SEARCH_PATHS\s*=/
              updated.gsub!(/^(FRAMEWORK_SEARCH_PATHS\s*=.*)$/, '\1 "${PODS_CONFIGURATION_BUILD_DIR}"')
            else
              updated << "FRAMEWORK_SEARCH_PATHS = $(inherited) \"${PODS_CONFIGURATION_BUILD_DIR}\"\n"
            end
          end

          File.write(xcconfig_path, updated) if updated != xcconfig
        end
      end
    rescue => _e
    end
  end

  SmartScannerCocoaPodsHook.apply_pre_resolution_fixes!

  if defined?(Pod::Installer::Analyzer::LockingDependencyAnalyzer)
    Pod::Installer::Analyzer::LockingDependencyAnalyzer.singleton_class.prepend(
      Module.new do
        def generate_version_locking_dependencies(lockfile, pods_to_update, pods_to_unlock = [])
          SmartScannerCocoaPodsHook.apply_pre_resolution_fixes!
          unlocked = Array(pods_to_update) | ['GTMSessionFetcher']
          super(lockfile, unlocked, pods_to_unlock)
        end
      end
    )
  end

  Pod::Installer.prepend(
    Module.new do
      def integrate
        super
        SmartScannerCocoaPodsHook.apply_post_integrate_fixes!(self)
      end
    end
  )
end

Pod::Spec.new do |s|
  s.name             = 'smart_scanner'
  s.version          = '0.0.3'
  s.summary          = 'A high-performance, battery & heat-optimized Flutter package for Barcode and QR Code scanning.'
  s.description      = <<-DESC
A high-performance, battery & heat-optimized Flutter package for Barcode and QR Code scanning powered by Google ML Kit.
                       DESC
  s.homepage         = 'https://github.com/MinhTung263/smart_scanner'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'MinhTung263' => 'minhtung263@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '15.5'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version = '5.0'
end
