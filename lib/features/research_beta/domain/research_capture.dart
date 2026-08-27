enum ResearchCaptureOrigin { directAiVoice, localRecordingUpload }

enum ResearchDocumentType { transcript, summary }

extension ResearchDocumentTypeLabel on ResearchDocumentType {
  String get defaultTitle => switch (this) {
    ResearchDocumentType.transcript => '转写',
    ResearchDocumentType.summary => 'AI 总结',
  };
}

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

class ResearchAsrSegment {
  const ResearchAsrSegment({
    required this.index,
    required this.relativePath,
    this.jobId,
  }) : assert(index >= 0);

  final int index;
  final String relativePath;
  final String? jobId;

  ResearchAsrSegment withJobId(String value) => ResearchAsrSegment(
    index: index,
    relativePath: relativePath,
    jobId: value,
  );

  @override
  bool operator ==(Object other) =>
      other is ResearchAsrSegment &&
      other.index == index &&
      other.relativePath == relativePath &&
      other.jobId == jobId;

  @override
  int get hashCode => Object.hash(index, relativePath, jobId);
}

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
    this.asrSegments = const [],
    this.noteId,
    this.generationTaskId,
    this.rawTranscript,
    this.correctedTranscript,
    this.title,
    this.transcriptTitle,
    this.summaryTitle,
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
  final List<ResearchAsrSegment> asrSegments;
  final String? noteId;
  final String? generationTaskId;
  final String? rawTranscript;
  final String? correctedTranscript;
  final String? title;
  final String? transcriptTitle;
  final String? summaryTitle;
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

  bool get hasMultipleAsrSegments => asrSegments.length > 1;

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
    if (duration < const Duration(seconds: 2)) {
      throw ArgumentError.value(duration, 'duration', 'AI 语音至少需要 2 秒');
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

  ResearchCapture withAsrSegments(List<ResearchAsrSegment> segments) {
    final ordered = List<ResearchAsrSegment>.from(segments)
      ..sort((left, right) => left.index.compareTo(right.index));
    for (var index = 0; index < ordered.length; index += 1) {
      if (ordered[index].index != index) {
        throw ArgumentError.value(segments, 'segments', '分段索引必须从 0 连续递增。');
      }
    }
    return copyWith(asrSegments: List.unmodifiable(ordered));
  }

  ResearchCapture withSubmittedAsrSegment({
    required int index,
    required String jobId,
  }) {
    final updated = asrSegments
        .map(
          (segment) =>
              segment.index == index ? segment.withJobId(jobId) : segment,
        )
        .toList(growable: false);
    if (!updated.any((segment) => segment.index == index)) {
      throw ArgumentError.value(index, 'index', '未找到对应的音频分段。');
    }
    return withAsrSegments(updated);
  }

  ResearchCapture toSegmentedTranscribing() {
    if (asrSegments.isEmpty ||
        asrSegments.any((segment) => segment.jobId == null)) {
      throw StateError('所有音频分段提交成功后才能开始转写。');
    }
    return copyWith(
      processingState: ResearchProcessingState.transcribing,
      inboxState: ResearchInboxState.processing,
      jobId: jobId ?? asrSegments.first.jobId,
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

  String documentTitle(ResearchDocumentType type) {
    final title = switch (type) {
      ResearchDocumentType.transcript => transcriptTitle,
      ResearchDocumentType.summary => summaryTitle,
    };
    return title == null || title.trim().isEmpty ? type.defaultTitle : title;
  }

  ResearchCapture withDocumentTitle(ResearchDocumentType type, String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'value', '文档名称不能为空。');
    }
    return switch (type) {
      ResearchDocumentType.transcript => copyWith(transcriptTitle: normalized),
      ResearchDocumentType.summary => copyWith(summaryTitle: normalized),
    };
  }

  ResearchCapture restartSummary() {
    return ResearchCapture(
      id: id,
      participantId: participantId,
      origin: origin,
      sourceType: sourceType,
      relativePath: relativePath,
      duration: duration,
      createdAt: createdAt,
      processingState: ResearchProcessingState.summarizing,
      inboxState: ResearchInboxState.processing,
      originalLocalRecordingId: originalLocalRecordingId,
      jobId: jobId,
      asrSegments: asrSegments,
      rawTranscript: rawTranscript,
      correctedTranscript: correctedTranscript,
      transcriptTitle: transcriptTitle,
      summaryTitle: summaryTitle,
      openedAt: openedAt,
    );
  }

  ResearchCapture restartTranscription() {
    return ResearchCapture(
      id: id,
      participantId: participantId,
      origin: origin,
      sourceType: sourceType,
      relativePath: relativePath,
      duration: duration,
      createdAt: createdAt,
      processingState: ResearchProcessingState.uploading,
      inboxState: ResearchInboxState.processing,
      originalLocalRecordingId: originalLocalRecordingId,
      asrSegments: const [],
      transcriptTitle: transcriptTitle,
      summaryTitle: summaryTitle,
      openedAt: openedAt,
    );
  }

  ResearchCapture copyWith({
    ResearchProcessingState? processingState,
    ResearchInboxState? inboxState,
    String? jobId,
    List<ResearchAsrSegment>? asrSegments,
    String? noteId,
    String? generationTaskId,
    String? rawTranscript,
    String? correctedTranscript,
    String? title,
    String? transcriptTitle,
    String? summaryTitle,
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
      asrSegments: asrSegments ?? this.asrSegments,
      noteId: noteId ?? this.noteId,
      generationTaskId: generationTaskId ?? this.generationTaskId,
      rawTranscript: rawTranscript ?? this.rawTranscript,
      correctedTranscript: correctedTranscript ?? this.correctedTranscript,
      title: title ?? this.title,
      transcriptTitle: transcriptTitle ?? this.transcriptTitle,
      summaryTitle: summaryTitle ?? this.summaryTitle,
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
