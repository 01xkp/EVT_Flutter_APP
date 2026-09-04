import 'package:aipin/features/device_session/domain/remembered_device.dart';

abstract interface class DeviceConnectionHistoryRepository {
  Future<List<RememberedDevice>> load();

  Future<void> upsert(RememberedDevice record);

  Future<void> removeMatching({
    required String connectionId,
    String? physicalMacAddress,
  });
}
