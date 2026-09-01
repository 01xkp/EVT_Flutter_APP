import 'package:aipin/features/device_session/data/shared_preferences_firmware_update_checkpoint_repository.dart';
import 'package:aipin/features/device_session/domain/firmware_update_checkpoint.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'persists an OTA checkpoint by device and clears it after verification',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repository = SharedPreferencesFirmwareUpdateCheckpointRepository();
      final updatedAt = DateTime.utc(2026, 9, 1, 8, 30);

      await repository.save(
        FirmwareUpdateCheckpoint(
          deviceId: 'device-1',
          packageHash: 'abc123',
          offset: 4096,
          updatedAt: updatedAt,
        ),
      );

      final restored = await repository.find('device-1');
      expect(restored?.packageHash, 'abc123');
      expect(restored?.offset, 4096);
      expect(restored?.updatedAt, updatedAt);

      await repository.clear('device-1');

      expect(await repository.find('device-1'), isNull);
    },
  );
}
