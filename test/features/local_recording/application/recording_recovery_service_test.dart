import 'package:evt_ble_app/features/local_recording/application/recording_recovery_service.dart';
import 'package:evt_ble_app/features/local_recording/domain/local_recording.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_local_recording_repository.dart';
import '../../../support/fake_recording_file_store.dart';

void main() {
  test('recovery never upgrades a missing temporary file to saved', () async {
    final repository = FakeLocalRecordingRepository([
      LocalRecording.inProgress(
        id: 'recording-1',
        title: '录音',
        relativePath: 'recording-1.m4a',
        createdAt: DateTime(2026, 8, 21),
      ),
    ]);
    final service = RecordingRecoveryService(
      repository: repository,
      files: FakeRecordingFileStore(),
      now: () => DateTime(2026, 8, 21, 10),
    );

    await service.reconcile();

    expect(repository.values.single.status, LocalRecordingStatus.failed);
  });

  test('recovery marks a readable partial capture as interrupted', () async {
    final repository = FakeLocalRecordingRepository([
      LocalRecording.inProgress(
        id: 'recording-2',
        title: '录音',
        relativePath: 'recording-2.m4a',
        createdAt: DateTime(2026, 8, 21),
      ),
    ]);
    final files = FakeRecordingFileStore()
      ..recoverablePaths['recording-2.m4a'] = 900;
    final service = RecordingRecoveryService(
      repository: repository,
      files: files,
      now: () => DateTime(2026, 8, 21, 10),
    );

    await service.reconcile();

    expect(repository.values.single.status, LocalRecordingStatus.interrupted);
    expect(repository.values.single.sizeBytes, 900);
  });
}
