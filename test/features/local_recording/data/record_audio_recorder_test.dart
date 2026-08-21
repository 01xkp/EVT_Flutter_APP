import 'package:evt_ble_app/features/local_recording/domain/audio_recorder_port.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_audio_recorder.dart';

void main() {
  test('recorder exposes pause, resume, and interruption signals', () async {
    final recorder = FakeAudioRecorder()
      ..permission = RecorderPermission.granted;
    await recorder.start('/tmp/recording.part.m4a');
    await recorder.pause();
    await recorder.resume();
    final signal = recorder.signals.first;
    recorder.emit(const RecorderSignal.interrupted('系统音频中断'));

    expect(recorder.operations, ['start', 'pause', 'resume']);
    expect(
      await signal,
      isA<RecorderInterrupted>().having(
        (value) => value.reason,
        'reason',
        '系统音频中断',
      ),
    );
  });
}
