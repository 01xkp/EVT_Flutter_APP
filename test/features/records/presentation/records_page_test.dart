import 'package:aipin/features/evidence/application/evidence_history_controller.dart';
import 'package:aipin/features/evidence/domain/evidence_bundle.dart';
import 'package:aipin/features/observation/domain/observation_verdict.dart';
import 'package:aipin/features/records/presentation/records_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_evidence_repository.dart';

void main() {
  testWidgets('shows device activity without a local recording tab', (
    tester,
  ) async {
    final controller = EvidenceHistoryController(
      FakeEvidenceRepository([
        EvidenceBundle.completed(
          deviceId: '71:BF:E2:3B:84:23',
          deviceName: 'AIPIN_8423',
          verdict: ObservationVerdict.passed,
          reason: '设备状态满足检查条件',
          createdAt: DateTime(2026, 9, 8, 10),
        ),
      ]),
    );
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(home: RecordsPage(evidenceController: controller)),
    );

    expect(find.text('设备活动'), findsWidgets);
    expect(find.text('AIPIN_8423'), findsOneWidget);
    expect(find.text('本机录音'), findsNothing);
  });
}
