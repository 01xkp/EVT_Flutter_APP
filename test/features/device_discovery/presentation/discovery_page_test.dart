import 'package:evt_ble_app/features/device_discovery/application/discovery_controller.dart';
import 'package:evt_ble_app/features/device_discovery/domain/advertisement_filter.dart';
import 'package:evt_ble_app/features/device_discovery/presentation/discovery_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_ble_transport.dart';

void main() {
  testWidgets('connection command stays disabled until a device is selected', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: DiscoveryPage()));

    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '连接设备'))
          .onPressed,
      isNull,
    );
  });

  testWidgets('discovery exposes recovery after scan failure', (tester) async {
    final transport = FakeBleTransport();
    final controller = DiscoveryController(
      transport,
      const AdvertisementFilter(),
    );
    addTearDown(() async {
      controller.dispose();
      await transport.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(home: DiscoveryPage(controller: controller)),
    );
    await tester.tap(find.widgetWithText(FilledButton, '查找附近设备'));
    transport.emitScanError(StateError('bluetooth unavailable'));
    await tester.pump();

    expect(find.text('重新查找'), findsOneWidget);
    expect(find.text('查看连接帮助'), findsOneWidget);
  });
}
