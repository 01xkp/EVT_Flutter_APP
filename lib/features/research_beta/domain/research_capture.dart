enum ResearchCaptureOrigin { directAiVoice, localRecordingUpload }

enum ResearchProcessingState {
  uploading,
  transcribing,
  summarizing,
  completed,
  uploadFailed,
  transcriptionFailed,
  summaryFailed,
}

enum ResearchInboxState { processing, needsReview, handled }

enum ResearchCardAction { retained, edited, copied, useful, notUseful }

class ResearchCapture {
  const ResearchCapture({
    required this.id,
    required this.participantId,
    required this.origin,
    required this.sourceType,
    required this.relativePath,
    required this.duration,
    required this.createdAt,
    required this.processingState,
    required this.inboxState,
    this.originalLocalRecordingId,
    this.jobId,
    this.noteId,
    this.generationTaskId,
    this.rawTranscript,
    this.correctedTranscript,
    this.title,
    this.summary,
    this.tags = const [],
    this.actionContext,
    this.failureReason,
    this.openedAt,
    this.handledAt,
    this.completedAt,
  });

  static const sourceTypeResearchImport = 'research_import';

  final String id;
  final String participantId;
  final ResearchCaptureOrigin origin;
  final String sourceType;
  final String relativePath;
  final Duration duration;
  final DateTime createdAt;
  final ResearchProcessingState processingState;
  final ResearchInboxState inboxState;
  final String? originalLocalRecordingId;
  final String? jobId;
  final String? noteId;
  final String? generationTaskId;
  final String? rawTranscript;
  final String? correctedTranscript;
  final String? title;
  final String? summary;
  final List<String> tags;
  final String? actionContext;
  final String? failureReason;
  final DateTime? openedAt;
  final DateTime? handledAt;
  final DateTime? completedAt;

  bool get isTerminal =>
      processingState == ResearchProcessingState.completed ||
      processingState == ResearchProcessingState.uploadFailed ||
      processingState == ResearchProcessingState.transcriptionFailed ||
      processingState == ResearchProcessingState.summaryFailed;

  bool get canRetry => processingState != ResearchProcessingState.completed;

  factory ResearchCapture.fromDirectAiVoice({
    required String id,
    required String participantId,
    required String relativePath,
    required Duration duration,
    required DateTime createdAt,
  }) {
    validateDuration(duration);
    return ResearchCapture(
      id: id,
      participantId: participantId,
      origin: ResearchCaptureOrigin.directAiVoice,
      sourceType: sourceTypeResearchImport,
      relativePath: relativePath,
      duration: duration,
      createdAt: createdAt,
      processingState: ResearchProcessingState.uploading,
      inboxState: ResearchInboxState.processing,
    );
  }

  factory ResearchCapture.fromLocalRecording({
    required String id,
    required String participantId,
    required String originalLocalRecordingId,
    required String relativePath,
    required Duration duration,
    required DateTime createdAt,
  }) {
    validateDuration(duration);
    return ResearchCapture(
      id: id,
      participantId: participantId,
      origin: ResearchCaptureOrigin.localRecordingUpload,
      sourceType: sourceTypeResearchImport,
      relativePath: relativePath,
      duration: duration,
      createdAt: createdAt,
      processingState: ResearchProcessingState.uploading,
      inboxState: ResearchInboxState.processing,
      originalLocalRecordingId: originalLocalRecordingId,
    );
  }

  static void validateDuration(Duration duration) {
    if (duration < const Duration(seconds: 2) ||
        duration > const Duration(seconds: 60)) {
      throw ArgumentError.value(duration, 'duration', 'AI 语音仅支持 2 至 60 秒');
    }
  }

  ResearchCapture toTranscribing(String jobId) {
    return copyWith(
      processingState: ResearchProcessingState.transcribing,
      inboxState: ResearchInboxState.processing,
      jobId: jobId,
      failureReason: '',
    );
  }

  ResearchCapture toSummarizing({
    required String rawTranscript,
    required String noteId,
    required String generationTaskId,
  }) {
    return copyWith(
      processingState: ResearchProcessingState.summarizing,
      inboxState: ResearchInboxState.processing,
      rawTranscript: rawTranscript,
      noteId: noteId,
      generationTaskId: generationTaskId,
      failureReason: '',
    );
  }

  ResearchCapture completed({
    required String title,
    required String summary,
    required List<String> tags,
    required DateTime completedAt,
    String? actionContext,
  }) {
    return copyWith(
      processingState: ResearchProcessingState.completed,
      inboxState: ResearchInboxState.needsReview,
      title: title.trim(),
      summary: summary.trim(),
      tags: List.unmodifiable(
        tags.map((tag) => tag.trim()).where((tag) => tag.isNotEmpty),
      ),
      actionContext: actionContext,
      completedAt: completedAt,
      failureReason: '',
    );
  }

  ResearchCapture failed(ResearchProcessingState state, String reason) {
    if (state != ResearchProcessingState.uploadFailed &&
        state != ResearchProcessingState.transcriptionFailed &&
        state != ResearchProcessingState.summaryFailed) {
      throw ArgumentError.value(state, 'state', '必须提供失败状态');
    }
    return copyWith(
      processingState: state,
      inboxState: ResearchInboxState.processing,
      failureReason: reason,
    );
  }

  ResearchCapture opened(DateTime openedAt) => copyWith(openedAt: openedAt);

  ResearchCapture handled(DateTime handledAt) {
    return copyWith(
      inboxState: ResearchInboxState.handled,
      handledAt: handledAt,
    );
  }

  ResearchCapture withCorrectedTranscript(String value) =>
      copyWith(correctedTranscript: value.trim());

  ResearchCapture copyWith({
    ResearchProcessingState? processingState,
    ResearchInboxState? inboxState,
    String? jobId,
    String? noteId,
    String? generationTaskId,
    String? rawTranscript,
    String? correctedTranscript,
    String? title,
    String? summary,
    List<String>? tags,
    String? actionContext,
    String? failureReason,
    DateTime? openedAt,
    DateTime? handledAt,
    DateTime? completedAt,
  }) {
    return ResearchCapture(
      id: id,
      participantId: participantId,
      origin: origin,
      sourceType: sourceType,
      relativePath: relativePath,
      duration: duration,
      createdAt: createdAt,
      processingState: processingState ?? this.processingState,
      inboxState: inboxState ?? this.inboxState,
      originalLocalRecordingId: originalLocalRecordingId,
      jobId: jobId ?? this.jobId,
      noteId: noteId ?? this.noteId,
      generationTaskId: generationTaskId ?? this.generationTaskId,
      rawTranscript: rawTranscript ?? this.rawTranscript,
      correctedTranscript: correctedTranscript ?? this.correctedTranscript,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      tags: tags ?? this.tags,
      actionContext: actionContext ?? this.actionContext,
      failureReason: failureReason?.isEmpty == true
          ? null
          : failureReason ?? this.failureReason,
      openedAt: openedAt ?? this.openedAt,
      handledAt: handledAt ?? this.handledAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}
