// ignore_for_file: prefer_initializing_formals

import 'package:aipin/features/research_beta/domain/research_analytics.dart';
import 'package:aipin/features/research_beta/domain/research_capture.dart';
import 'package:aipin/features/research_beta/domain/research_capture_repository.dart';
import 'package:aipin/features/research_beta/domain/research_trial.dart';
import 'package:aipin/core/documents/document_file_name.dart';
import 'package:uuid/uuid.dart';

class ResearchCaptureLibraryController {
  ResearchCaptureLibraryController({
    required ResearchCaptureRepository repository,
    required ResearchTrialStore trialStore,
    String Function()? participantIdGenerator,
    DateTime Function()? now,
  }) : _repository = repository,
       _trialStore = trialStore,
       _participantIdGenerator = participantIdGenerator ?? const Uuid().v4,
       _now = now ?? DateTime.now;

  final ResearchCaptureRepository _repository;
  final ResearchTrialStore _trialStore;
  final String Function() _participantIdGenerator;
  final DateTime Function() _now;

  Future<ResearchTrial> acceptConsent() async {
    final now = _now();
    final current = await _trialStore.load();
    final trial =
        (current ??
                ResearchTrial.newParticipant(
                  participantId: _participantIdGenerator(),
                  startedAt: now,
                ))
            .accepted(now);
    await _trialStore.save(trial);
    return trial;
  }

  Future<bool> hasAcceptedConsent() async =>
      (await _trialStore.load())?.hasAcceptedConsent ?? false;

  Future<void> markHandled(
    ResearchCapture capture,
    ResearchCardAction action,
  ) async {
    final handledAt = _now();
    await _repository.update(capture.handled(handledAt));
    await _repository.saveEvent(
      ResearchEvent.captureHandled(
        participantId: capture.participantId,
        captureId: capture.id,
        action: action,
        duration: capture.duration,
        occurredAt: handledAt,
      ),
    );
    final existing = await _repository.loadAggregate(capture.participantId);
    final aggregate =
        existing ??
        ResearchAggregate.empty(
          participantId: capture.participantId,
          createdAt: handledAt,
        );
    await _repository.saveAggregate(aggregate.recordAction(action));
  }

  Future<void> markOpened(ResearchCapture capture) async {
    await _repository.update(capture.opened(_now()));
  }

  Future<void> saveTranscript(
    ResearchCapture capture,
    String transcript,
  ) async {
    final normalized = transcript.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(transcript, 'transcript', '转写不能为空。');
    }
    await markHandled(
      capture.copyWith(rawTranscript: normalized),
      ResearchCardAction.edited,
    );
  }

  Future<void> saveMarkdownSummary(
    ResearchCapture capture,
    String summary,
  ) async {
    final normalized = summary.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(summary, 'summary', 'Markdown 总结不能为空。');
    }
    await markHandled(
      capture.copyWith(summary: normalized),
      ResearchCardAction.edited,
    );
  }

  Future<void> renameDocument(
    ResearchCapture capture,
    ResearchDocumentType type,
    String requestedTitle,
  ) async {
    final normalized = DocumentFileName.normalizeCustomBaseName(requestedTitle);
    if (normalized == null) {
      throw ArgumentError.value(requestedTitle, 'requestedTitle', '文档名称不能为空。');
    }
    if (normalized == capture.documentTitle(type)) {
      return;
    }
    await markHandled(
      capture.withDocumentTitle(type, normalized),
      ResearchCardAction.edited,
    );
  }

  Future<bool> shouldAskDailyUnderstanding(ResearchCapture capture) async {
    if (capture.processingState != ResearchProcessingState.completed) {
      return false;
    }
    final trial = await _trialStore.load();
    if (trial == null) {
      return false;
    }
    final today = _dateOnly(_now());
    return trial.lastDailyUnderstandingPromptOn != today;
  }

  Future<void> markDailyUnderstandingPrompted() async {
    final trial = await _trialStore.load();
    if (trial != null) {
      await _trialStore.save(trial.markDailyUnderstandingPrompted(_now()));
    }
  }

  Future<void> recordTranscriptQuality(
    ResearchCapture capture, {
    required bool isAccurate,
  }) async {
    final occurredAt = _now();
    await _repository.saveEvent(
      ResearchEvent(
        id: '${capture.id}-${occurredAt.microsecondsSinceEpoch}-quality',
        participantId: capture.participantId,
        captureId: capture.id,
        type: ResearchEventType.qualityFeedback,
        occurredAt: occurredAt,
        durationBucket: ResearchEvent.durationBucketFor(capture.duration),
        qualityFeedback: isAccurate,
      ),
    );
    final aggregate = await _aggregateFor(capture, occurredAt);
    await _repository.saveAggregate(
      aggregate.recordQualityFeedback(
        isAccurate: isAccurate,
        occurredAt: occurredAt,
      ),
    );
  }

  Future<bool> recordDailyUnderstanding(
    ResearchCapture capture, {
    required bool understood,
  }) async {
    if (!await shouldAskDailyUnderstanding(capture)) {
      return false;
    }
    final occurredAt = _now();
    final trial = await _trialStore.load();
    if (trial == null) {
      return false;
    }
    await _trialStore.save(trial.markDailyUnderstandingPrompted(occurredAt));
    await _repository.saveEvent(
      ResearchEvent(
        id: '${capture.id}-${occurredAt.microsecondsSinceEpoch}-understanding',
        participantId: capture.participantId,
        captureId: capture.id,
        type: ResearchEventType.dailyUnderstanding,
        occurredAt: occurredAt,
        durationBucket: ResearchEvent.durationBucketFor(capture.duration),
        dailyUnderstanding: understood,
      ),
    );
    final aggregate = await _aggregateFor(capture, occurredAt);
    await _repository.saveAggregate(
      aggregate.recordDailyUnderstanding(
        understood: understood,
        occurredAt: occurredAt,
      ),
    );
    return true;
  }

  Future<ResearchAggregate> _aggregateFor(
    ResearchCapture capture,
    DateTime occurredAt,
  ) async {
    return await _repository.loadAggregate(capture.participantId) ??
        ResearchAggregate.empty(
          participantId: capture.participantId,
          createdAt: occurredAt,
        );
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
