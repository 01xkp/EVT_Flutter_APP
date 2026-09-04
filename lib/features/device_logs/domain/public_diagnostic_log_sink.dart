abstract interface class PublicDiagnosticLogSink {
  Future<PublicDiagnosticLogMirrorStatus> mirrorCanonicalFile({
    required String sourcePath,
    required String filename,
  });
}

class PublicDiagnosticLogMirrorStatus {
  const PublicDiagnosticLogMirrorStatus({
    required this.available,
    this.relativePath,
    this.lastUpdatedAt,
    this.failureCode,
  });

  const PublicDiagnosticLogMirrorStatus.unavailable()
    : available = false,
      relativePath = null,
      lastUpdatedAt = null,
      failureCode = null;

  factory PublicDiagnosticLogMirrorStatus.success({
    required String relativePath,
    required DateTime lastUpdatedAt,
  }) => PublicDiagnosticLogMirrorStatus(
    available: true,
    relativePath: relativePath,
    lastUpdatedAt: lastUpdatedAt,
  );

  factory PublicDiagnosticLogMirrorStatus.failure(String failureCode) =>
      PublicDiagnosticLogMirrorStatus(
        available: false,
        failureCode: _normalizeFailureCode(failureCode),
      );

  final bool available;
  final String? relativePath;
  final DateTime? lastUpdatedAt;
  final String? failureCode;

  static String _normalizeFailureCode(String value) {
    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return normalized.isEmpty ? 'unknown' : normalized;
  }
}
