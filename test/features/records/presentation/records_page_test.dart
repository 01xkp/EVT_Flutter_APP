import 'package:aipin/features/evidence/application/evidence_history_controller.dart';
import 'package:aipin/features/evidence/domain/evidence_bundle.dart';
import 'package:aipin/features/observation/domain/observation_verdict.dart';
import 'package:aipin/features/records/presentation/records_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_evidence_repository.dart';

void main() {
  testWidgets('failed history loading is shown and can be retried', (
    tester,
  ) async {
    final repository = _FailingHistoryRepository();
    final controller = EvidenceHistoryController(repository);
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(home: RecordsPage(evidenceController: controller)),
    );

    expect(find.text('证据记录暂时不可读取。'), findsOneWidget);
    expect(find.text('暂无检查记录'), findsNothing);

    repository.shouldFail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('暂无检查记录'), findsOneWidget);
    expect(find.text('证据记录暂时不可读取。'), findsNothing);
  });

  testWidgets('shows failed and unverifiable verdicts with their reasons', (
    tester,
  ) async {
    final controller = EvidenceHistoryController(
      FakeEvidenceRepository([
        EvidenceBundle.completed(
          deviceId: 'one',
          deviceName: '设备一',
          verdict: ObservationVerdict.failed,
          reason: '未收到停止录音响应',
        ),
        EvidenceBundle.completed(
          deviceId: 'two',
          deviceName: '设备二',
          verdict: ObservationVerdict.unverifiable,
          reason: '缺少设备状态',
        ),
      ]),
    );
    addTearDown(controller.dispose);
    await controller.load();

    await tester.pumpWidget(
      MaterialApp(home: RecordsPage(evidenceController: controller)),
    );

    expect(find.text('未通过'), findsOneWidget);
    expect(find.text('证据不足'), findsOneWidget);
    expect(find.textContaining('未收到停止录音响应'), findsOneWidget);
    expect(find.textContaining('缺少设备状态'), findsOneWidget);
  });

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

    expect(find.text('检查记录'), findsWidgets);
    expect(find.text('AIPIN_8423'), findsOneWidget);
    expect(find.text('本机录音'), findsNothing);
  });
}

class _FailingHistoryRepository extends FakeEvidenceRepository {
  bool shouldFail = true;

  @override
  Future<List<EvidenceBundle>> all() async {
    if (shouldFail) {
      throw StateError('unavailable');
    }
    return super.all();
  }
}
