import 'package:aipin/features/device_session/domain/device_file_download_checkpoint.dart';
import 'package:aipin/features/device_session/domain/device_file_download_checkpoint_repository.dart';

class FakeDeviceFileDownloadCheckpointRepository
    implements DeviceFileDownloadCheckpointRepository {
  FakeDeviceFileDownloadCheckpointRepository([
    Iterable<DeviceFileDownloadCheckpoint> values = const [],
  ]) : _values = List<DeviceFileDownloadCheckpoint>.from(values);

  final List<DeviceFileDownloadCheckpoint> _values;

  @override
  Future<List<DeviceFileDownloadCheckpoint>> allDownloading() async =>
      List<DeviceFileDownloadCheckpoint>.unmodifiable(_values);

  @override
  Future<DeviceFileDownloadCheckpoint?> find({
    required String deviceId,
    required List<int> nameSlot,
  }) async {
    final id = DeviceFileDownloadCheckpoint.idFor(
      deviceId: deviceId,
      nameSlot: nameSlot,
    );
    for (final checkpoint in _values) {
      if (checkpoint.id == id) {
        return checkpoint;
      }
    }
    return null;
  }

  @override
  Future<void> remove(String id) async {
    _values.removeWhere((checkpoint) => checkpoint.id == id);
  }

  @override
  Future<void> removeAllForDevice(String deviceId) async {
    _values.removeWhere((checkpoint) => checkpoint.deviceId == deviceId);
  }

  @override
  Future<void> save(DeviceFileDownloadCheckpoint checkpoint) async {
    await remove(checkpoint.id);
    _values.add(checkpoint);
  }
}
