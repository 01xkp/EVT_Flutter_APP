class PendingResearchCaptureFile {
  const PendingResearchCaptureFile({
    required this.id,
    required this.temporaryPath,
    required this.relativePath,
  });

  final String id;
  final String temporaryPath;
  final String relativePath;
}

class CompletedResearchCaptureFile {
  const CompletedResearchCaptureFile({
    required this.relativePath,
    required this.absolutePath,
    required this.sizeBytes,
  });

  final String relativePath;
  final String absolutePath;
  final int sizeBytes;
}

class ResearchCaptureFileException implements Exception {
  const ResearchCaptureFileException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class ResearchCaptureFileStore {
  Future<PendingResearchCaptureFile> createPending({required String id});
  Future<void> discard(PendingResearchCaptureFile pending);
  Future<CompletedResearchCaptureFile> finalize(
    PendingResearchCaptureFile pending,
  );
  Future<CompletedResearchCaptureFile> copyFromLocal({
    required String id,
    required String sourcePath,
  });
  Future<String> absolutePathFor(String relativePath);
  Future<void> delete(String relativePath);
  Future<void> deleteAll();
}
