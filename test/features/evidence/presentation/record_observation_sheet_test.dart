import 'package:evt_ble_app/features/device_session/domain/device_snapshot.dart';
import 'package:evt_ble_app/features/evidence/presentation/record_observation_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/device_fixtures.dart';
import '../../../support/fake_evidence_repository.dart';

void main() {
  testWidgets('record sheet saves an observed note with its latest snapshot', (
    tester,
  ) async {
    final repository = FakeEvidenceRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordObservationSheet(
            repository: repository,
            deviceId: '71:BF:E2:3B:84:23',
            deviceName: 'AIPIN_8423',
            latestSnapshot: snapshot(state: DeviceState.standby),
          ),
        ),
      ),
    );

    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存'))
          .onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextField), 'LED 与状态上报时间一致');
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(repository.values.single.deviceName, 'AIPIN_8423');
    expect(repository.values.single.records.first.source, isNotEmpty);
    expect(find.text('已保存'), findsOneWidget);
  });
}
