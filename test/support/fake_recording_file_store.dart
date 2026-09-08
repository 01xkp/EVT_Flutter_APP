import 'package:aipin/features/local_recording/domain/recording_file_store.dart';

class FakeRecordingFileStore implements RecordingFileStore {
  final Map<String, int> recoverablePaths = {};
  final Set<String> deletedPaths = {};
  final Set<String> discardedIds = {};
  final Set<String> missingPaths = {};
  var cleanupTemporaryFilesCalls = 0;
  List<String> cleanupProtectedRecordingIds = const [];
  int finalizedSizeBytes = 160000;
  bool failFinalization = false;
  bool failDelete = false;

  @override
  Future<String> absolutePathFor(String relativePath) async {
    return '/recordings/$relativePath';
  }

  @override
  Future<PendingRecordingFile> createPending({
    required String id,
    String extension = '.m4a',
  }) async {
    return PendingRecordingFile(
      id: id,
      temporaryPath: '/recordings/$id.part$extension',
      relativePath: '$id$extension',
    );
  }

  @override
  Future<void> append(PendingRecordingFile pending, List<int> bytes) async {}

  @override
  Future<int> pendingLength(PendingRecordingFile pending) async => 0;

  @override
  Stream<List<int>> readPending(PendingRecordingFile pending) =>
      const Stream<List<int>>.empty();

  @override
  Future<CompletedRecordingFile> importBytes({
    required String id,
    String extension = '.m4a',
    required Stream<List<int>> chunks,
  }) async {
    var size = 0;
    await for (final chunk in chunks) {
      size += chunk.length;
    }
    return CompletedRecordingFile(
      relativePath: '$id$extension',
      absolutePath: '/recordings/$id$extension',
      sizeBytes: size,
    );
  }

  @override
  Future<void> discard(PendingRecordingFile pending) async {
    discardedIds.add(pending.id);
  }

  @override
  Future<void> delete(String relativePath) async {
    if (failDelete) {
      throw const RecordingFileException('无法删除录音文件。');
    }
    deletedPaths.add(relativePath);
  }

  @override
  Future<bool> exists(String relativePath) async =>
      !missingPaths.contains(relativePath);

  @override
  Future<void> cleanupOrphanedTemporaryFiles({
    Iterable<String> protectedRecordingIds = const [],
  }) async {
    cleanupTemporaryFilesCalls += 1;
    cleanupProtectedRecordingIds = List<String>.unmodifiable(
      protectedRecordingIds,
    );
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
