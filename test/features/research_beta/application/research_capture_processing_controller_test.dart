import 'dart:async';

import 'package:aipin/features/local_recording/domain/local_recording.dart';
import 'package:aipin/features/research_beta/application/research_capture_processing_controller.dart';
import 'package:aipin/features/research_beta/application/research_processing_poll_schedule.dart';
import 'package:aipin/features/research_beta/domain/research_capture.dart';
import 'package:aipin/features/research_beta/domain/research_trial.dart';
import 'package:aipin/features/research_beta/domain/temporary_asr_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_recording_file_store.dart';
import '../../../support/fake_research_beta.dart';

void main() {
  late FakeResearchCaptureRepository repository;
  late FakeResearchCaptureFileStore files;
  late FakeTemporaryAsrGateway gateway;
  late ResearchCaptureProcessingController controller;

  setUp(() {
    repository = FakeResearchCaptureRepository();
    files = FakeResearchCaptureFileStore();
    gateway = FakeTemporaryAsrGateway();
    controller = ResearchCaptureProcessingController(
      repository: repository,
      researchFiles: files,
      localFiles: FakeRecordingFileStore(),
      gateway: gateway,
      trialStore: FakeResearchTrialStore(
        ResearchTrial.newParticipant(
          participantId: 'participant-1',
          startedAt: DateTime(2026, 8, 24),
        ).accepted(DateTime(2026, 8, 24)),
      ),
      idGenerator: () => 'capture-1',
      now: () => DateTime(2026, 8, 24, 10),
      delay: (_) async {},
    );
  });

  test(
    'recovery resumes from saved job ID without resubmitting audio',
    () async {
      await repository.save(
        ResearchCapture.fromDirectAiVoice(
          id: 'capture-1',
          participantId: 'participant-1',
          relativePath: 'capture-1.m4a',
          duration: const Duration(seconds: 12),
          createdAt: DateTime(2026, 8, 24),
        ).toTranscribing('job-1'),
      );

      await controller.resumePending();

      expect(gateway.submitCount, 0);
      expect(gateway.pollJobIds, <String>['job-1']);
      expect(
        (await repository.findById('capture-1'))!.processingState,
        ResearchProcessingState.completed,
      );
    },
  );

  test(
    'local upload is copied once and never resubmitted for same recording',
    () async {
      final local = LocalRecording.saved(
        id: 'local-1',
        title: '本机录音',
        relativePath: 'local-1.m4a',
        createdAt: DateTime(2026, 8, 24),
        completedAt: DateTime(2026, 8, 24, 9),
        duration: const Duration(seconds: 12),
        sizeBytes: 12,
      );

      final first = await controller.createFromLocalRecording(local);
      await controller.process(first.id);
      final second = await controller.createFromLocalRecording(local);

      expect(first.id, second.id);
      expect(files.copiedSources, <String>['/recordings/local-1.m4a']);
      expect(gateway.submitCount, 1);
    },
  );

  test(
    'retains a completed transcript when AI summary creation fails',
    () async {
      gateway.noteOutcome = const AsrFailure<AsrNoteTask>(
        kind: AsrFailureKind.remote,
        message: 'AI 整理服务暂不可用。',
      );
      await repository.save(
        ResearchCapture.fromDirectAiVoice(
          id: 'capture-1',
          participantId: 'participant-1',
          relativePath: 'capture-1.m4a',
          duration: const Duration(seconds: 12),
          createdAt: DateTime(2026, 8, 24),
        ).toTranscribing('job-1'),
      );

      await controller.process('capture-1');

      final capture = await repository.findById('capture-1');
      expect(capture!.processingState, ResearchProcessingState.summaryFailed);
      expect(capture.rawTranscript, '机器转写');
      expect(capture.failureReason, 'AI 整理服务暂不可用。');
    },
  );

  test(
    'retrying a failed summary recreates it without resubmitting audio',
    () async {
      await repository.save(
        ResearchCapture.fromDirectAiVoice(
              id: 'capture-1',
              participantId: 'participant-1',
              relativePath: 'capture-1.m4a',
              duration: const Duration(seconds: 12),
              createdAt: DateTime(2026, 8, 24),
            )
            .toTranscribing('job-1')
            .toSummarizing(
              rawTranscript: '机器转写',
              noteId: 'note-1',
              generationTaskId: 'task-1',
            )
            .failed(ResearchProcessingState.summaryFailed, 'AI 整理服务暂不可用。'),
      );

      await controller.retry('capture-1');

      final saved = await repository.findById('capture-1');
      expect(gateway.deletedNoteIds, <String>['note-1']);
      expect(gateway.noteRequestCount, 1);
      expect(gateway.submitCount, 0);
      expect(saved!.processingState, ResearchProcessingState.completed);
    },
  );

  test(
    'regenerating a completed transcript resubmits audio and replaces stale content',
    () async {
      await repository.save(
        ResearchCapture.fromDirectAiVoice(
              id: 'capture-1',
              participantId: 'participant-1',
              relativePath: 'capture-1.m4a',
              duration: const Duration(seconds: 12),
              createdAt: DateTime(2026, 8, 24),
            )
            .toTranscribing('old-job')
            .toSummarizing(
              rawTranscript: '旧转写',
              noteId: 'old-note',
              generationTaskId: 'old-task',
            )
            .completed(
              title: '旧标题',
              summary: '旧总结',
              tags: const ['旧标签'],
              completedAt: DateTime(2026, 8, 24, 11),
            ),
      );

      await controller.regenerateTranscript('capture-1');

      final capture = await repository.findById('capture-1');
      expect(gateway.deletedNoteIds, <String>['old-note']);
      expect(gateway.submitCount, 1);
      expect(capture!.rawTranscript, '机器转写');
      expect(capture.summary, '摘要');
      expect(capture.processingState, ResearchProcessingState.completed);
    },
  );

  test(
    'regenerating a completed summary keeps edited transcript without reuploading',
    () async {
      await repository.save(
        ResearchCapture.fromDirectAiVoice(
              id: 'capture-1',
              participantId: 'participant-1',
              relativePath: 'capture-1.m4a',
              duration: const Duration(seconds: 12),
              createdAt: DateTime(2026, 8, 24),
            )
            .toTranscribing('job-1')
            .toSummarizing(
              rawTranscript: '人工修改后的转写',
              noteId: 'old-note',
              generationTaskId: 'old-task',
            )
            .completed(
              title: '旧标题',
              summary: '旧总结',
              tags: const ['旧标签'],
              completedAt: DateTime(2026, 8, 24, 11),
            ),
      );

      await controller.regenerateSummary('capture-1');

      final capture = await repository.findById('capture-1');
      expect(gateway.deletedNoteIds, <String>['old-note']);
      expect(gateway.submitCount, 0);
      expect(gateway.createdNoteTranscripts, <String>['人工修改后的转写']);
      expect(capture!.rawTranscript, '人工修改后的转写');
      expect(capture.summary, '摘要');
      expect(capture.processingState, ResearchProcessingState.completed);
    },
  );

  test('uses the capture age for each pending transcription delay', () async {
    final startedAt = DateTime(2026, 8, 25, 10);
    final schedule = _RecordingPollSchedule();
    final pendingGateway = _PendingThenCompletedGateway();
    final progressiveController = ResearchCaptureProcessingController(
      repository: repository,
      researchFiles: files,
      localFiles: FakeRecordingFileStore(),
      gateway: pendingGateway,
      trialStore: FakeResearchTrialStore(
        ResearchTrial.newParticipant(
          participantId: 'participant-1',
          startedAt: DateTime(2026, 8, 24),
        ).accepted(DateTime(2026, 8, 24)),
      ),
      now: () => startedAt.add(const Duration(minutes: 2)),
      delay: (_) async {},
      pollSchedule: schedule,
    );
    addTearDown(progressiveController.dispose);
    await repository.save(
      ResearchCapture.fromDirectAiVoice(
        id: 'capture-1',
        participantId: 'participant-1',
        relativePath: 'capture-1.m4a',
        duration: const Duration(seconds: 12),
        createdAt: startedAt,
      ).toTranscribing('job-1'),
    );

    await progressiveController.process('capture-1');

    expect(schedule.elapsedValues, <Duration>[const Duration(minutes: 2)]);
  });

  test(
    'completed captures are emitted once until completion notices are drained',
    () async {
      await repository.save(
        ResearchCapture.fromDirectAiVoice(
          id: 'capture-1',
          participantId: 'participant-1',
          relativePath: 'capture-1.m4a',
          duration: const Duration(seconds: 12),
          createdAt: DateTime(2026, 8, 25, 10),
        ).toTranscribing('job-1'),
      );

      await controller.process('capture-1');

      expect(controller.drainCompletedCaptures().single.id, 'capture-1');
      expect(controller.drainCompletedCaptures(), isEmpty);
    },
  );

  test('emits transcription summary and completion updates in order', () async {
    await repository.save(
      ResearchCapture.fromDirectAiVoice(
        id: 'capture-1',
        participantId: 'participant-1',
        relativePath: 'capture-1.m4a',
        duration: const Duration(seconds: 12),
        createdAt: DateTime(2026, 8, 25, 10),
      ).toTranscribing('job-1'),
    );

    await controller.process('capture-1');
    final updates = controller.drainUiUpdates();

    expect(updates.map((update) => update.kind), <ResearchCaptureUiUpdateKind>[
      ResearchCaptureUiUpdateKind.transcribing,
      ResearchCaptureUiUpdateKind.summarizing,
      ResearchCaptureUiUpdateKind.completed,
    ]);
    expect(updates.every((update) => update.captureId == 'capture-1'), isTrue);
    expect(updates.last.completedAt, DateTime(2026, 8, 24, 10));
  });

  test(
    'retention day clears content and preserves aggregate-only counts',
    () async {
      await repository.save(
        ResearchCapture.fromDirectAiVoice(
              id: 'capture-1',
              participantId: 'participant-1',
              relativePath: 'capture-1.m4a',
              duration: const Duration(seconds: 12),
              createdAt: DateTime(2026, 8, 24),
            )
            .toTranscribing('job-1')
            .toSummarizing(
              rawTranscript: '机器转写',
              noteId: 'note-1',
              generationTaskId: 'task-1',
            ),
      );

      await controller.enforceRetention(now: DateTime(2026, 9, 14));

      expect(await repository.findById('capture-1'), isNull);
      expect(
        (await repository.loadAggregate('participant-1'))!.captureCount,
        1,
      );
      expect(files.deletedPaths, contains('*'));
      expect(gateway.deletedNoteIds, <String>['note-1']);
    },
  );

  test(
    'remote deletion exceptions do not block local capture cleanup',
    () async {
      gateway.deleteError = StateError('remote unavailable');
      await repository.save(
        ResearchCapture.fromDirectAiVoice(
          id: 'capture-1',
          participantId: 'participant-1',
          relativePath: 'capture-1.m4a',
          duration: const Duration(seconds: 12),
          createdAt: DateTime(2026, 8, 24),
        ).toSummarizing(
          rawTranscript: '机器转写',
          noteId: 'note-1',
          generationTaskId: 'task-1',
        ),
      );

      await controller.delete('capture-1');

      expect(await repository.findById('capture-1'), isNull);
      expect(files.deletedPaths, contains('capture-1.m4a'));
    },
  );

  test(
    'a stalled upload reaches a retryable failure by its deadline',
    () async {
      final stalled = _StalledSubmitGateway();
      final timeoutController = ResearchCaptureProcessingController(
        repository: repository,
        researchFiles: files,
        localFiles: FakeRecordingFileStore(),
        gateway: stalled,
        trialStore: FakeResearchTrialStore(
          ResearchTrial.newParticipant(
            participantId: 'participant-1',
            startedAt: DateTime(2026, 8, 24),
          ).accepted(DateTime(2026, 8, 24)),
        ),
        now: () => DateTime(2026, 8, 24, 10),
        processingTimeout: const Duration(milliseconds: 10),
      );
      addTearDown(timeoutController.dispose);
      await repository.save(
        ResearchCapture.fromDirectAiVoice(
          id: 'capture-1',
          participantId: 'participant-1',
          relativePath: 'capture-1.m4a',
          duration: const Duration(seconds: 12),
          createdAt: DateTime(2026, 8, 24),
        ),
      );

      final capture = await timeoutController
          .process('capture-1')
          .timeout(const Duration(milliseconds: 100));

      expect(capture!.processingState, ResearchProcessingState.uploadFailed);
      expect(capture.canRetry, isTrue);
    },
  );

  test(
    'default processing deadline permits an upload that exceeds 10 minutes',
    () async {
      final startedAt = DateTime(2026, 8, 24, 10);
      var nowCalls = 0;
      final longAudioController = ResearchCaptureProcessingController(
        repository: repository,
        researchFiles: files,
        localFiles: FakeRecordingFileStore(),
        gateway: gateway,
        trialStore: FakeResearchTrialStore(
          ResearchTrial.newParticipant(
            participantId: 'participant-1',
            startedAt: DateTime(2026, 8, 24),
          ).accepted(DateTime(2026, 8, 24)),
        ),
        now: () {
          nowCalls += 1;
          return nowCalls == 1
              ? startedAt
              : startedAt.add(const Duration(minutes: 10, seconds: 1));
        },
        delay: (_) async {},
      );
      addTearDown(longAudioController.dispose);
      await repository.save(
        ResearchCapture.fromDirectAiVoice(
          id: 'capture-1',
          participantId: 'participant-1',
          relativePath: 'capture-1.m4a',
          duration: const Duration(minutes: 30),
          createdAt: startedAt,
        ),
      );

      final capture = await longAudioController.process('capture-1');

      expect(capture!.processingState, ResearchProcessingState.completed);
    },
  );
}

class _StalledSubmitGateway extends FakeTemporaryAsrGateway {
  @override
  Future<AsrOutcome<AsrJob>> submitAudio(String absoluteAudioPath) =>
      Completer<AsrOutcome<AsrJob>>().future;
}

class _RecordingPollSchedule extends ResearchProcessingPollSchedule {
  final List<Duration> elapsedValues = <Duration>[];

  @override
  Duration nextDelay(Duration elapsed) {
    elapsedValues.add(elapsed);
    return super.nextDelay(elapsed);
  }
}

class _PendingThenCompletedGateway extends FakeTemporaryAsrGateway {
  var _isFirstPoll = true;

  @override
  Future<AsrOutcome<AsrJob>> pollJob(String jobId) async {
    pollJobIds.add(jobId);
    if (_isFirstPoll) {
      _isFirstPoll = false;
      return AsrSuccess(AsrJob(id: jobId, status: AsrJobStatus.pending));
    }
    return AsrSuccess(AsrJob(id: jobId, status: AsrJobStatus.completed));
  }
}
