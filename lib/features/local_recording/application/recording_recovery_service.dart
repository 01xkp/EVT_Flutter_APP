import 'package:evt_ble_app/features/local_recording/domain/local_recording.dart';
import 'package:evt_ble_app/features/local_recording/domain/local_recording_repository.dart';
import 'package:evt_ble_app/features/local_recording/domain/recording_file_store.dart';

class RecordingRecoveryService {
  factory RecordingRecoveryService({
    required LocalRecordingRepository repository,
    required RecordingFileStore files,
    DateTime Function()? now,
  }) {
    return RecordingRecoveryService._(
      repository: repository,
      files: files,
      now: now ?? DateTime.now,
    );
  }

  RecordingRecoveryService._({
    required this._repository,
    required this._files,
    required this._now,
  });

  final LocalRecordingRepository _repository;
  final RecordingFileStore _files;
  final DateTime Function() _now;

  Future<void> reconcile() async {
    final recordings = await _repository.all();
    for (final recording in recordings) {
      if (recording.status != LocalRecordingStatus.inProgress) {
        continue;
      }
      try {
        final file = await _files.recoverPartial(recording.relativePath);
        if (file == null) {
          await _repository.update(recording.failed('临时录音文件不存在。'));
          continue;
        }
        await _repository.update(
          recording.completed(
            status: LocalRecordingStatus.interrupted,
            completedAt: _now(),
            duration: recording.duration ?? Duration.zero,
            sizeBytes: file.sizeBytes,
            failureReason: '应用意外退出，已恢复可播放部分。',
          ),
        );
      } on RecordingFileException catch (error) {
        await _repository.update(recording.failed(error.message));
      }
    }
  }
}
