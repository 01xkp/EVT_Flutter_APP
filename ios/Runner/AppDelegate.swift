import Flutter
import Foundation
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static let publicDiagnosticLogsChannelName = "aipin/public_diagnostic_logs"
  private var publicDiagnosticLogsChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: Self.publicDiagnosticLogsChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "mirrorCanonicalLog" else {
        result(FlutterMethodNotImplemented)
        return
      }
      Self.mirrorCanonicalLog(call, result: result)
    }
    publicDiagnosticLogsChannel = channel
  }

  private static func mirrorCanonicalLog(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    #if DEBUG
      guard
        let arguments = call.arguments as? [String: Any],
        let sourcePath = arguments["sourcePath"] as? String,
        let filename = arguments["filename"] as? String,
        !sourcePath.isEmpty,
        !filename.isEmpty
      else {
        result(mirrorFailure("invalid_arguments"))
        return
      }

      DispatchQueue.global(qos: .utility).async {
        let response = mirrorCanonicalLogFile(
          sourcePath: sourcePath,
          filename: filename
        )
        DispatchQueue.main.async {
          result(response)
        }
      }
    #else
      result(mirrorFailure("debug_only"))
    #endif
  }

  #if DEBUG
    private static func mirrorCanonicalLogFile(
      sourcePath: String,
      filename: String
    ) -> [String: Any] {
      guard isValidLogFilename(filename) else {
        return mirrorFailure("invalid_filename")
      }

      do {
        let fileManager = FileManager.default
        guard let applicationSupportDirectory = fileManager.urls(
          for: .applicationSupportDirectory,
          in: .userDomainMask
        ).first else {
          return mirrorFailure("storage_error")
        }

        let canonicalApplicationSupportDirectory = canonicalURL(
          applicationSupportDirectory
        )
        let source = canonicalURL(URL(fileURLWithPath: sourcePath))
        guard
          isDescendant(source, of: canonicalApplicationSupportDirectory),
          isValidLogSourceName(source.lastPathComponent, for: filename)
        else {
          return mirrorFailure("invalid_source")
        }

        let sourceValues = try source.resourceValues(forKeys: [.isRegularFileKey])
        guard sourceValues.isRegularFile == true else {
          return mirrorFailure("invalid_source")
        }

        guard let documentsDirectory = fileManager.urls(
          for: .documentDirectory,
          in: .userDomainMask
        ).first else {
          return mirrorFailure("storage_error")
        }
        let canonicalDocumentsDirectory = canonicalURL(documentsDirectory)
        let requestedDestinationDirectory = documentsDirectory
          .appendingPathComponent("AIPIN", isDirectory: true)
          .appendingPathComponent("logs", isDirectory: true)
        try fileManager.createDirectory(
          at: requestedDestinationDirectory,
          withIntermediateDirectories: true
        )
        let destinationDirectory = canonicalURL(requestedDestinationDirectory)
        guard isDescendant(destinationDirectory, of: canonicalDocumentsDirectory) else {
          return mirrorFailure("invalid_destination")
        }

        let destination = destinationDirectory.appendingPathComponent(filename)
        let temporaryDestination = destinationDirectory.appendingPathComponent(
          ".aipin-log-\(UUID().uuidString).tmp"
        )
        defer {
          try? fileManager.removeItem(at: temporaryDestination)
        }

        try fileManager.copyItem(at: source, to: temporaryDestination)
        var destinationIsDirectory: ObjCBool = false
        if fileManager.fileExists(
          atPath: destination.path,
          isDirectory: &destinationIsDirectory
        ) {
          guard !destinationIsDirectory.boolValue else {
            return mirrorFailure("invalid_destination")
          }
          try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporaryDestination, to: destination)
        return mirrorSuccess("Documents/AIPIN/logs/\(filename)")
      } catch {
        return mirrorFailure("storage_error")
      }
    }

    private static func isValidLogFilename(_ filename: String) -> Bool {
      filename.range(
          of: "^aipin-[0-9]{4}-[0-9]{2}-[0-9]{2}(?:-[0-9]{2}-[0-9]{2}-[0-9]{2}(?:-[0-9]+)?)?\\.log(?:\\.[0-9]+)?$",
        options: .regularExpression
      ) != nil
    }

    private static func isValidLogSourceName(_ sourceName: String, for filename: String) -> Bool {
      if sourceName == filename { return true }
      // Rotation copies are immutable while queued for mirroring. Their source
      // slot may differ from the destination slot after the next rotation.
      let stem = filename.components(separatedBy: ".log")[0]
      let escapedStem = NSRegularExpression.escapedPattern(for: stem)
      return sourceName.range(
        of: "^\(escapedStem)\\.log(?:\\.[0-9]+)?\\.mirror-[0-9]+-[0-9]+$",
        options: .regularExpression
      ) != nil
    }

    private static func canonicalURL(_ url: URL) -> URL {
      url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
    }

    private static func isDescendant(_ candidate: URL, of directory: URL) -> Bool {
      candidate.pathComponents.starts(with: directory.pathComponents)
    }
  #endif

  private static func mirrorSuccess(_ relativePath: String) -> [String: Any] {
    [
      "available": true,
      "relativePath": relativePath,
      "lastUpdatedAtEpochMilliseconds": Int(Date().timeIntervalSince1970 * 1000),
    ]
  }

  private static func mirrorFailure(_ code: String) -> [String: Any] {
    [
      "available": false,
      "failureCode": code,
    ]
  }
}
