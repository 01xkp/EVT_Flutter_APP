import 'package:evt_ble_app/core/protocol/device_event.dart';
import 'package:evt_ble_app/features/device_session/domain/device_snapshot.dart';
import 'package:evt_ble_app/features/observation/domain/observation_scenario.dart';
import 'package:evt_ble_app/features/observation/presentation/observation_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/device_fixtures.dart';
import '../../../support/fake_evidence_repository.dart';

void main() {
  testWidgets('uses the requested initial scenario for hardware recording', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ObservationPage(
          repository: FakeEvidenceRepository(),
          deviceId: '71:BF:E2:3B:84:23',
          deviceName: 'AIPIN_8423',
          latestSnapshot: snapshot(state: DeviceState.standby),
          initialScenario: ObservationScenario.vadRecording,
        ),
      ),
    );

    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'VAD 录音'))
          .selected,
      isTrue,
    );
  });

  testWidgets(
    'VAD scenario evaluates protocol evidence and saves its verdict',
    (tester) async {
      final repository = FakeEvidenceRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: ObservationPage(
            repository: repository,
            deviceId: '71:BF:E2:3B:84:23',
            deviceName: 'AIPIN_8423',
            latestSnapshot: snapshot(state: DeviceState.standby),
            events: [
              event(DeviceEventKind.recordingStarted),
              event(DeviceEventKind.silenceEnded),
            ],
          ),
        ),
      );

      await tester.tap(find.text('VAD 录音'));
      await tester.pump();
      expect(find.text('通过'), findsOneWidget);

      await tester.tap(find.text('保存验证结果'));
      await tester.pump();
      expect(find.text('已保存'), findsOneWidget);
      expect(repository.values.single.reason, '已获得所需设备证据。');
    },
  );
}
