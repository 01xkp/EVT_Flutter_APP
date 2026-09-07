class DeviceFile {
  const DeviceFile({
    required this.name,
    required this.nameSlot,
    required this.length,
  });

  final String name;
  final List<int> nameSlot;
  final int length;
}

class DeviceFileMetadata {
  const DeviceFileMetadata({
    required this.name,
    required this.nameSlot,
    required this.startUtc,
    required this.durationSeconds,
    required this.recordingSessionId,
    required this.segmentIndex,
    required this.clockQuality,
    required this.utcCorrectionMilliseconds,
    required this.length,
    required this.crc32,
    required this.state,
  });

  final String name;
  final List<int> nameSlot;
  final DateTime startUtc;
  final int durationSeconds;
  final int recordingSessionId;
  final int segmentIndex;
  final int clockQuality;
  final int utcCorrectionMilliseconds;
  final int length;
  final int crc32;
  final int state;
}
