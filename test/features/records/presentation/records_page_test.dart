import 'package:evt_ble_app/features/evidence/application/evidence_history_controller.dart';
import 'package:evt_ble_app/features/local_recording/application/recording_library_controller.dart';
import 'package:evt_ble_app/features/records/presentation/records_page.dart';
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
    final localController = RecordingLibraryController(
      repository: FakeLocalRecordingRepository(),
      files: FakeRecordingFileStore(),
      player: FakeAudioPlayer(),
    );
    final activityController = EvidenceHistoryController(
      FakeEvidenceRepository(),
    );
    addTearDown(localController.close);
    addTearDown(activityController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: RecordsPage(
          recordingController: localController,
          evidenceController: activityController,
          onStartRecording: () {},
        ),
      ),
    );

    expect(find.text('本机录音'), findsOneWidget);
    await tester.tap(find.text('设备活动'));
    await tester.pumpAndSettle();
    expect(find.text('设备活动'), findsWidgets);
  });
}
