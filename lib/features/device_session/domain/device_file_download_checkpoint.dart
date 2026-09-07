import 'dart:convert';

enum DeviceFileDownloadPhase { downloading, readyForArchive }

class DeviceFileDownloadCheckpoint {
  const DeviceFileDownloadCheckpoint({
    required this.id,
    required this.deviceId,
    required this.nameSlot,
    required this.recordingId,
    required this.expectedLength,
    required this.expectedCrc32,
    required this.receivedBytes,
    required this.updatedAt,
    this.phase = DeviceFileDownloadPhase.downloading,
  });

  final String id;
  final String deviceId;
  final List<int> nameSlot;
  final String recordingId;
  final int expectedLength;
  final int expectedCrc32;
  final int receivedBytes;
  final DateTime updatedAt;
  final DeviceFileDownloadPhase phase;

  static String idFor({required String deviceId, required List<int> nameSlot}) {
    return '$deviceId:${base64Url.encode(nameSlot)}';
  }

  bool matches({required int length, required int crc32}) {
    return expectedLength == length && expectedCrc32 == crc32;
  }

  DeviceFileDownloadCheckpoint copyWith({
    int? receivedBytes,
    DateTime? updatedAt,
    DeviceFileDownloadPhase? phase,
  }) {
    return DeviceFileDownloadCheckpoint(
      id: id,
      deviceId: deviceId,
      nameSlot: nameSlot,
      recordingId: recordingId,
      expectedLength: expectedLength,
      expectedCrc32: expectedCrc32,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      updatedAt: updatedAt ?? this.updatedAt,
      phase: phase ?? this.phase,
    );
  }
}
