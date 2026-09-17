import 'package:aipin/features/device_session/data/shared_preferences_firmware_update_checkpoint_repository.dart';
import 'package:aipin/features/device_session/domain/firmware_update_checkpoint.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('persists the DVT offset, length and image CRC checkpoint', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repository = SharedPreferencesFirmwareUpdateCheckpointRepository();
    final updatedAt = DateTime.utc(2026, 9, 15, 12, 30);

    await repository.save(
      FirmwareUpdateCheckpoint(
        deviceId: 'device-1',
        packageHash: 'abc',
        imageCrc32: 0x55BC801D,
        packageVersion: 2,
        expectedBusinessVersion: '1.0.2',
        phase: FirmwareUpdateCheckpointPhase.awaitingReconnect,
        nextOffset: 4096,
        nextLength: 1024,
        updatedAt: updatedAt,
      ),
    );

    final value = await repository.find('device-1');
    expect(value?.packageHash, 'abc');
    expect(value?.imageCrc32, 0x55BC801D);
    expect(value?.packageVersion, 2);
    expect(value?.expectedBusinessVersion, '1.0.2');
    expect(value?.phase, FirmwareUpdateCheckpointPhase.awaitingReconnect);
    expect(value?.nextOffset, 4096);
    expect(value?.nextLength, 1024);
    expect(value?.updatedAt, updatedAt);

    await repository.clear('device-1');
    expect(await repository.find('device-1'), isNull);
  });
}
