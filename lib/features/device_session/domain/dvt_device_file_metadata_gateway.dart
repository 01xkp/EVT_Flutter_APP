import 'device_file.dart';

/// The immutable triple that authorizes the V1.6 DVT device-side delete.
///
/// The App must build this only after the local file CRC has matched the
/// metadata and the archive gateway has confirmed durable cloud persistence.
class DvtDeviceArchiveConfirmation {
  const DvtDeviceArchiveConfirmation({
    required this.nameSlot,
    required this.fileSize,
    required this.crc32,
  });

  final List<int> nameSlot;
  final int fileSize;
  final int crc32;

  /// V1.6 fixes `ArchiveResult` to one for the only App-issued confirmation.
  static const archiveResult = 1;
}

/// The only successful V1.6 `ARCHIVE_CONFIRM` outcomes.
class DvtDeviceArchiveConfirmationResult {
  const DvtDeviceArchiveConfirmationResult(this.state);

  final DvtDeviceFileState state;

  bool get deviceDeleted => state == DvtDeviceFileState.deleted;

  bool get retainedForRecovery => state == DvtDeviceFileState.reclaimable;

  bool get isTerminal => state.isArchiveConfirmationTerminal;
}

/// DVT-only boundary for `0x26` file metadata and controlled deletion.
///
/// The implementation belongs to the later-stage DVT command path. The shared
/// serialized command client may carry `0x26` only after the DVT session gate
/// has admitted FF16 and its Indicate subscription.
abstract interface class DvtDeviceFileMetadataGateway {
  Future<DvtDeviceFileMetadata> readDvtFileMetadata({
    required List<int> nameSlot,
  });

  Future<DvtDeviceArchiveConfirmationResult> confirmDvtArchive({
    required DvtDeviceArchiveConfirmation confirmation,
  });
}
