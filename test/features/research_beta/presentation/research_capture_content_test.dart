import 'package:aipin/features/research_beta/domain/research_capture.dart';
import 'package:aipin/features/research_beta/presentation/research_capture_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows a simple transcription loading state', (tester) async {
    final capture = ResearchCapture(
      id: 'capture-1',
      participantId: 'participant-1',
      origin: ResearchCaptureOrigin.directAiVoice,
      sourceType: ResearchCapture.sourceTypeResearchImport,
      relativePath: 'recordings/capture-1.m4a',
      duration: const Duration(minutes: 30),
      createdAt: DateTime(2026, 8, 25),
      processingState: ResearchProcessingState.transcribing,
      inboxState: ResearchInboxState.processing,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResearchCaptureTranscriptPanel(
            capture: capture,
            onSaveTranscript: (_) async {},
            onRetry: () async {},
            onCopy: (_) async {},
            onExport: (_) async {},
          ),
        ),
      ),
    );

    expect(find.text('正在转写'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('researchProcessingLoader')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('researchProcessingProgress')),
      findsNothing,
    );
    expect(find.textContaining('第 '), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('转写准确吗？'), findsNothing);
    expect(find.text('准确'), findsNothing);
    expect(find.text('不准确'), findsNothing);
  });

  testWidgets('shows a simple summary loading state', (tester) async {
    final capture = ResearchCapture(
      id: 'capture-1',
      participantId: 'participant-1',
      origin: ResearchCaptureOrigin.directAiVoice,
      sourceType: ResearchCapture.sourceTypeResearchImport,
      relativePath: 'recordings/capture-1.m4a',
      duration: const Duration(seconds: 10),
      createdAt: DateTime(2026, 8, 25),
      processingState: ResearchProcessingState.summarizing,
      inboxState: ResearchInboxState.processing,
      rawTranscript: '机器转写内容',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResearchCaptureSummaryPanel(
            capture: capture,
            onRetry: () async {},
            onSaveMarkdownSummary: (_) async {},
            onCopy: (_) async {},
            onExport: (_) async {},
          ),
        ),
      ),
    );

    expect(find.text('正在总结'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('researchProcessingLoader')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('researchProcessingProgress')),
      findsNothing,
    );
    expect(find.textContaining('第 '), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('hides internal fields from a persisted legacy summary', (
    tester,
  ) async {
    const legacySummary = '''## 概览

- **entry_id**
  - internal-id
- **text**
  - 确定上线时间。
- **evidence**
  - **text**
    - 原始依据文本。
  - **time_state**
    - no_time_evidence''';
    final capture = ResearchCapture(
      id: 'capture-1',
      participantId: 'participant-1',
      origin: ResearchCaptureOrigin.directAiVoice,
      sourceType: ResearchCapture.sourceTypeResearchImport,
      relativePath: 'recordings/capture-1.m4a',
      duration: const Duration(seconds: 10),
      createdAt: DateTime(2026, 8, 25),
      processingState: ResearchProcessingState.completed,
      inboxState: ResearchInboxState.needsReview,
      summary: legacySummary,
      tags: const ['团队标签'],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResearchCaptureSummaryPanel(
            capture: capture,
            onRetry: () async {},
            onSaveMarkdownSummary: (_) async {},
            onCopy: (_) async {},
            onExport: (_) async {},
          ),
        ),
      ),
    );

    expect(find.text('确定上线时间。'), findsOneWidget);
    expect(find.text('text', findRichText: true), findsNothing);
    expect(find.text('entry_id'), findsNothing);
    expect(find.text('internal-id'), findsNothing);
    expect(find.text('evidence'), findsNothing);
    expect(find.text('原始依据文本。'), findsNothing);
    expect(find.text('time_state'), findsNothing);
    expect(find.text('no_time_evidence'), findsNothing);
    expect(find.text('团队标签'), findsNothing);
    expect(find.text('保留'), findsNothing);
    expect(find.text('复制'), findsNothing);
    expect(find.text('有用'), findsNothing);
    expect(find.text('无用'), findsNothing);
    expect(find.byTooltip('复制总结'), findsOneWidget);
    expect(find.byTooltip('导出总结'), findsOneWidget);
  });
}
