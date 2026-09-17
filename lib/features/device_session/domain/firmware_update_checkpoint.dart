/// Persistent DVT restart information for a WQOTA transfer.
///
/// The device remains authoritative for the resume window returned by E3, but
/// the App keeps the expected image, offset, window length and image CRC so it
/// can detect a mismatched package after a timeout or connection loss.
enum FirmwareUpdateCheckpointPhase { transferring, awaitingReconnect }

class FirmwareUpdateCheckpoint {
  const FirmwareUpdateCheckpoint({
    required this.deviceId,
    required this.packageHash,
    required this.imageCrc32,
    required this.packageVersion,
    required this.expectedBusinessVersion,
    required this.phase,
    required this.nextOffset,
    required this.nextLength,
    required this.updatedAt,
  });

  final String deviceId;
  final String packageHash;
  final int imageCrc32;
  final int packageVersion;
  final String expectedBusinessVersion;
  final FirmwareUpdateCheckpointPhase phase;
  final int nextOffset;
  final int nextLength;
  final DateTime updatedAt;
}

abstract interface class FirmwareUpdateCheckpointRepository {
  Future<FirmwareUpdateCheckpoint?> find(String deviceId);

  Future<void> save(FirmwareUpdateCheckpoint checkpoint);

  Future<void> clear(String deviceId);
}
