import 'package:aipin/features/research_beta/application/research_capture_library_controller.dart';
import 'package:aipin/features/research_beta/domain/research_analytics.dart';
import 'package:aipin/features/research_beta/domain/research_capture.dart';
import 'package:aipin/features/research_beta/domain/research_trial.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_research_beta.dart';

void main() {
  late FakeResearchCaptureRepository repository;
  late FakeResearchTrialStore trialStore;
  late ResearchCaptureLibraryController controller;

  setUp(() {
    repository = FakeResearchCaptureRepository();
    trialStore = FakeResearchTrialStore(
      ResearchTrial.newParticipant(
        participantId: 'participant-1',
        startedAt: DateTime(2026, 8, 24),
      ).accepted(DateTime(2026, 8, 24)),
    );
    controller = ResearchCaptureLibraryController(
      repository: repository,
      trialStore: trialStore,
      now: () => DateTime(2026, 8, 25, 10),
    );
  });

  test(
    'quality feedback records an aggregate event without card content',
    () async {
      final capture = _completedCapture();

      await controller.recordTranscriptQuality(capture, isAccurate: true);

      expect(repository.events, hasLength(1));
      expect(repository.events.single.type, ResearchEventType.qualityFeedback);
      expect(repository.events.single.qualityFeedback, isTrue);
      expect(
        (await repository.loadAggregate(
          'participant-1',
        ))!.accurateFeedbackCount,
        1,
      );
    },
  );

  test(
    'daily understanding stores one answer for the local calendar day',
    () async {
      final capture = _completedCapture();

      expect(
        await controller.recordDailyUnderstanding(capture, understood: false),
        isTrue,
      );
      expect(
        await controller.recordDailyUnderstanding(capture, understood: true),
        isFalse,
      );

      expect(repository.events, hasLength(1));
      expect(
        repository.events.single.type,
        ResearchEventType.dailyUnderstanding,
      );
      expect(repository.events.single.dailyUnderstanding, isFalse);
      expect(
        (await repository.loadAggregate('participant-1'))!.notUnderstoodCount,
        1,
      );
    },
  );

  test('saves an edited Markdown summary and records an edit action', () async {
    final capture = _completedCapture();
    await repository.save(capture);

    await controller.saveMarkdownSummary(capture, '# 会议总结\n\n- 明日确认方案');

    expect(repository.captures[capture.id]!.summary, '# 会议总结\n\n- 明日确认方案');
    expect(
      repository.captures[capture.id]!.inboxState,
      ResearchInboxState.handled,
    );
    expect(repository.events.single.type, ResearchEventType.captureHandled);
    expect(repository.events.single.action, ResearchCardAction.edited);
  });

  test('saves a direct transcript edit as the transcript text', () async {
    final capture = _completedCapture().copyWith(
      rawTranscript: '原始转写',
      correctedTranscript: '旧校正内容',
    );
    await repository.save(capture);

    await controller.saveTranscript(capture, '编辑后的转写');

    final saved = repository.captures[capture.id]!;
    expect(saved.rawTranscript, '编辑后的转写');
    expect(saved.correctedTranscript, '旧校正内容');
    expect(saved.inboxState, ResearchInboxState.handled);
    expect(repository.events.single.action, ResearchCardAction.edited);
  });
}

ResearchCapture _completedCapture() {
  return ResearchCapture.fromDirectAiVoice(
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
      .completed(
        title: '标题',
        summary: '摘要',
        tags: const <String>[],
        completedAt: DateTime(2026, 8, 24, 10),
      );
}
