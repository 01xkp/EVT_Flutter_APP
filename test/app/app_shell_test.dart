import 'package:evt_ble_app/app/evt_app.dart';
import 'package:evt_ble_app/app/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_ble_transport.dart';

void main() {
  testWidgets('selected discovery candidate opens its session without losing shell navigation', (
    tester,
  ) async {
    final transport = FakeBleTransport.withGattReadyProfile();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [bleTransportProvider.overrideWithValue(transport)],
        child: const EvtApp(),
      ),
    );

    await tester.tap(find.byTooltip('开始扫描'));
    transport.emitCandidate(FakeBleTransport.matchingCandidate);
    await tester.pump();
    await tester.tap(find.text('AIPIN_8423'));
    await tester.pump();
    await tester.tap(find.text('连接设备'));
    await tester.runAsync(() async {
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    transport.completeRead(FakeBleTransport.validBatteryFrame);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('设备快照'), findsOneWidget);
    expect(find.byTooltip('查看证据'), findsOneWidget);
  });
}
