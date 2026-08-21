import 'package:evt_ble_app/features/local_recording/data/foreground_recording_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no-op background service remains safe on unsupported platforms', () async {
    const service = NoopRecordingBackgroundService();

    await service.start();
    await service.updateElapsed(const Duration(seconds: 12));
    await service.stop();
  });
}
