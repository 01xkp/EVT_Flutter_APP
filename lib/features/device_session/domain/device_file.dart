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

/// File states carried by the V1.6 DVT `0x26 / GET_META` response.
///
/// `deviceConfirmedLegacy` is intentionally represented so a real device
/// response can be decoded for diagnostics, but it is not a successful DVT
/// archive-confirmation result. V1.6 accepts only [reclaimable] and [deleted]
/// after cloud persistence.
enum DvtDeviceFileState {
  writing(0),
  ready(1),
  syncing(2),
  deviceConfirmedLegacy(3),
  reclaimable(4),
  error(5),
  deleted(6);

  const DvtDeviceFileState(this.wireValue);

  final int wireValue;

  static DvtDeviceFileState fromWireValue(int value) {
    for (final state in values) {
      if (state.wireValue == value) {
        return state;
      }
    }
    throw FormatException('DVT 文件状态无效：$value。');
  }

  bool get canDownload => this == ready;

  bool get isArchiveConfirmationTerminal =>
      this == reclaimable || this == deleted;
}

/// Immutable metadata returned by the V1.6 DVT `0x26 / GET_META` operation.
///
/// V1.6 removed the V1.5 `DurationS` field. The payload is therefore exactly
/// 41 bytes and duration is deliberately absent from this model.
class DvtDeviceFileMetadata {
  const DvtDeviceFileMetadata({
    required this.name,
    required this.nameSlot,
    required this.startUtc,
    required this.recordingSessionId,
    required this.segmentIndex,
    required this.clockQuality,
    required this.utcCorrectionMilliseconds,
    required this.fileSize,
    required this.crc32,
    required this.state,
  });

  final String name;
  final List<int> nameSlot;
  final DateTime startUtc;
  final int recordingSessionId;
  final int segmentIndex;
  final int clockQuality;
  final int utcCorrectionMilliseconds;
  final int fileSize;
  final int crc32;
  final DvtDeviceFileState state;

  bool matchesListedFile(DeviceFile file) =>
      file.length == fileSize && _sameBytes(file.nameSlot, nameSlot);

  bool matchesArchiveTriple({
    required List<int> otherNameSlot,
    required int otherFileSize,
    required int otherCrc32,
  }) =>
      fileSize == otherFileSize &&
      crc32 == otherCrc32 &&
      _sameBytes(nameSlot, otherNameSlot);
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
