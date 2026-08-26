import 'package:aipin/features/evidence/application/evidence_history_controller.dart';
import 'package:aipin/features/evidence/domain/evidence_bundle.dart';
import 'package:aipin/features/evidence/presentation/evidence_history_page.dart';
import 'package:aipin/features/observation/domain/observation_verdict.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_evidence_repository.dart';

void main() {
  testWidgets('history shows device identity and an explicit verdict label', (
    tester,
  ) async {
    final controller = EvidenceHistoryController(
      FakeEvidenceRepository([
        EvidenceBundle.completed(
          deviceId: '71:BF:E2:3B:84:23',
          deviceName: 'AIPIN_8423',
          verdict: ObservationVerdict.unverifiable,
          reason: '待机功耗字段未上报',
          createdAt: DateTime(2026, 8, 21),
        ),
      ]),
    );
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(home: EvidenceHistoryPage(controller: controller)),
    );

    expect(find.text('AIPIN_8423'), findsOneWidget);
    expect(find.text('不可验证'), findsOneWidget);
  });
}
