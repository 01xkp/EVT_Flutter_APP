import AVFoundation

final class M4aAudioSegmenter {
  typealias Completion = (Result<[[String: Any]], Error>) -> Void

  func split(
    sourcePath: String,
    outputPathPrefix: String,
    maximumSegmentMilliseconds: Int,
    completion: @escaping Completion
  ) {
    guard maximumSegmentMilliseconds > 0,
          FileManager.default.fileExists(atPath: sourcePath) else {
      completion(.failure(NSError(
        domain: "AIPIN.AudioSegmentation",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Audio source is unavailable"]
      )))
      return
    }
    let asset = AVURLAsset(url: URL(fileURLWithPath: sourcePath))
    asset.loadValuesAsynchronously(forKeys: ["duration"]) { [weak self] in
      guard let self else { return }
      var error: NSError?
      guard asset.statusOfValue(forKey: "duration", error: &error) == .loaded else {
        completion(.failure(error ?? NSError(
          domain: "AIPIN.AudioSegmentation",
          code: 2,
          userInfo: [NSLocalizedDescriptionKey: "Unable to read audio duration"]
        )))
        return
      }
      let durationSeconds = CMTimeGetSeconds(asset.duration)
      guard durationSeconds.isFinite, durationSeconds > 0 else {
        completion(.failure(NSError(
          domain: "AIPIN.AudioSegmentation",
          code: 3,
          userInfo: [NSLocalizedDescriptionKey: "Audio duration is unavailable"]
        )))
        return
      }
      self.exportNextSegment(
        asset: asset,
        totalDurationSeconds: durationSeconds,
        maximumSegmentSeconds: Double(maximumSegmentMilliseconds) / 1000,
        outputPathPrefix: outputPathPrefix,
        startSeconds: 0,
        index: 0,
        outputs: [],
        completion: completion
      )
    }
  }

  private func exportNextSegment(
    asset: AVAsset,
    totalDurationSeconds: Double,
    maximumSegmentSeconds: Double,
    outputPathPrefix: String,
    startSeconds: Double,
    index: Int,
    outputs: [[String: Any]],
    completion: @escaping Completion
  ) {
    guard startSeconds < totalDurationSeconds else {
      completion(.success(outputs))
      return
    }
    let durationSeconds = min(maximumSegmentSeconds, totalDurationSeconds - startSeconds)
    let outputURL = URL(fileURLWithPath: "\(outputPathPrefix)\(String(format: "%04d", index)).m4a")
    let directoryURL = outputURL.deletingLastPathComponent()
    do {
      try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
      if FileManager.default.fileExists(atPath: outputURL.path) {
        try FileManager.default.removeItem(at: outputURL)
      }
    } catch {
      completion(.failure(error))
      return
    }
    guard let exportSession = AVAssetExportSession(
      asset: asset,
      presetName: AVAssetExportPresetPassthrough
    ) else {
      completion(.failure(NSError(
        domain: "AIPIN.AudioSegmentation",
        code: 4,
        userInfo: [NSLocalizedDescriptionKey: "Unable to create audio export"]
      )))
      return
    }
    exportSession.outputURL = outputURL
    exportSession.outputFileType = .m4a
    exportSession.timeRange = CMTimeRange(
      start: CMTime(seconds: startSeconds, preferredTimescale: 1000),
      duration: CMTime(seconds: durationSeconds, preferredTimescale: 1000)
    )
    exportSession.exportAsynchronously { [weak self] in
      DispatchQueue.main.async {
        guard let self else { return }
        guard exportSession.status == .completed else {
          try? FileManager.default.removeItem(at: outputURL)
          completion(.failure(exportSession.error ?? NSError(
            domain: "AIPIN.AudioSegmentation",
            code: 5,
            userInfo: [NSLocalizedDescriptionKey: "Unable to export audio segment"]
          )))
          return
        }
        var nextOutputs = outputs
        nextOutputs.append([
          "index": index,
          "durationMilliseconds": max(1, Int((durationSeconds * 1000).rounded()))
        ])
        self.exportNextSegment(
          asset: asset,
          totalDurationSeconds: totalDurationSeconds,
          maximumSegmentSeconds: maximumSegmentSeconds,
          outputPathPrefix: outputPathPrefix,
          startSeconds: startSeconds + durationSeconds,
          index: index + 1,
          outputs: nextOutputs,
          completion: completion
        )
      }
    }
  }
}
