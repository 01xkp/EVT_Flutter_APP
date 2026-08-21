import 'package:evt_ble_app/features/local_recording/application/recording_controller.dart';
import 'package:evt_ble_app/features/local_recording/domain/audio_recorder_port.dart';
import 'package:evt_ble_app/features/local_recording/domain/local_recording.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_audio_recorder.dart';
import '../../../support/fake_local_recording_repository.dart';
import '../../../support/fake_recording_background_service.dart';
import '../../../support/fake_recording_file_store.dart';

void main() {
  late FakeAudioRecorder recorder;
  late FakeLocalRecordingRepository repository;
  late FakeRecordingFileStore files;
  late FakeRecordingBackgroundService background;
  late RecordingController controller;

  setUp(() {
    recorder = FakeAudioRecorder()..permission = RecorderPermission.granted;
    repository = FakeLocalRecordingRepository();
    files = FakeRecordingFileStore();
    background = FakeRecordingBackgroundService();
    controller = RecordingController(
      repository: repository,
      recorder: recorder,
      files: files,
      background: background,
      idGenerator: () => 'recording-1',
      now: () => DateTime(2026, 8, 21, 9, 28),
    );
  });

  tearDown(() => controller.close());

  test('start persists in-progress metadata before capture and finalizes to saved', () async {
    await controller.start();

    expect(repository.values.single.status, LocalRecordingStatus.inProgress);
    expect(background.startCalls, 1);
    expect(recorder.operations, ['start']);

    await controller.stop();

    expect(repository.values.single.status, LocalRecordingStatus.saved);
    expect(repository.values.single.duration, const Duration(seconds: 12));
    expect(background.stopCalls, 1);
    expect(controller.state.phase, ActiveRecordingPhase.idle);
  });

  test('denied permission does not create metadata or start a service', () async {
    recorder.permission = RecorderPermission.denied;

    await controller.start();

    expect(repository.values, isEmpty);
    expect(background.startCalls, 0);
    expect(controller.state.phase, ActiveRecordingPhase.permissionDenied);
  });

  test('an interruption preserves a readable partial capture as interrupted', () async {
    await controller.start();
    recorder.emit(const RecorderSignal.interrupted('来电占用麦克风'));
    await Future<void>.delayed(Duration.zero);

    expect(repository.values.single.status, LocalRecordingStatus.interrupted);
    expect(repository.values.single.failureReason, '来电占用麦克风');
    expect(background.stopCalls, 1);
  });
}
