import 'package:evt_ble_app/features/local_recording/application/recording_library_controller.dart';
import 'package:evt_ble_app/features/local_recording/domain/local_recording.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_audio_player.dart';
import '../../../support/fake_local_recording_repository.dart';
import '../../../support/fake_recording_file_store.dart';

void main() {
  late FakeLocalRecordingRepository repository;
  late FakeRecordingFileStore files;
  late FakeAudioPlayer player;
  late RecordingLibraryController controller;

  setUp(() {
    repository = FakeLocalRecordingRepository([savedRecording('one')]);
    files = FakeRecordingFileStore();
    player = FakeAudioPlayer();
    controller = RecordingLibraryController(
      repository: repository,
      files: files,
      player: player,
    );
  });

  tearDown(() => controller.close());

  test('load keeps prior rows when the repository throws', () async {
    await controller.load();
    repository.failReads = true;

    await controller.load();

    expect(controller.state.items.single.id, 'one');
    expect(controller.state.errorMessage, '本地录音暂时不可读取。');
  });

  test('starting playback stops the prior selection and blocks it during capture', () async {
    repository.values.add(savedRecording('two'));
    await controller.load();

    await controller.play('one');
    await controller.play('two');
    expect(player.activePath, endsWith('two.m4a'));

    controller.setCaptureActive(true);
    await controller.play('one');
    expect(controller.state.errorMessage, '录音进行中，结束后可播放。');
  });

  test('deleting removes the file before metadata and renaming validates input', () async {
    await controller.load();
    final recording = controller.state.items.single;

    await controller.rename(recording, '  客户访谈  ');
    expect(repository.values.single.title, '客户访谈');

    await controller.delete(repository.values.single);
    expect(files.deletedPaths, {'one.m4a'});
    expect(repository.values, isEmpty);
  });
}

LocalRecording savedRecording(String id) {
  return LocalRecording.saved(
    id: id,
    title: '录音 $id',
    relativePath: '$id.m4a',
    createdAt: DateTime(2026, 8, 21),
    completedAt: DateTime(2026, 8, 21, 0, 0, 8),
    duration: const Duration(seconds: 8),
    sizeBytes: 32000,
  );
}
