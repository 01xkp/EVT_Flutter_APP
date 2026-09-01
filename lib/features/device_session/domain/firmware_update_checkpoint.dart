class FirmwareUpdateCheckpoint {
  const FirmwareUpdateCheckpoint({
    required this.deviceId,
    required this.packageHash,
    required this.offset,
    required this.updatedAt,
  });

  final String deviceId;
  final String packageHash;
  final int offset;
  final DateTime updatedAt;
}

abstract interface class FirmwareUpdateCheckpointRepository {
  Future<FirmwareUpdateCheckpoint?> find(String deviceId);

  Future<void> save(FirmwareUpdateCheckpoint checkpoint);

  Future<void> clear(String deviceId);
}
