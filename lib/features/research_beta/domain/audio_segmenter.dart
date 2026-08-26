class AudioSegmentationRequest {
  const AudioSegmentationRequest({
    required this.sourcePath,
    required this.outputPathPrefix,
    required this.maximumSegmentDuration,
  });

  final String sourcePath;
  final String outputPathPrefix;
  final Duration maximumSegmentDuration;
}

class AudioSegment {
  const AudioSegment({required this.index, required this.duration})
    : assert(index >= 0);

  final int index;
  final Duration duration;
}

abstract interface class AudioSegmenter {
  Future<List<AudioSegment>> splitM4a(AudioSegmentationRequest request);
}
