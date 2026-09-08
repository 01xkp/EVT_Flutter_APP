import 'package:aipin/features/device_session/domain/device_file_download_checkpoint.dart';

abstract interface class DeviceFileDownloadCheckpointRepository {
  Future<List<DeviceFileDownloadCheckpoint>> allDownloading();

  Future<DeviceFileDownloadCheckpoint?> find({
    required String deviceId,
    required List<int> nameSlot,
  });

  Future<void> save(DeviceFileDownloadCheckpoint checkpoint);

  Future<void> remove(String id);

  Future<void> removeAllForDevice(String deviceId);
}
