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

  test(
    'renames only the requested document and records an edit action',
    () async {
      final capture = _completedCapture().withDocumentTitle(
        ResearchDocumentType.summary,
        '原总结名称',
      );
      await repository.save(capture);

      await controller.renameDocument(
        capture,
        ResearchDocumentType.transcript,
        '  访谈:转写.txt ',
      );

      final saved = repository.captures[capture.id]!;
      expect(saved.transcriptTitle, '访谈转写');
      expect(saved.summaryTitle, '原总结名称');
      expect(saved.inboxState, ResearchInboxState.handled);
      expect(repository.events.single.action, ResearchCardAction.edited);
    },
  );

  test('rejects an empty or fully illegal document name', () async {
    final capture = _completedCapture().withDocumentTitle(
      ResearchDocumentType.summary,
      '已有名称',
    );
    await repository.save(capture);

    await expectLater(
      controller.renameDocument(
        capture,
        ResearchDocumentType.summary,
        ' \\ / : * ? " < > | ',
      ),
      throwsArgumentError,
    );

    expect(repository.captures[capture.id]!.summaryTitle, '已有名称');
    expect(repository.events, isEmpty);
  });

  test('does not record an edit when a document name is unchanged', () async {
    final capture = _completedCapture();
    await repository.save(capture);

    await controller.renameDocument(
      capture,
      ResearchDocumentType.transcript,
      '转写',
    );

    final saved = repository.captures[capture.id]!;
    expect(saved.transcriptTitle, isNull);
    expect(saved.inboxState, ResearchInboxState.needsReview);
    expect(repository.events, isEmpty);
    expect(await repository.loadAggregate(capture.participantId), isNull);
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
