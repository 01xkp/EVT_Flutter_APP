// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:aipin/features/local_recording/domain/local_recording.dart';
import 'package:aipin/features/local_recording/domain/recording_file_store.dart';
import 'package:aipin/features/research_beta/application/research_processing_poll_schedule.dart';
import 'package:aipin/features/research_beta/domain/research_analytics.dart';
import 'package:aipin/features/research_beta/domain/research_capture.dart';
import 'package:aipin/features/research_beta/domain/research_capture_file_store.dart';
import 'package:aipin/features/research_beta/domain/research_capture_repository.dart';
import 'package:aipin/features/research_beta/domain/research_trial.dart';
import 'package:aipin/features/research_beta/domain/temporary_asr_gateway.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

enum ResearchCaptureUiUpdateKind { transcribing, summarizing, completed }

class ResearchCaptureUiUpdate {
  const ResearchCaptureUiUpdate({
    required this.captureId,
    required this.kind,
    this.completedAt,
  });

  final String captureId;
  final ResearchCaptureUiUpdateKind kind;
  final DateTime? completedAt;
}

class ResearchCaptureProcessingController extends ChangeNotifier {
  ResearchCaptureProcessingController({
    required ResearchCaptureRepository repository,
    required ResearchCaptureFileStore researchFiles,
    required RecordingFileStore localFiles,
    required TemporaryAsrGateway gateway,
    required ResearchTrialStore trialStore,
    String Function()? idGenerator,
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
    ResearchProcessingPollSchedule pollSchedule =
        const ResearchProcessingPollSchedule(),
    Duration processingTimeout = const Duration(minutes: 30),
    Duration remoteDeleteTimeout = const Duration(seconds: 5),
  }) : _repository = repository,
       _researchFiles = researchFiles,
       _localFiles = localFiles,
       _gateway = gateway,
       _trialStore = trialStore,
       _idGenerator = idGenerator ?? const Uuid().v4,
       _now = now ?? DateTime.now,
       _delay = delay ?? Future.delayed,
       _pollSchedule = pollSchedule,
       _processingTimeout = processingTimeout,
       _remoteDeleteTimeout = remoteDeleteTimeout;

  final ResearchCaptureRepository _repository;
  final ResearchCaptureFileStore _researchFiles;
  final RecordingFileStore _localFiles;
  final TemporaryAsrGateway _gateway;
  final ResearchTrialStore _trialStore;
  final String Function() _idGenerator;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;
  final ResearchProcessingPollSchedule _pollSchedule;
  final Duration _processingTimeout;
  final Duration _remoteDeleteTimeout;
  final Map<String, Future<ResearchCapture?>> _inFlight =
      <String, Future<ResearchCapture?>>{};

  final Set<String> _processingIds = <String>{};
  Set<String> get processingIds => Set.unmodifiable(_processingIds);
  final List<ResearchCapture> _completedCaptures = <ResearchCapture>[];
  final List<ResearchCaptureUiUpdate> _pendingUiUpdates =
      <ResearchCaptureUiUpdate>[];

  List<ResearchCapture> drainCompletedCaptures() {
    final completed = List<ResearchCapture>.unmodifiable(_completedCaptures);
    _completedCaptures.clear();
    return completed;
  }

  List<ResearchCaptureUiUpdate> drainUiUpdates() {
    final updates = List<ResearchCaptureUiUpdate>.unmodifiable(
      _pendingUiUpdates,
    );
    _pendingUiUpdates.clear();
    _completedCaptures.clear();
    return updates;
  }

  String? _lastError;
  String? get lastError => _lastError;

  Future<ResearchCapture> createFromLocalRecording(
    LocalRecording recording,
  ) async {
    if (!recording.isPlayable || recording.duration == null) {
      throw ArgumentError.value(recording, 'recording', '该本机录音不可用于 AI 整理。');
    }
    ResearchCapture.validateDuration(recording.duration!);
    final existing = await _repository.findByOriginalLocalRecordingId(
      recording.id,
    );
    if (existing != null) {
      return existing;
    }
    final trial = await _requireAcceptedTrial();
    final sourcePath = await _localFiles.absolutePathFor(
      recording.relativePath,
    );
    final copied = await _researchFiles.copyFromLocal(
      id: _idGenerator(),
      sourcePath: sourcePath,
    );
    final capture = ResearchCapture.fromLocalRecording(
      id: _idFromRelativePath(copied.relativePath),
      participantId: trial.participantId,
      originalLocalRecordingId: recording.id,
      relativePath: copied.relativePath,
      duration: recording.duration!,
      createdAt: _now(),
    );
    await _repository.save(capture);
    unawaited(process(capture.id));
    return capture;
  }

  Future<void> delete(String captureId) async {
    final capture = await _repository.findById(captureId);
    if (capture == null) {
      return;
    }
    try {
      await _deleteRemoteNote(capture);
    } finally {
      await _deleteLocalCapture(capture);
    }
  }

  Future<void> deleteAllResearchData() async {
    final captures = await _repository.all();
    try {
      await Future.wait(captures.map(_deleteRemoteNote));
    } finally {
      await _deleteAllLocalResearchData();
    }
  }

  Future<void> enforceRetention({DateTime? now}) async {
    final trial = await _trialStore.load();
    if (trial == null) {
      return;
    }
    final current = _dateOnly(now ?? _now());
    final contentExpiry = _dateOnly(
      trial.startedAt.add(const Duration(days: 21)),
    );
    if (current.isBefore(contentExpiry)) {
      return;
    }
    final captures = await _repository.all();
    final existing = await _repository.loadAggregate(trial.participantId);
    await _repository.saveAggregate(
      ResearchAggregate(
        participantId: trial.participantId,
        createdAt: existing?.createdAt ?? trial.startedAt,
        updatedAt: current,
        captureCount: existing?.captureCount ?? captures.length,
        handledCount:
            existing?.handledCount ??
            captures
                .where(
                  (capture) => capture.inboxState == ResearchInboxState.handled,
                )
                .length,
        usefulReuseCount: existing?.usefulReuseCount ?? 0,
        accurateFeedbackCount: existing?.accurateFeedbackCount ?? 0,
        inaccurateFeedbackCount: existing?.inaccurateFeedbackCount ?? 0,
        understoodCount: existing?.understoodCount ?? 0,
        notUnderstoodCount: existing?.notUnderstoodCount ?? 0,
      ),
    );
    try {
      await Future.wait(captures.map(_deleteRemoteNote));
    } finally {
      await _deleteAllLocalResearchData();
    }
    await _repository.deleteExpiredAggregates(
      current.subtract(const Duration(days: 365)),
    );
  }

  Future<ResearchCapture?> process(String captureId) {
    final active = _inFlight[captureId];
    if (active != null) {
      return active;
    }
    final work = _processInternal(captureId);
    _inFlight[captureId] = work;
    return work.whenComplete(() => _inFlight.remove(captureId));
  }

  Future<void> resumePending() async {
    final pending = await _repository.findNonterminal();
    await Future.wait(pending.map((capture) => process(capture.id)));
  }

  Future<ResearchCapture?> retry(String captureId) async {
    final capture = await _repository.findById(captureId);
    if (capture == null || !capture.canRetry) {
      return capture;
    }
    if (capture.processingState == ResearchProcessingState.summaryFailed) {
      return regenerateSummary(captureId);
    }
    final resumed = _resumeState(capture);
    await _repository.update(resumed);
    return process(captureId);
  }

  Future<ResearchCapture?> regenerateTranscript(String captureId) async {
    final capture = await _repository.findById(captureId);
    if (capture == null ||
        !capture.isTerminal ||
        _inFlight[captureId] != null) {
      return capture;
    }
    await _deleteRemoteNote(capture);
    await _repository.update(capture.restartTranscription());
    return process(captureId);
  }

  Future<ResearchCapture?> regenerateSummary(String captureId) async {
    final capture = await _repository.findById(captureId);
    if (capture == null ||
        !capture.isTerminal ||
        capture.jobId == null ||
        capture.rawTranscript == null ||
        _inFlight[captureId] != null) {
      return capture;
    }
    await _deleteRemoteNote(capture);
    await _repository.update(capture.restartSummary());
    return process(captureId);
  }

  Future<ResearchCapture?> _processInternal(String captureId) async {
    _processingIds.add(captureId);
    _lastError = null;
    notifyListeners();
    try {
      var capture = await _repository.findById(captureId);
      if (capture == null ||
          capture.processingState == ResearchProcessingState.completed) {
        return capture;
      }
      _reportStage(capture);
      final deadline = _now().add(_processingTimeout);

      if (capture.processingState == ResearchProcessingState.uploading) {
        capture = await _submitOrResumeJob(capture, deadline);
        if (capture.processingState == ResearchProcessingState.uploadFailed) {
          return capture;
        }
      }

      if (capture.processingState == ResearchProcessingState.transcribing) {
        capture = await _completeTranscription(capture, deadline);
        if (capture.processingState ==
                ResearchProcessingState.transcriptionFailed ||
            capture.processingState == ResearchProcessingState.summaryFailed) {
          return capture;
        }
      }

      if (capture.processingState == ResearchProcessingState.summarizing) {
        capture = await _completeSummary(capture, deadline);
      }
      return capture;
    } finally {
      _processingIds.remove(captureId);
      notifyListeners();
    }
  }

  Future<ResearchCapture> _submitOrResumeJob(
    ResearchCapture capture,
    DateTime deadline,
  ) async {
    final knownJobId = capture.jobId;
    if (knownJobId != null) {
      final resumed = capture.toTranscribing(knownJobId);
      await _repository.update(resumed);
      _reportStage(resumed);
      return resumed;
    }
    final path = await _researchFiles.absolutePathFor(capture.relativePath);
    final result = await _requestBeforeDeadline(
      _gateway.submitAudio(path),
      deadline,
    );
    if (result == null) {
      return _fail(
        capture,
        ResearchProcessingState.uploadFailed,
        '上传处理超时，请稍后重试。',
      );
    }
    if (result is AsrFailure<AsrJob>) {
      return _fail(
        capture,
        ResearchProcessingState.uploadFailed,
        result.message,
      );
    }
    final job = (result as AsrSuccess<AsrJob>).value;
    final updated = capture.toTranscribing(job.id);
    await _repository.update(updated);
    _reportStage(updated);
    return updated;
  }

  Future<ResearchCapture> _completeTranscription(
    ResearchCapture capture,
    DateTime deadline,
  ) async {
    final jobId = capture.jobId;
    if (jobId == null) {
      return _fail(
        capture,
        ResearchProcessingState.transcriptionFailed,
        '未找到可恢复的转写任务。',
      );
    }
    while (true) {
      if (!_now().isBefore(deadline)) {
        return _fail(
          capture,
          ResearchProcessingState.transcriptionFailed,
          '转写处理超时，请稍后重试。',
        );
      }
      final statusResult = await _requestBeforeDeadline(
        _gateway.pollJob(jobId),
        deadline,
      );
      if (statusResult == null) {
        return _fail(
          capture,
          ResearchProcessingState.transcriptionFailed,
          '转写处理超时，请稍后重试。',
        );
      }
      if (statusResult is AsrFailure<AsrJob>) {
        return _fail(
          capture,
          ResearchProcessingState.transcriptionFailed,
          statusResult.message,
        );
      }
      final job = (statusResult as AsrSuccess<AsrJob>).value;
      if (job.status == AsrJobStatus.pending) {
        await _delay(_nextPollDelay(capture));
        continue;
      }
      if (job.status != AsrJobStatus.completed) {
        return _fail(
          capture,
          ResearchProcessingState.transcriptionFailed,
          job.message ?? '转写处理失败。',
        );
      }
      final transcriptResult = await _requestBeforeDeadline(
        _gateway.fetchTranscript(jobId),
        deadline,
      );
      if (transcriptResult == null) {
        return _fail(
          capture,
          ResearchProcessingState.transcriptionFailed,
          '转写处理超时，请稍后重试。',
        );
      }
      if (transcriptResult is AsrFailure<AsrTranscript>) {
        return _fail(
          capture,
          ResearchProcessingState.transcriptionFailed,
          transcriptResult.message,
        );
      }
      final transcript = (transcriptResult as AsrSuccess<AsrTranscript>).value;
      // The completed transcript remains reviewable even when summary creation
      // fails or the external summary service is temporarily unavailable.
      final transcribed = capture.copyWith(rawTranscript: transcript.text);
      await _repository.update(transcribed);
      final noteResult = await _requestBeforeDeadline(
        _gateway.createNote(jobId: jobId, transcript: transcript),
        deadline,
      );
      if (noteResult == null) {
        return _fail(
          transcribed,
          ResearchProcessingState.summaryFailed,
          'AI 整理处理超时，请稍后重试。',
        );
      }
      if (noteResult is AsrFailure<AsrNoteTask>) {
        return _fail(
          transcribed,
          ResearchProcessingState.summaryFailed,
          noteResult.message,
        );
      }
      final note = (noteResult as AsrSuccess<AsrNoteTask>).value;
      final updated = transcribed.toSummarizing(
        rawTranscript: transcript.text,
        noteId: note.noteId,
        generationTaskId: note.generationTaskId,
      );
      await _repository.update(updated);
      _reportStage(updated);
      return updated;
    }
  }

  Future<ResearchCapture> _completeSummary(
    ResearchCapture capture,
    DateTime deadline,
  ) async {
    final noteId = capture.noteId;
    final taskId = capture.generationTaskId;
    if (noteId == null || taskId == null) {
      return _startSummary(capture, deadline);
    }
    while (true) {
      if (!_now().isBefore(deadline)) {
        return _fail(
          capture,
          ResearchProcessingState.summaryFailed,
          'AI 整理处理超时，请稍后重试。',
        );
      }
      final statusResult = await _requestBeforeDeadline(
        _gateway.pollGenerationTask(noteId: noteId, generationTaskId: taskId),
        deadline,
      );
      if (statusResult == null) {
        return _fail(
          capture,
          ResearchProcessingState.summaryFailed,
          'AI 整理处理超时，请稍后重试。',
        );
      }
      if (statusResult is AsrFailure<AsrGenerationStatus>) {
        return _fail(
          capture,
          ResearchProcessingState.summaryFailed,
          statusResult.message,
        );
      }
      final status = (statusResult as AsrSuccess<AsrGenerationStatus>).value;
      if (status == AsrGenerationStatus.pending) {
        await _delay(_nextPollDelay(capture));
        continue;
      }
      if (status != AsrGenerationStatus.completed) {
        return _fail(
          capture,
          ResearchProcessingState.summaryFailed,
          'AI 整理服务处理失败。',
        );
      }
      final noteResult = await _requestBeforeDeadline(
        _gateway.fetchCompletedNote(noteId),
        deadline,
      );
      if (noteResult == null) {
        return _fail(
          capture,
          ResearchProcessingState.summaryFailed,
          'AI 整理处理超时，请稍后重试。',
        );
      }
      if (noteResult is AsrFailure<AsrGeneratedNote>) {
        return _fail(
          capture,
          ResearchProcessingState.summaryFailed,
          noteResult.message,
        );
      }
      final note = (noteResult as AsrSuccess<AsrGeneratedNote>).value;
      final completed = capture.completed(
        title: note.title,
        summary: note.summary,
        tags: note.tags,
        actionContext: note.actionContext,
        completedAt: _now(),
      );
      await _repository.update(completed);
      _reportCompletion(completed);
      return completed;
    }
  }

  Future<ResearchCapture> _startSummary(
    ResearchCapture capture,
    DateTime deadline,
  ) async {
    final jobId = capture.jobId;
    final editedTranscript = capture.rawTranscript?.trim();
    if (jobId == null || editedTranscript == null || editedTranscript.isEmpty) {
      return _fail(
        capture,
        ResearchProcessingState.summaryFailed,
        '未找到可用于生成总结的转写内容。',
      );
    }
    final transcriptResult = await _requestBeforeDeadline(
      _gateway.fetchTranscript(jobId),
      deadline,
    );
    if (transcriptResult == null) {
      return _fail(
        capture,
        ResearchProcessingState.summaryFailed,
        'AI 整理处理超时，请稍后重试。',
      );
    }
    if (transcriptResult is AsrFailure<AsrTranscript>) {
      return _fail(
        capture,
        ResearchProcessingState.summaryFailed,
        transcriptResult.message,
      );
    }
    final source = (transcriptResult as AsrSuccess<AsrTranscript>).value;
    final noteResult = await _requestBeforeDeadline(
      _gateway.createNote(
        jobId: jobId,
        transcript: AsrTranscript(
          text: editedTranscript,
          relativePath: source.relativePath,
          variant: source.variant,
          engine: source.engine,
        ),
      ),
      deadline,
    );
    if (noteResult == null) {
      return _fail(
        capture,
        ResearchProcessingState.summaryFailed,
        'AI 整理处理超时，请稍后重试。',
      );
    }
    if (noteResult is AsrFailure<AsrNoteTask>) {
      return _fail(
        capture,
        ResearchProcessingState.summaryFailed,
        noteResult.message,
      );
    }
    final note = (noteResult as AsrSuccess<AsrNoteTask>).value;
    final updated = capture.toSummarizing(
      rawTranscript: editedTranscript,
      noteId: note.noteId,
      generationTaskId: note.generationTaskId,
    );
    await _repository.update(updated);
    return _completeSummary(updated, deadline);
  }

  Future<ResearchCapture> _fail(
    ResearchCapture capture,
    ResearchProcessingState state,
    String message,
  ) async {
    _lastError = message;
    final failed = capture.failed(state, message);
    await _repository.update(failed);
    return failed;
  }

  void _reportStage(ResearchCapture capture) {
    final kind = switch (capture.processingState) {
      ResearchProcessingState.transcribing =>
        ResearchCaptureUiUpdateKind.transcribing,
      ResearchProcessingState.summarizing =>
        ResearchCaptureUiUpdateKind.summarizing,
      _ => null,
    };
    if (kind == null) {
      return;
    }
    _pendingUiUpdates.add(
      ResearchCaptureUiUpdate(captureId: capture.id, kind: kind),
    );
    notifyListeners();
  }

  void _reportCompletion(ResearchCapture capture) {
    final completedAt = capture.completedAt;
    if (completedAt == null) {
      return;
    }
    _pendingUiUpdates.add(
      ResearchCaptureUiUpdate(
        captureId: capture.id,
        kind: ResearchCaptureUiUpdateKind.completed,
        completedAt: completedAt,
      ),
    );
    _completedCaptures.add(capture);
    notifyListeners();
  }

  Duration _nextPollDelay(ResearchCapture capture) {
    final elapsed = _now().difference(capture.createdAt);
    return _pollSchedule.nextDelay(
      elapsed.isNegative ? Duration.zero : elapsed,
    );
  }

  Future<void> _deleteRemoteNote(ResearchCapture capture) async {
    final noteId = capture.noteId;
    if (noteId == null) {
      return;
    }
    try {
      final result = await _gateway
          .deleteNote(noteId)
          .timeout(_remoteDeleteTimeout);
      if (result is AsrFailure<void>) {
        await _recordRemoteDeleteFailure(capture, result.message);
      }
    } on TimeoutException {
      await _recordRemoteDeleteFailure(capture, 'AI 整理远端删除超时。');
    } catch (_) {
      await _recordRemoteDeleteFailure(capture, 'AI 整理远端删除失败。');
    }
  }

  Future<void> _deleteLocalCapture(ResearchCapture capture) async {
    try {
      await _researchFiles.delete(capture.relativePath);
    } catch (_) {
      // Local metadata must still be removable when an old file is absent.
    } finally {
      await _repository.delete(capture.id);
    }
  }

  Future<void> _deleteAllLocalResearchData() async {
    try {
      await _researchFiles.deleteAll();
    } finally {
      try {
        await _repository.deleteAllCaptures();
      } finally {
        await _repository.deleteAllEvents();
      }
    }
  }

  Future<AsrOutcome<T>?> _requestBeforeDeadline<T>(
    Future<AsrOutcome<T>> request,
    DateTime deadline,
  ) async {
    final remaining = deadline.difference(_now());
    if (remaining <= Duration.zero) {
      return null;
    }
    try {
      return await request.timeout(remaining);
    } on TimeoutException {
      return null;
    }
  }

  Future<ResearchTrial> _requireAcceptedTrial() async {
    final trial = await _trialStore.load();
    if (trial == null || !trial.hasAcceptedConsent) {
      throw StateError('请先同意 AI 语音研究说明。');
    }
    return trial;
  }

  ResearchCapture _resumeState(ResearchCapture capture) {
    if (capture.noteId != null && capture.generationTaskId != null) {
      return capture.copyWith(
        processingState: ResearchProcessingState.summarizing,
        inboxState: ResearchInboxState.processing,
        failureReason: '',
      );
    }
    if (capture.jobId != null) {
      return capture.copyWith(
        processingState: ResearchProcessingState.transcribing,
        inboxState: ResearchInboxState.processing,
        failureReason: '',
      );
    }
    return capture.copyWith(
      processingState: ResearchProcessingState.uploading,
      inboxState: ResearchInboxState.processing,
      failureReason: '',
    );
  }

  Future<void> _recordRemoteDeleteFailure(
    ResearchCapture capture,
    String message,
  ) {
    return _repository.saveEvent(
      ResearchEvent(
        id: '${capture.id}-${_now().microsecondsSinceEpoch}-remote-delete',
        participantId: capture.participantId,
        captureId: capture.id,
        type: ResearchEventType.remoteDeleteFailed,
        occurredAt: _now(),
        elapsedMilliseconds: message.length,
      ),
    );
  }

  static DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  static String _idFromRelativePath(String relativePath) {
    return relativePath.replaceFirst(RegExp(r'\.m4a$'), '');
  }
}
