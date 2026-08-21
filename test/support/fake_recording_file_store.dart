import 'package:evt_ble_app/features/local_recording/domain/recording_file_store.dart';

class FakeRecordingFileStore implements RecordingFileStore {
  final Map<String, int> recoverablePaths = {};
  final Set<String> deletedPaths = {};
  int finalizedSizeBytes = 160000;
  bool failFinalization = false;
  bool failDelete = false;

  @override
  Future<String> absolutePathFor(String relativePath) async {
    return '/recordings/$relativePath';
  }

  @override
  Future<PendingRecordingFile> createPending({required String id}) async {
    return PendingRecordingFile(
      id: id,
      temporaryPath: '/recordings/$id.part.m4a',
      relativePath: '$id.m4a',
    );
  }

  @override
  Future<void> delete(String relativePath) async {
    if (failDelete) {
      throw const RecordingFileException('无法删除录音文件。');
    }
    deletedPaths.add(relativePath);
  }

  @override
  Future<CompletedRecordingFile> finalize(PendingRecordingFile pending) async {
    if (failFinalization) {
      throw const RecordingFileException('无法完成录音文件。');
    }
    return CompletedRecordingFile(
      relativePath: pending.relativePath,
      absolutePath: '/recordings/${pending.relativePath}',
      sizeBytes: finalizedSizeBytes,
    );
  }

  @override
  Future<CompletedRecordingFile?> recoverPartial(String relativePath) async {
    final sizeBytes = recoverablePaths[relativePath];
    if (sizeBytes == null) {
      return null;
    }
    return CompletedRecordingFile(
      relativePath: relativePath,
      absolutePath: '/recordings/$relativePath',
      sizeBytes: sizeBytes,
    );
  }
}
