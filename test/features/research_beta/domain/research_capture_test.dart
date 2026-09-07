import 'package:aipin/features/research_beta/domain/research_capture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'local upload keeps an immutable reference to its original recording',
    () {
      final capture = ResearchCapture.fromLocalRecording(
        id: 'capture-1',
        participantId: 'participant-1',
        originalLocalRecordingId: 'local-1',
        relativePath: 'research_captures/capture-1.m4a',
        duration: const Duration(seconds: 12),
        createdAt: DateTime(2026, 8, 24),
      );

      expect(capture.origin, ResearchCaptureOrigin.localRecordingUpload);
      expect(capture.originalLocalRecordingId, 'local-1');
      expect(capture.sourceType, ResearchCapture.sourceTypeResearchImport);
      expect(capture.processingState, ResearchProcessingState.uploading);
      expect(capture.inboxState, ResearchInboxState.processing);
    },
  );

  test('AI Voice duration must be at least two seconds', () {
    expect(
      () => ResearchCapture.validateDuration(const Duration(seconds: 1)),
      throwsArgumentError,
    );
    expect(
      () => ResearchCapture.validateDuration(const Duration(hours: 2)),
      returnsNormally,
    );
    expect(
      () => ResearchCapture.validateDuration(const Duration(seconds: 2)),
      returnsNormally,
    );
  });

  test('completing a capture makes it available for review', () {
    final capture = ResearchCapture.fromDirectAiVoice(
      id: 'capture-1',
      participantId: 'participant-1',
      relativePath: 'research_captures/capture-1.m4a',
      duration: const Duration(seconds: 12),
      createdAt: DateTime(2026, 8, 24),
    );

    final completed = capture.completed(
      title: '整理后的标题',
      summary: '整理后的摘要',
      tags: const ['工作'],
      completedAt: DateTime(2026, 8, 24, 10),
    );

    expect(completed.processingState, ResearchProcessingState.completed);
    expect(completed.inboxState, ResearchInboxState.needsReview);
    expect(completed.title, '整理后的标题');
  });

  test('keeps independent document names when processing is restarted', () {
    final capture =
        ResearchCapture.fromDirectAiVoice(
              id: 'capture-1',
              participantId: 'participant-1',
              relativePath: 'research_captures/capture-1.m4a',
              duration: const Duration(seconds: 12),
              createdAt: DateTime(2026, 8, 24),
            )
            .withDocumentTitle(ResearchDocumentType.transcript, '访谈转写')
            .withDocumentTitle(ResearchDocumentType.summary, '访谈纪要');

    expect(capture.transcriptTitle, '访谈转写');
    expect(capture.summaryTitle, '访谈纪要');
    expect(capture.documentTitle(ResearchDocumentType.transcript), '访谈转写');
    expect(capture.documentTitle(ResearchDocumentType.summary), '访谈纪要');
    expect(capture.restartTranscription().transcriptTitle, '访谈转写');
    expect(capture.restartTranscription().summaryTitle, '访谈纪要');
    expect(capture.restartSummary().transcriptTitle, '访谈转写');
    expect(capture.restartSummary().summaryTitle, '访谈纪要');
  });
}
