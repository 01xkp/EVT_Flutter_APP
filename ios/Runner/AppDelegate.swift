import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let audioChannel = FlutterMethodChannel(
      name: "com.aigutta.aipin/audio-segmentation",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    audioChannel.setMethodCallHandler { call, result in
      guard call.method == "splitM4a",
            let arguments = call.arguments as? [String: Any],
            let sourcePath = arguments["sourcePath"] as? String,
            let outputPathPrefix = arguments["outputPathPrefix"] as? String,
            let maximumSegmentMilliseconds = arguments["maximumSegmentMilliseconds"] as? Int else {
        result(FlutterMethodNotImplemented)
        return
      }
      M4aAudioSegmenter().split(
        sourcePath: sourcePath,
        outputPathPrefix: outputPathPrefix,
        maximumSegmentMilliseconds: maximumSegmentMilliseconds
      ) { segmentationResult in
        DispatchQueue.main.async {
          switch segmentationResult {
          case .success(let segments):
            result(segments)
          case .failure(let error):
            result(FlutterError(
              code: "audio_segmentation_failed",
              message: error.localizedDescription,
              details: nil
            ))
          }
        }
      }
    }
  }
}
