import 'dart:async';

import 'package:aipin/core/documents/text_document_exporter.dart';
import 'package:aipin/features/local_recording/domain/audio_player_port.dart';
import 'package:aipin/features/local_recording/domain/local_recording.dart';
import 'package:aipin/features/local_recording/presentation/audio_playback_panel.dart';
import 'package:aipin/features/local_recording/presentation/local_recording_detail_page.dart';
import 'package:aipin/features/research_beta/application/research_capture_library_controller.dart';
import 'package:aipin/features/research_beta/application/research_capture_processing_controller.dart';
import 'package:aipin/features/research_beta/domain/research_capture.dart';
import 'package:aipin/features/research_beta/domain/temporary_asr_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_audio_player.dart';
import '../../../support/fake_recording_file_store.dart';
import '../../../support/fake_research_beta.dart';

void main() {
  testWidgets(
    'recording detail plays local audio and seeks from playback tab',
    (tester) async {
      final player = FakeAudioPlayer();
      await tester.pumpWidget(
        MaterialApp(home: _detailPage(audioPlayerFactory: () => player)),
      );

      expect(find.text('播放'), findsOneWidget);
      expect(find.text('转写'), findsOneWidget);
      expect(find.text('总结'), findsOneWidget);
      final waveform = find.byKey(
        const ValueKey('local-recording-playback-waveform'),
      );
      final progress = find.byKey(
        const ValueKey('local-recording-playback-progress'),
      );
      expect(waveform, findsOneWidget);
      expect(find.descendant(of: waveform, matching: progress), findsNothing);

      await tester.tap(find.byTooltip('播放录音'));
      await tester.pump();
      player.emitPosition(const Duration(seconds: 3));
      await tester.pump();
      await tester.drag(progress, const Offset(120, 0));
      await tester.pump();

      expect(player.playedPaths, <String>['/recordings/recording-1.m4a']);
      expect(player.seekedPositions, isNotEmpty);
      expect(
        player.seekedPositions.last,
        greaterThan(const Duration(seconds: 3)),
      );
    },
  );

  testWidgets(
    'playback advances its visible progress when native position updates lag',
    (tester) async {
      final player = FakeAudioPlayer();
      await tester.pumpWidget(
        MaterialApp(home: _detailPage(audioPlayerFactory: () => player)),
      );

      final progress = find.byKey(
        const ValueKey('local-recording-playback-progress'),
      );
      await tester.tap(find.byTooltip('播放录音'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      expect(tester.widget<Slider>(progress).value, greaterThan(0));
    },
  );

  testWidgets('playback places progress below its raised waveform', (
    tester,
  ) async {
    final player = FakeAudioPlayer();
    await tester.pumpWidget(
      MaterialApp(home: _detailPage(audioPlayerFactory: () => player)),
    );

    await tester.tap(find.byTooltip('播放录音'));
    await tester.pump();

    final waveform = find.byKey(
      const ValueKey('local-recording-playback-waveform'),
    );
    final progress = find.byKey(
      const ValueKey('local-recording-playback-progress'),
    );
    final pause = find.byTooltip('暂停录音');
    expect(find.byTooltip('上一条录音'), findsOneWidget);
    expect(find.byTooltip('下一条录音'), findsOneWidget);
    expect(
      tester.getTopLeft(progress).dy,
      greaterThan(tester.getBottomLeft(waveform).dy),
    );
    expect(
      tester.getTopLeft(pause).dy,
      greaterThan(tester.getBottomLeft(progress).dy),
    );
    final playbackGroupCenter =
        (tester.getCenter(waveform).dy + tester.getCenter(pause).dy) / 2;
    expect(
      playbackGroupCenter,
      closeTo(tester.getCenter(find.byType(AudioPlaybackPanel)).dy, 32),
    );
  });

  testWidgets('playback opens adjacent recordings from its skip controls', (
    tester,
  ) async {
    LocalRecording? opened;
    final first = _savedRecording(id: 'recording-1', title: '第一条录音');
    final current = _savedRecording(id: 'recording-2', title: '第二条录音');
    final last = _savedRecording(id: 'recording-3', title: '第三条录音');
    await tester.pumpWidget(
      MaterialApp(
        home: _detailPage(
          recording: current,
          recordings: [first, current, last],
          onOpenRecording: (recording) => opened = recording,
        ),
      ),
    );

    await tester.tap(find.byTooltip('上一条录音'));
    expect(opened?.id, 'recording-1');
    await tester.tap(find.byTooltip('下一条录音'));
    expect(opened?.id, 'recording-3');
  });

  testWidgets('transcript and summary request AI processing when absent', (
    tester,
  ) async {
    var requestCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: _detailPage(
          onRequestAiProcessing: (_) async {
            requestCount += 1;
            return null;
          },
        ),
      ),
    );

    await tester.tap(find.text('转写'));
    await tester.pump();
    expect(requestCount, 1);
    await tester.pumpAndSettle();
    expect(find.text('尚未进行 AI 转写'), findsOneWidget);
    await tester.tap(find.text('开始 AI 转写和总结'));
    await tester.pump();
    expect(requestCount, 2);

    await tester.tap(find.text('总结'));
    await tester.pump();
    expect(requestCount, 3);
    await tester.pumpAndSettle();
    expect(find.text('尚未进行 AI 总结'), findsOneWidget);
    await tester.tap(find.text('开始 AI 转写和总结'));
    await tester.pump();
    expect(requestCount, 4);
  });

  testWidgets('detail opens transcript editing from its edit button', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: _detailPage(capture: _completedCapture())),
    );

    await tester.tap(find.text('转写'));
    await tester.pumpAndSettle();
    expect(find.text('转写文本（TXT）'), findsNothing);
    expect(find.text('校正转写'), findsNothing);
    expect(find.text('转写'), findsAtLeastNWidgets(2));
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byTooltip('编辑转写'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '编辑后的转写');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('总结'));
    await tester.pumpAndSettle();
    expect(find.text('本次沟通重点'), findsOneWidget);
    expect(find.byTooltip('编辑总结'), findsOneWidget);
  });

  testWidgets(
    'detail exposes distinct regenerate controls for transcript and summary',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _detailPage(capture: _completedCapture())),
      );

      await tester.tap(find.text('转写'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('重新生成转写'), findsOneWidget);

      await tester.tap(find.text('总结'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('重新生成总结'), findsOneWidget);
    },
  );

  testWidgets(
    'regenerating transcript asks for confirmation before replacing content',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: _detailPage(capture: _completedCapture())),
      );

      await tester.tap(find.text('转写'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('重新生成转写'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('重新生成转写？'), findsOneWidget);
      expect(find.text('会重新上传原录音，并覆盖当前转写和 AI 总结。'), findsOneWidget);
      expect(find.text('重新生成'), findsOneWidget);
    },
  );

  testWidgets('document actions export the displayed transcript and summary', (
    tester,
  ) async {
    final exporter = _FakeTextDocumentExporter();
    await tester.pumpWidget(
      MaterialApp(
        home: _detailPage(
          capture: _completedCapture(),
          textDocumentExporter: exporter,
        ),
      ),
    );

    await tester.tap(find.text('转写'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('导出转写'));
    await tester.pumpAndSettle();

    expect(exporter.requests, hasLength(1));
    expect(exporter.requests.single.fileName, '20260825_000000_转写.txt');
    expect(exporter.requests.single.content, '机器转写内容');
    expect(exporter.requests.single.mimeType, 'text/plain');

    await tester.tap(find.text('总结'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('导出总结'));
    await tester.pumpAndSettle();

    expect(exporter.requests, hasLength(2));
    expect(exporter.requests.last.fileName, '20260825_000000_总结.md');
    expect(exporter.requests.last.content, '# 本次沟通重点\n- 跟进需求');
    expect(exporter.requests.last.mimeType, 'text/markdown');
  });

  testWidgets(
    'leaving recording detail does not cancel pending AI processing',
    (tester) async {
      final repository = FakeResearchCaptureRepository();
      final researchFiles = FakeResearchCaptureFileStore();
      final localFiles = FakeRecordingFileStore();
      final gateway = _StalledThenCompletedGateway();
      final processing = ResearchCaptureProcessingController(
        repository: repository,
        researchFiles: researchFiles,
        localFiles: localFiles,
        gateway: gateway,
        audioSegmenter: FakeAudioSegmenter(),
        trialStore: FakeResearchTrialStore(),
        delay: (_) async {},
      );
      addTearDown(processing.dispose);
      final capture = ResearchCapture.fromLocalRecording(
        id: 'capture-1',
        participantId: 'participant-1',
        originalLocalRecordingId: 'recording-1',
        relativePath: 'capture-1.m4a',
        duration: const Duration(seconds: 12),
        createdAt: DateTime(2026, 8, 25, 10),
      ).toTranscribing('job-1');
      await repository.save(capture);
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: SizedBox()),
        ),
      );
      unawaited(
        navigatorKey.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => _detailPage(
              researchRepository: repository,
              researchFiles: researchFiles,
              localFiles: localFiles,
              researchProcessing: processing,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final processingFuture = processing.process(capture.id);
      await tester.pump();

      await tester.pageBack();
      await tester.pumpAndSettle();
      gateway.complete();
      await processingFuture;

      expect(
        (await repository.findById(capture.id))!.processingState,
        ResearchProcessingState.completed,
      );
    },
  );
}

Widget _detailPage({
  AudioPlayerPort Function()? audioPlayerFactory,
  Future<ResearchCapture?> Function(LocalRecording recording)?
  onRequestAiProcessing,
  ResearchCapture? capture,
  TextDocumentExporter? textDocumentExporter,
  LocalRecording? recording,
  List<LocalRecording> recordings = const <LocalRecording>[],
  ValueChanged<LocalRecording>? onOpenRecording,
  FakeResearchCaptureRepository? researchRepository,
  FakeResearchCaptureFileStore? researchFiles,
  FakeRecordingFileStore? localFiles,
  ResearchCaptureProcessingController? researchProcessing,
}) {
  final repository = researchRepository ?? FakeResearchCaptureRepository();
  if (capture != null) {
    repository.captures[capture.id] = capture;
  }
  final files = researchFiles ?? FakeResearchCaptureFileStore();
  final fileStore = localFiles ?? FakeRecordingFileStore();
  final trialStore = FakeResearchTrialStore();
  return LocalRecordingDetailPage(
    recording: recording ?? _savedRecording(),
    recordings: recordings,
    onOpenRecording: onOpenRecording,
    localFiles: fileStore,
    audioPlayerFactory: audioPlayerFactory ?? FakeAudioPlayer.new,
    researchRepository: repository,
    researchLibrary: ResearchCaptureLibraryController(
      repository: repository,
      trialStore: trialStore,
    ),
    researchProcessing:
        researchProcessing ??
        ResearchCaptureProcessingController(
          repository: repository,
          researchFiles: files,
          localFiles: fileStore,
          gateway: FakeTemporaryAsrGateway(),
          audioSegmenter: FakeAudioSegmenter(),
          trialStore: trialStore,
          delay: (_) async {},
        ),
    textDocumentExporter:
        textDocumentExporter ?? const AppTextDocumentExporter(),
    onRequestAiProcessing: onRequestAiProcessing ?? (_) async => null,
  );
}

class _FakeTextDocumentExporter implements TextDocumentExporter {
  final requests = <_ExportRequest>[];

  @override
  Future<void> export({
    required String fileName,
    required String content,
    required String mimeType,
  }) async {
    requests.add(
      _ExportRequest(fileName: fileName, content: content, mimeType: mimeType),
    );
  }
}

class _ExportRequest {
  const _ExportRequest({
    required this.fileName,
    required this.content,
    required this.mimeType,
  });

  final String fileName;
  final String content;
  final String mimeType;
}

class _StalledThenCompletedGateway extends FakeTemporaryAsrGateway {
  final Completer<AsrOutcome<AsrJob>> _job = Completer<AsrOutcome<AsrJob>>();

  @override
  Future<AsrOutcome<AsrJob>> pollJob(String jobId) => _job.future;

  void complete() {
    _job.complete(
      const AsrSuccess<AsrJob>(
        AsrJob(id: 'job-1', status: AsrJobStatus.completed),
      ),
    );
  }
}

ResearchCapture _completedCapture() =>
    ResearchCapture.fromLocalRecording(
          id: 'capture-1',
          participantId: 'participant-1',
          originalLocalRecordingId: 'recording-1',
          relativePath: 'capture-1.m4a',
          duration: const Duration(seconds: 12),
          createdAt: DateTime(2026, 8, 25),
        )
        .completed(
          title: '客户访谈',
          summary: '# 本次沟通重点\n- 跟进需求',
          tags: const ['客户'],
          completedAt: DateTime(2026, 8, 25, 0, 0, 20),
        )
        .copyWith(rawTranscript: '机器转写内容');

LocalRecording _savedRecording({
  String id = 'recording-1',
  String title = '客户访谈',
}) {
  return LocalRecording.saved(
    id: id,
    title: title,
    relativePath: '$id.m4a',
    createdAt: DateTime(2026, 8, 25),
    completedAt: DateTime(2026, 8, 25, 0, 0, 12),
    duration: const Duration(seconds: 12),
    sizeBytes: 160000,
  );
}
