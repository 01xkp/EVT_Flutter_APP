import 'dart:async';

import 'package:aipin/app/evt_app.dart';
import 'package:aipin/app/providers.dart';
import 'package:aipin/features/device_logs/data/file_app_log_store.dart';
import 'package:aipin/features/local_recording/domain/local_recording.dart';
import 'package:aipin/features/device_session/domain/device_connection_history_repository.dart';
import 'package:aipin/features/device_session/domain/remembered_device.dart';
import 'package:aipin/features/local_recording/domain/audio_recorder_port.dart';
import 'package:aipin/features/research_beta/application/research_capture_library_controller.dart';
import 'package:aipin/features/research_beta/application/research_capture_processing_controller.dart';
import 'package:aipin/features/research_beta/domain/research_capture.dart';
import 'package:aipin/features/research_beta/domain/research_trial.dart';
import 'package:aipin/features/research_beta/domain/temporary_asr_gateway.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_onboarding_store.dart';
import '../support/fake_audio_player.dart';
import '../support/fake_audio_recorder.dart';
import '../support/fake_ble_transport.dart';
import '../support/fake_evidence_repository.dart';
import '../support/fake_local_recording_repository.dart';
import '../support/fake_recording_background_service.dart';
import '../support/fake_recording_file_store.dart';
import '../support/fake_research_beta.dart';

void main() {
  testWidgets('completed onboarding reveals consumer navigation', (
    tester,
  ) async {
    final observer = _ProviderCreationObserver();
    await tester.pumpWidget(
      ProviderScope(
        observers: [observer],
        overrides: [
          onboardingStoreProvider.overrideWithValue(
            FakeOnboardingStore(completed: true),
          ),
        ],
        child: const EvtApp(),
      ),
    );

    expect(find.byKey(const ValueKey('aipinBrandSplash')), findsOneWidget);
    await tester.pump();

    expect(find.text('首页'), findsWidgets);
    expect(find.text('录音'), findsWidgets);
    expect(find.text('记录'), findsOneWidget);
    expect(find.text('我的设备'), findsOneWidget);
    expect(find.text('尚未连接'), findsOneWidget);
    expect(
      observer.createdProviders,
      isNot(contains(researchCaptureProcessingControllerProvider)),
      reason: '首页启动不应初始化 AI 语音处理或研究数据库。',
    );
  });

  testWidgets('automatically connects when a remembered device is scanned', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final transport = FakeBleTransport.withGattReadyProfile();
    final appLogStore = FileAppLogStore(enabled: false);
    final candidate = FakeBleTransport.matchingCandidate;
    final history = _MemoryConnectionHistory(<RememberedDevice>[
      RememberedDevice(
        connectionId: candidate.connectionId,
        physicalMacAddress: candidate.physicalDeviceId,
        displayName: candidate.name,
        lastConnectedAt: DateTime.utc(2026, 9, 4, 10),
      ),
    ]);
    addTearDown(transport.dispose);
    addTearDown(appLogStore.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onboardingStoreProvider.overrideWithValue(
            FakeOnboardingStore(completed: true),
          ),
          bleTransportProvider.overrideWithValue(transport),
          deviceConnectionHistoryRepositoryProvider.overrideWithValue(history),
          appLogStoreProvider.overrideWithValue(appLogStore),
        ],
        child: const EvtApp(),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(transport.scanCallCount, 1);
    expect((await history.load()).single.matches(candidate), isTrue);

    transport.emitCandidate(candidate);
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 350)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(transport.discoveryRequests, <String>[candidate.connectionId]);
    expect(history.upserts, hasLength(1));
    expect(history.upserts.single.connectionId, candidate.connectionId);
  });

  testWidgets('ending local recording asks before AI processing', (
    tester,
  ) async {
    final recorder = FakeAudioRecorder()
      ..permission = RecorderPermission.granted;
    final localRepository = FakeLocalRecordingRepository();
    final localFiles = FakeRecordingFileStore();
    final researchRepository = FakeResearchCaptureRepository();
    final trialStore = FakeResearchTrialStore(
      ResearchTrial.newParticipant(
        participantId: 'participant-1',
        startedAt: DateTime(2026, 8, 25),
      ).accepted(DateTime(2026, 8, 25)),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onboardingStoreProvider.overrideWithValue(
            FakeOnboardingStore(completed: true),
          ),
          localRecordingRepositoryProvider.overrideWithValue(localRepository),
          recordingFileStoreProvider.overrideWithValue(localFiles),
          audioRecorderProvider.overrideWithValue(recorder),
          recordingBackgroundProvider.overrideWithValue(
            FakeRecordingBackgroundService(),
          ),
          audioPlayerProvider.overrideWithValue(FakeAudioPlayer()),
          researchCaptureLibraryControllerProvider.overrideWithValue(
            ResearchCaptureLibraryController(
              repository: researchRepository,
              trialStore: trialStore,
            ),
          ),
        ],
        child: const EvtApp(),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('录音').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始本机录音'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('结束录音'));
    await tester.pumpAndSettle();

    expect(find.text('使用 AI 转写和总结？'), findsOneWidget);
    expect(find.text('暂不处理'), findsOneWidget);
    expect(find.text('开始处理'), findsOneWidget);
  });

  testWidgets('shows stage-specific AI completion notices after returning', (
    tester,
  ) async {
    final repository = FakeResearchCaptureRepository();
    final processing = _researchProcessing(repository);
    final recording = _savedLocalRecording();
    addTearDown(processing.dispose);
    await tester.pumpWidget(
      _appWithResearchProcessing(
        processing: processing,
        repository: repository,
        localRecordings: <LocalRecording>[recording],
      ),
    );
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await repository.save(_transcribingCapture('capture-1', recording.id));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await processing.process('capture-1');
    await tester.pump();
    expect(find.text('客户访谈 完成'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.text('客户访谈 转写完成'), findsOneWidget);
    expect(find.text('AI 转写和总结已完成'), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 180));

    expect(find.text('客户访谈 转写完成'), findsNothing);
    expect(find.text('客户访谈 完成'), findsOneWidget);
  });

  testWidgets('does not coalesce AI completions received while inactive', (
    tester,
  ) async {
    final repository = FakeResearchCaptureRepository();
    final processing = _researchProcessing(repository);
    final recording = _savedLocalRecording();
    final secondRecording = _savedLocalRecording(
      id: 'recording-2',
      title: '项目复盘',
    );
    addTearDown(processing.dispose);
    await tester.pumpWidget(
      _appWithResearchProcessing(
        processing: processing,
        repository: repository,
        localRecordings: <LocalRecording>[recording, secondRecording],
      ),
    );
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await repository.save(_transcribingCapture('capture-1', recording.id));
    await repository.save(
      _transcribingCapture('capture-2', secondRecording.id),
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await Future.wait([
      processing.process('capture-1'),
      processing.process('capture-2'),
    ]);
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.text('客户访谈 转写完成'), findsOneWidget);
    expect(find.text('2 条 AI 处理已完成'), findsNothing);
    expect(find.text('AI 转写和总结已完成'), findsNothing);
  });

  testWidgets(
    'hides the global transcription notice while recording detail is visible',
    (tester) async {
      final repository = FakeResearchCaptureRepository();
      final gateway = _StalledUploadGateway();
      final processing = _researchProcessing(repository, gateway: gateway);
      addTearDown(processing.dispose);
      final recording = _savedLocalRecording();
      await tester.pumpWidget(
        _appWithResearchProcessing(
          processing: processing,
          repository: repository,
          localRecordings: <LocalRecording>[recording],
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(recording.title));
      await tester.pumpAndSettle();

      await repository.save(
        ResearchCapture.fromLocalRecording(
          id: 'capture-1',
          participantId: 'participant-1',
          originalLocalRecordingId: recording.id,
          relativePath: 'capture-1.m4a',
          duration: const Duration(seconds: 12),
          createdAt: DateTime(2026, 8, 25, 10),
        ),
      );
      final work = processing.process('capture-1');
      await gateway.uploadStarted;
      await tester.pump();

      final toast = find.byKey(const ValueKey('ai-processing-toast'));
      expect(toast, findsNothing);

      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      await tester.pump();
      expect(toast, findsOneWidget);
      expect(find.text('正在转写'), findsOneWidget);

      gateway.completeUpload();
      await work;
    },
  );

  testWidgets(
    'does not show a transcription completion notice after leaving its detail',
    (tester) async {
      final repository = FakeResearchCaptureRepository();
      final gateway = _StalledUploadGateway();
      final processing = _researchProcessing(repository, gateway: gateway);
      addTearDown(processing.dispose);
      final recording = _savedLocalRecording();
      await tester.pumpWidget(
        _appWithResearchProcessing(
          processing: processing,
          repository: repository,
          localRecordings: <LocalRecording>[recording],
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('记录'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(recording.title));
      await tester.pumpAndSettle();

      await repository.save(
        ResearchCapture.fromLocalRecording(
          id: 'capture-1',
          participantId: 'participant-1',
          originalLocalRecordingId: recording.id,
          relativePath: 'capture-1.m4a',
          duration: const Duration(seconds: 12),
          createdAt: DateTime(2026, 8, 25, 10),
        ),
      );
      final work = processing.process('capture-1');
      await gateway.uploadStarted;
      gateway.completeUpload();
      await work;
      await tester.pump();
      await tester.pageBack();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(find.text('客户访谈 转写完成'), findsNothing);
    },
  );
}

Widget _appWithResearchProcessing({
  required ResearchCaptureProcessingController processing,
  required FakeResearchCaptureRepository repository,
  List<LocalRecording> localRecordings = const <LocalRecording>[],
}) {
  final trialStore = FakeResearchTrialStore(
    ResearchTrial.newParticipant(
      participantId: 'participant-1',
      startedAt: DateTime(2026, 8, 25),
    ).accepted(DateTime(2026, 8, 25)),
  );
  return ProviderScope(
    overrides: [
      onboardingStoreProvider.overrideWithValue(
        FakeOnboardingStore(completed: true),
      ),
      researchCaptureRepositoryProvider.overrideWithValue(repository),
      researchTrialStoreProvider.overrideWithValue(trialStore),
      researchCaptureProcessingControllerProvider.overrideWithValue(processing),
      researchCaptureLibraryControllerProvider.overrideWithValue(
        ResearchCaptureLibraryController(
          repository: repository,
          trialStore: trialStore,
        ),
      ),
      localRecordingRepositoryProvider.overrideWithValue(
        FakeLocalRecordingRepository(localRecordings),
      ),
      evidenceRepositoryProvider.overrideWithValue(FakeEvidenceRepository()),
      recordingFileStoreProvider.overrideWithValue(FakeRecordingFileStore()),
      audioRecorderProvider.overrideWithValue(FakeAudioRecorder()),
      recordingBackgroundProvider.overrideWithValue(
        FakeRecordingBackgroundService(),
      ),
      audioPlayerProvider.overrideWithValue(FakeAudioPlayer()),
    ],
    child: const EvtApp(),
  );
}

ResearchCaptureProcessingController _researchProcessing(
  FakeResearchCaptureRepository repository, {
  TemporaryAsrGateway? gateway,
}) {
  return ResearchCaptureProcessingController(
    repository: repository,
    researchFiles: FakeResearchCaptureFileStore(),
    localFiles: FakeRecordingFileStore(),
    gateway: gateway ?? FakeTemporaryAsrGateway(),
    audioSegmenter: FakeAudioSegmenter(),
    trialStore: FakeResearchTrialStore(
      ResearchTrial.newParticipant(
        participantId: 'participant-1',
        startedAt: DateTime(2026, 8, 25),
      ).accepted(DateTime(2026, 8, 25)),
    ),
    now: () => DateTime(2026, 8, 25, 10),
    delay: (_) async {},
  );
}

class _StalledUploadGateway extends FakeTemporaryAsrGateway {
  final Completer<AsrOutcome<AsrJob>> _upload = Completer<AsrOutcome<AsrJob>>();
  final Completer<void> _uploadStarted = Completer<void>();

  Future<void> get uploadStarted => _uploadStarted.future;

  @override
  Future<AsrOutcome<AsrJob>> submitAudio(String absoluteAudioPath) {
    _uploadStarted.complete();
    return _upload.future;
  }

  void completeUpload() {
    _upload.complete(
      const AsrSuccess<AsrJob>(
        AsrJob(id: 'job-1', status: AsrJobStatus.completed),
      ),
    );
  }
}

LocalRecording _savedLocalRecording({
  String id = 'recording-1',
  String title = '客户访谈',
}) => LocalRecording.saved(
  id: id,
  title: title,
  relativePath: 'recording-1.m4a',
  createdAt: DateTime(2026, 8, 25, 10),
  completedAt: DateTime(2026, 8, 25, 10, 0, 12),
  duration: const Duration(seconds: 12),
  sizeBytes: 160000,
);

ResearchCapture _transcribingCapture(String id, String recordingId) {
  return ResearchCapture.fromLocalRecording(
    id: id,
    participantId: 'participant-1',
    originalLocalRecordingId: recordingId,
    relativePath: '$id.m4a',
    duration: const Duration(seconds: 12),
    createdAt: DateTime(2026, 8, 25, 10),
  ).toTranscribing('$id-job');
}

class _ProviderCreationObserver extends ProviderObserver {
  final createdProviders = <ProviderBase<Object?>>[];

  @override
  void didAddProvider(
    ProviderBase<Object?> provider,
    Object? value,
    ProviderContainer container,
  ) {
    createdProviders.add(provider);
  }
}

class _MemoryConnectionHistory implements DeviceConnectionHistoryRepository {
  _MemoryConnectionHistory(Iterable<RememberedDevice> initial)
    : _records = List<RememberedDevice>.of(initial);

  final List<RememberedDevice> _records;
  final List<RememberedDevice> upserts = <RememberedDevice>[];

  @override
  Future<List<RememberedDevice>> load() async =>
      List<RememberedDevice>.unmodifiable(_records);

  @override
  Future<void> removeMatching({
    required String connectionId,
    String? physicalMacAddress,
  }) async {
    _records.removeWhere((record) {
      if (physicalMacAddress != null && record.physicalMacAddress != null) {
        return physicalMacAddress == record.physicalMacAddress;
      }
      return connectionId == record.connectionId;
    });
  }

  @override
  Future<void> upsert(RememberedDevice record) async {
    await removeMatching(
      connectionId: record.connectionId,
      physicalMacAddress: record.physicalMacAddress,
    );
    _records.add(record);
    upserts.add(record);
  }
}
