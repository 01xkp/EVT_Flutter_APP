import 'package:aipin/features/device_session/application/session_state.dart';
import 'package:aipin/features/device_session/domain/session_phase.dart';
import 'package:aipin/features/device_session/presentation/device_detail_page.dart';
import 'package:aipin/features/device_session/presentation/session_dashboard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('dashboard keeps the compatibility route consumer-facing', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SessionDashboardPage()));

    expect(find.text('设备详情'), findsOneWidget);
    expect(find.text('暂时无法获取'), findsOneWidget);
    expect(find.text('重新连接'), findsOneWidget);
  });

  testWidgets('detail asks before disconnecting', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DeviceDetailPage(
          state: SessionState(phase: SessionPhase.observable),
          onDisconnect: _noOp,
        ),
      ),
    );

    await tester.tap(find.text('断开设备'));
    await tester.pumpAndSettle();

    expect(find.text('断开设备？'), findsOneWidget);
  });
}

void _noOp() {}
