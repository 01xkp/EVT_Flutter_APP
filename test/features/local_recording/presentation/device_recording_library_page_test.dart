import 'package:aipin/features/local_recording/application/recording_library_controller.dart';
import 'package:aipin/features/local_recording/domain/local_recording.dart';
import 'package:aipin/features/local_recording/presentation/device_recording_library_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_audio_player.dart';
import '../../../support/fake_local_recording_repository.dart';
import '../../../support/fake_recording_file_store.dart';

void main() {
  testWidgets('shows read failure and reloads saved recordings on retry', (
    tester,
  ) async {
    final repository = FakeLocalRecordingRepository([_savedRecording()])
      ..failReads = true;
    final controller = RecordingLibraryController(
      repository: repository,
      files: FakeRecordingFileStore(),
      player: FakeAudioPlayer(),
    );
    addTearDown(controller.close);
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(home: DeviceRecordingLibraryPage(controller: controller)),
    );

    expect(find.text('已保存录音暂时不可读取。'), findsOneWidget);
    expect(find.text('暂无已保存录音'), findsNothing);
    expect(find.text('重试'), findsOneWidget);

    repository.failReads = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('设备录音'), findsOneWidget);
    expect(find.text('已保存录音暂时不可读取。'), findsNothing);
    expect(find.text('重试'), findsNothing);
  });

  testWidgets(
    'saved device recording library has no microphone capture action',
    (tester) async {
      final controller = RecordingLibraryController(
        repository: FakeLocalRecordingRepository([_savedRecording()]),
        files: FakeRecordingFileStore(),
        player: FakeAudioPlayer(),
      );
      addTearDown(controller.close);
      await controller.load();

      await tester.pumpWidget(
        MaterialApp(home: DeviceRecordingLibraryPage(controller: controller)),
      );

      expect(find.text('已保存录音'), findsOneWidget);
      expect(find.text('设备录音'), findsOneWidget);
      expect(find.byTooltip('开始本机录音'), findsNothing);
    },
  );

  testWidgets('delete asks for explicit confirmation', (tester) async {
    final controller = RecordingLibraryController(
      repository: FakeLocalRecordingRepository([_savedRecording()]),
      files: FakeRecordingFileStore(),
      player: FakeAudioPlayer(),
    );
    addTearDown(controller.close);
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(home: DeviceRecordingLibraryPage(controller: controller)),
    );

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('删除这条已保存录音？'), findsOneWidget);
  });
}

LocalRecording _savedRecording() {
  return LocalRecording.saved(
    id: 'recording-1',
    title: '设备录音',
    relativePath: 'recording-1.m4a',
    createdAt: DateTime(2026, 8, 21),
    completedAt: DateTime(2026, 8, 21, 0, 0, 10),
    duration: const Duration(seconds: 10),
    sizeBytes: 120000,
  );
}
