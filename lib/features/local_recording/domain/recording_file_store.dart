class PendingRecordingFile {
  const PendingRecordingFile({
    required this.id,
    required this.temporaryPath,
    required this.relativePath,
  });

  final String id;
  final String temporaryPath;
  final String relativePath;
}

class CompletedRecordingFile {
  const CompletedRecordingFile({
    required this.relativePath,
    required this.absolutePath,
    required this.sizeBytes,
  });

  final String relativePath;
  final String absolutePath;
  final int sizeBytes;
}

class RecordingFileException implements Exception {
  const RecordingFileException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class RecordingFileStore {
  Future<PendingRecordingFile> createPending({required String id});
  Future<void> discard(PendingRecordingFile pending);
  Future<CompletedRecordingFile> finalize(PendingRecordingFile pending);
  Future<CompletedRecordingFile?> recoverPartial(String relativePath);
  Future<String> absolutePathFor(String relativePath);
  Future<bool> exists(String relativePath);
  Future<void> delete(String relativePath);
  Future<void> cleanupOrphanedTemporaryFiles();
}
