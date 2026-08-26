import 'package:aipin/features/evidence/application/evidence_history_controller.dart';
import 'package:aipin/features/local_recording/application/recording_library_controller.dart';
import 'package:aipin/features/local_recording/domain/local_recording.dart';
import 'package:aipin/features/records/presentation/records_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_audio_player.dart';
import '../../../support/fake_evidence_repository.dart';
import '../../../support/fake_local_recording_repository.dart';
import '../../../support/fake_recording_file_store.dart';

void main() {
  testWidgets('records switches between local recordings and device activity', (
    tester,
  ) async {
    final repository = FakeLocalRecordingRepository([_savedRecording()]);
    final localController = RecordingLibraryController(
      repository: repository,
      files: FakeRecordingFileStore(),
      player: FakeAudioPlayer(),
    );
    final activityController = EvidenceHistoryController(
      FakeEvidenceRepository(),
    );
    addTearDown(localController.close);
    addTearDown(activityController.dispose);
    await localController.load();
    await tester.pumpWidget(
      MaterialApp(
        home: RecordsPage(
          recordingController: localController,
          evidenceController: activityController,
        ),
      ),
    );

    expect(find.text('本机录音'), findsOneWidget);
    expect(find.text('AI 语音'), findsNothing);
    expect(find.byTooltip('开始本机录音'), findsNothing);
    expect(find.byTooltip('播放录音'), findsNothing);
    expect(
      find.text('2026-08-21 00:00 · 00:00:10 · 120 KB · 已保存'),
      findsOneWidget,
    );
    await tester.tap(find.text('设备活动'));
    await tester.pumpAndSettle();
    expect(find.text('设备活动'), findsWidgets);
  });

  testWidgets('records deletes a local recording after confirmation', (
    tester,
  ) async {
    final repository = FakeLocalRecordingRepository([_savedRecording()]);
    final localController = RecordingLibraryController(
      repository: repository,
      files: FakeRecordingFileStore(),
      player: FakeAudioPlayer(),
    );
    final activityController = EvidenceHistoryController(
      FakeEvidenceRepository(),
    );
    addTearDown(localController.close);
    addTearDown(activityController.dispose);
    await localController.load();

    await tester.pumpWidget(
      MaterialApp(
        home: RecordsPage(
          recordingController: localController,
          evidenceController: activityController,
        ),
      ),
    );

    await tester.tap(find.byTooltip('删除录音'));
    await tester.pumpAndSettle();
    expect(find.text('删除这条录音？'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(repository.values, isEmpty);
    expect(find.text('暂无本机录音'), findsOneWidget);
  });

  testWidgets('records renames a local recording and keeps direct deletion', (
    tester,
  ) async {
    final repository = FakeLocalRecordingRepository([_savedRecording()]);
    final localController = RecordingLibraryController(
      repository: repository,
      files: FakeRecordingFileStore(),
      player: FakeAudioPlayer(),
    );
    final activityController = EvidenceHistoryController(
      FakeEvidenceRepository(),
    );
    addTearDown(localController.close);
    addTearDown(activityController.dispose);
    await localController.load();
    await tester.pumpWidget(
      MaterialApp(
        home: RecordsPage(
          recordingController: localController,
          evidenceController: activityController,
        ),
      ),
    );

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '客户访谈复盘');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(repository.values.single.title, '客户访谈复盘');
    expect(find.text('客户访谈复盘'), findsOneWidget);
    expect(find.byTooltip('删除录音'), findsOneWidget);
  });

  testWidgets('records places rename before delete and uses rename wording', (
    tester,
  ) async {
    final localController = RecordingLibraryController(
      repository: FakeLocalRecordingRepository([_savedRecording()]),
      files: FakeRecordingFileStore(),
      player: FakeAudioPlayer(),
    );
    final activityController = EvidenceHistoryController(
      FakeEvidenceRepository(),
    );
    addTearDown(localController.close);
    addTearDown(activityController.dispose);
    await localController.load();
    await tester.pumpWidget(
      MaterialApp(
        home: RecordsPage(
          recordingController: localController,
          evidenceController: activityController,
        ),
      ),
    );

    expect(
      tester.getCenter(find.byTooltip('更多操作')).dx,
      lessThan(tester.getCenter(find.byTooltip('删除录音')).dx),
    );

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();

    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('修改标题'), findsNothing);
  });

  testWidgets('tapping a local recording requests its detail page', (
    tester,
  ) async {
    final repository = FakeLocalRecordingRepository([_savedRecording()]);
    final localController = RecordingLibraryController(
      repository: repository,
      files: FakeRecordingFileStore(),
      player: FakeAudioPlayer(),
    );
    final activityController = EvidenceHistoryController(
      FakeEvidenceRepository(),
    );
    LocalRecording? opened;
    addTearDown(localController.close);
    addTearDown(activityController.dispose);
    await localController.load();

    await tester.pumpWidget(
      MaterialApp(
        home: RecordsPage(
          recordingController: localController,
          evidenceController: activityController,
          onOpenRecording: (recording) => opened = recording,
        ),
      ),
    );

    await tester.tap(find.text('客户访谈'));
    await tester.pump();

    expect(opened?.id, 'recording-1');
  });
}

LocalRecording _savedRecording() {
  return LocalRecording.saved(
    id: 'recording-1',
    title: '客户访谈',
    relativePath: 'recording-1.m4a',
    createdAt: DateTime(2026, 8, 21),
    completedAt: DateTime(2026, 8, 21, 0, 0, 10),
    duration: const Duration(seconds: 10),
    sizeBytes: 120000,
  );
}
