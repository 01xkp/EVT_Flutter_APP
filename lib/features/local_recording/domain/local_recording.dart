enum LocalRecordingStatus { inProgress, saved, interrupted, failed }

class LocalRecording {
  const LocalRecording({
    required this.id,
    required this.title,
    required this.relativePath,
    required this.createdAt,
    required this.status,
    this.completedAt,
    this.duration,
    this.sizeBytes,
    this.failureReason,
  });

  final String id;
  final String title;
  final String relativePath;
  final DateTime createdAt;
  final LocalRecordingStatus status;
  final DateTime? completedAt;
  final Duration? duration;
  final int? sizeBytes;
  final String? failureReason;

  bool get isPlayable =>
      (status == LocalRecordingStatus.saved ||
          status == LocalRecordingStatus.interrupted) &&
      duration != null &&
      sizeBytes != null &&
      sizeBytes! > 0;

  factory LocalRecording.inProgress({
    required String id,
    required String title,
    required String relativePath,
    required DateTime createdAt,
  }) {
    return LocalRecording(
      id: id,
      title: title,
      relativePath: relativePath,
      createdAt: createdAt,
      status: LocalRecordingStatus.inProgress,
    );
  }

  factory LocalRecording.saved({
    required String id,
    required String title,
    required String relativePath,
    required DateTime createdAt,
    required DateTime completedAt,
    required Duration duration,
    required int sizeBytes,
  }) {
    return LocalRecording(
      id: id,
      title: title,
      relativePath: relativePath,
      createdAt: createdAt,
      status: LocalRecordingStatus.saved,
      completedAt: completedAt,
      duration: duration,
      sizeBytes: sizeBytes,
    );
  }

  LocalRecording renamed(String value) {
    final title = value.trim();
    if (title.isEmpty) {
      throw ArgumentError.value(value, 'value', '标题不能为空');
    }
    return copyWith(title: title);
  }

  LocalRecording completed({
    required LocalRecordingStatus status,
    required DateTime completedAt,
    required Duration duration,
    required int sizeBytes,
    String? failureReason,
  }) {
    assert(
      status == LocalRecordingStatus.saved ||
          status == LocalRecordingStatus.interrupted,
    );
    return copyWith(
      status: status,
      completedAt: completedAt,
      duration: duration,
      sizeBytes: sizeBytes,
      failureReason: failureReason,
    );
  }

  LocalRecording failed(String reason) {
    return copyWith(status: LocalRecordingStatus.failed, failureReason: reason);
  }

  LocalRecording copyWith({
    String? title,
    LocalRecordingStatus? status,
    DateTime? completedAt,
    Duration? duration,
    int? sizeBytes,
    String? failureReason,
  }) {
    return LocalRecording(
      id: id,
      title: title ?? this.title,
      relativePath: relativePath,
      createdAt: createdAt,
      status: status ?? this.status,
      completedAt: completedAt ?? this.completedAt,
      duration: duration ?? this.duration,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      failureReason: failureReason ?? this.failureReason,
    );
  }
}
