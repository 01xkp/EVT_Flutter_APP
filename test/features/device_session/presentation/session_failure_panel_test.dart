import 'package:aipin/core/diagnostics/evt_failure.dart';
import 'package:aipin/features/device_session/presentation/session_failure_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/device_fixtures.dart';

void main() {
  testWidgets(
    'environment failure shows remediation, last snapshot, and retry',
    (tester) async {
      var retryCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SessionFailurePanel(
              failure: EvtFailure.environment(message: '蓝牙扫描不可用'),
              lastSnapshot: snapshot(observedAt: DateTime(2026, 8, 21, 10, 32)),
              onRetry: () => retryCount += 1,
            ),
          ),
        ),
      );

      expect(find.text('蓝牙或权限不可用'), findsOneWidget);
      expect(find.textContaining('最后有效状态'), findsOneWidget);
      await tester.tap(find.text('重试'));
      expect(retryCount, 1);
    },
  );

  testWidgets('protocol failure never uses a positive state label', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SessionFailurePanel(
            failure: EvtFailure.protocol(message: 'CRC 校验失败'),
          ),
        ),
      ),
    );

    expect(find.text('当前数据不可验证'), findsOneWidget);
    expect(find.text('状态可观察'), findsNothing);
  });
}
