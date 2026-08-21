import 'package:evt_ble_app/features/local_recording/application/recording_library_controller.dart';
import 'package:evt_ble_app/features/local_recording/domain/local_recording.dart';
import 'package:evt_ble_app/features/local_recording/presentation/local_recording_library_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_audio_player.dart';
import '../../../support/fake_local_recording_repository.dart';
import '../../../support/fake_recording_file_store.dart';

void main() {
  testWidgets('library delete asks for explicit confirmation', (tester) async {
    final controller = RecordingLibraryController(
      repository: FakeLocalRecordingRepository([_savedRecording()]),
      files: FakeRecordingFileStore(),
      player: FakeAudioPlayer(),
    );
    addTearDown(controller.close);
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(home: LocalRecordingLibraryPage(controller: controller)),
    );

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('删除这条录音？'), findsOneWidget);
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
