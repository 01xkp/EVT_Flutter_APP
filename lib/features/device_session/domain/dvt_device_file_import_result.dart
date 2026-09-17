import 'package:aipin/features/device_session/domain/device_file.dart';
import 'package:aipin/features/device_session/domain/device_file_download_checkpoint.dart';
import 'package:aipin/features/device_session/domain/dvt_device_file_metadata_gateway.dart';
import 'package:aipin/features/local_recording/domain/local_recording.dart';
import 'package:aipin/features/local_recording/domain/recording_file_store.dart';

/// A locally saved and CRC-validated DVT file, ready for a separate archive
/// action. Constructing this result never means that cloud persistence or
/// device-side deletion has happened.
class DvtDeviceFileImportResult {
  const DvtDeviceFileImportResult({
    required this.recording,
    required this.completedFile,
    required this.metadata,
    required this.checkpoint,
  });

  final LocalRecording recording;
  final CompletedRecordingFile completedFile;
  final DvtDeviceFileMetadata metadata;
  final DeviceFileDownloadCheckpoint checkpoint;
}

/// The outcome of a separate durable archive plus device confirmation.
class DvtDeviceFileArchiveResult {
  const DvtDeviceFileArchiveResult({
    required this.imported,
    required this.deviceConfirmation,
  });

  final DvtDeviceFileImportResult imported;
  final DvtDeviceArchiveConfirmationResult deviceConfirmation;
}
