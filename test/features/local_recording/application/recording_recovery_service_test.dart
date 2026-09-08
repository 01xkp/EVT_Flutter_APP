import 'package:aipin/features/local_recording/application/recording_recovery_service.dart';
import 'package:aipin/features/local_recording/domain/local_recording.dart';
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

  test(
    'recovery marks a saved recording with a missing file as failed',
    () async {
      final recording = LocalRecording.saved(
        id: 'recording-3',
        title: '录音',
        relativePath: 'recording-3.m4a',
        createdAt: DateTime(2026, 8, 21),
        completedAt: DateTime(2026, 8, 21, 10),
        duration: const Duration(seconds: 4),
        sizeBytes: 900,
      );
      final repository = FakeLocalRecordingRepository([recording]);
      final files = FakeRecordingFileStore()
        ..missingPaths.add(recording.relativePath);
      final service = RecordingRecoveryService(
        repository: repository,
        files: files,
      );

      await service.reconcile();

      expect(repository.values.single.status, LocalRecordingStatus.failed);
      expect(repository.values.single.failureReason, '录音文件不存在。');
    },
  );

  test(
    'recovery removes orphaned temporary files after reconciliation',
    () async {
      final files = FakeRecordingFileStore();
      final service = RecordingRecoveryService(
        repository: FakeLocalRecordingRepository(),
        files: files,
      );

      await service.reconcile();

      expect(files.cleanupTemporaryFilesCalls, 1);
    },
  );

  test(
    'recovery protects checkpoint-owned temporary device downloads',
    () async {
      final files = FakeRecordingFileStore();
      final service = RecordingRecoveryService(
        repository: FakeLocalRecordingRepository(),
        files: files,
      );

      await service.reconcile(
        protectedRecordingIds: const ['device-checkpoint'],
      );

      expect(files.cleanupProtectedRecordingIds, ['device-checkpoint']);
    },
  );

  test(
    'recovery retains temporary files when checkpoint lookup is unavailable',
    () async {
      final files = FakeRecordingFileStore();
      final service = RecordingRecoveryService(
        repository: FakeLocalRecordingRepository(),
        files: files,
      );

      await service.reconcile(cleanupTemporaryFiles: false);

      expect(files.cleanupTemporaryFilesCalls, 0);
    },
  );
}
