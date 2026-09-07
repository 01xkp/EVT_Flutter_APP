import 'package:aipin/features/device_session/data/shared_preferences_device_clear_checkpoint_repository.dart';
import 'package:aipin/features/device_session/domain/device_clear_checkpoint.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('persists a confirmed clear transaction by device', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = SharedPreferencesDeviceClearCheckpointRepository();
    final checkpoint = DeviceClearCheckpoint(
      deviceId: 'device-1',
      transactionId: 0x01020304,
      expectedBindingGeneration: 3,
      confirmNonce: List<int>.generate(16, (index) => index),
      clearScope: 0x3F,
    );

    await repository.save(checkpoint);

    final restored = await repository.find('device-1');
    expect(restored?.transactionId, checkpoint.transactionId);
    expect(restored?.expectedBindingGeneration, 3);
    expect(restored?.confirmNonce, checkpoint.confirmNonce);
    expect(restored?.clearScope, 0x3F);

    await repository.clear('device-1');

    expect(await repository.find('device-1'), isNull);
  });
}
