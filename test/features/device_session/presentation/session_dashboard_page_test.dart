import 'package:evt_ble_app/features/device_session/presentation/session_dashboard_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('dashboard labels unavailable values and disables observation', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SessionDashboardPage()));

    expect(find.text('设备快照'), findsOneWidget);
    expect(find.text('不可验证'), findsWidgets);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
  });
}
