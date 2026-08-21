import 'package:evt_ble_app/features/local_recording/application/recording_controller.dart';
import 'package:evt_ble_app/features/local_recording/domain/audio_recorder_port.dart';
import 'package:evt_ble_app/features/local_recording/presentation/active_recording_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_audio_recorder.dart';
import '../../../support/fake_local_recording_repository.dart';
import '../../../support/fake_recording_background_service.dart';
import '../../../support/fake_recording_file_store.dart';

void main() {
  testWidgets('active recorder renders a fixed timer and pause then stop controls', (
    tester,
  ) async {
    final controller = RecordingController(
      repository: FakeLocalRecordingRepository(),
      recorder: FakeAudioRecorder()..permission = RecorderPermission.granted,
      files: FakeRecordingFileStore(),
      background: FakeRecordingBackgroundService(),
      idGenerator: () => 'recording-1',
    );
    addTearDown(controller.close);

    await tester.pumpWidget(
      MaterialApp(home: ActiveRecordingPage(controller: controller)),
    );
    await tester.pump();

    expect(find.text('00:00:00'), findsOneWidget);
    expect(find.byTooltip('暂停录音'), findsOneWidget);
    expect(find.byTooltip('结束录音'), findsOneWidget);

    await controller.stop();
    await tester.pump();
  });
}
