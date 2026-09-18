import 'package:aipin/features/evidence/domain/evidence_bundle.dart';
import 'package:aipin/features/evidence/presentation/record_observation_sheet.dart';
import 'package:aipin/features/observation/presentation/observation_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/device_fixtures.dart';
import '../../../support/fake_evidence_repository.dart';

void main() {
  for (final manual in [false, true]) {
    testWidgets(
      'evidence save failure is visible and retryable (manual=$manual)',
      (tester) async {
        final repository = _FailingRepository();
        await tester.pumpWidget(
          MaterialApp(
            home: manual
                ? Scaffold(
                    body: RecordObservationSheet(
                      repository: repository,
                      deviceId: 'fixture',
                      deviceName: '示例设备',
                      latestSnapshot: snapshot(),
                    ),
                  )
                : ObservationPage(
                    repository: repository,
                    deviceId: 'fixture',
                    deviceName: '示例设备',
                    latestSnapshot: snapshot(),
                  ),
          ),
        );
        if (manual) {
          await tester.enterText(find.byType(TextField), '按键反馈正常');
          await tester.pump();
        }
        final save = find.text(manual ? '保存' : '保存验证结果');
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(find.text('保存失败，请重试。'), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
        expect(find.text('已保存'), findsNothing);
        if (manual) expect(find.text('按键反馈正常'), findsOneWidget);
        repository.shouldFail = false;
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(find.text('已保存'), findsOneWidget);
        expect(repository.values, hasLength(1));
      },
    );
  }
}

class _FailingRepository extends FakeEvidenceRepository {
  bool shouldFail = true;
  @override
  Future<void> save(EvidenceBundle bundle) async {
    if (shouldFail) throw StateError('Storage unavailable');
    await super.save(bundle);
  }
}
