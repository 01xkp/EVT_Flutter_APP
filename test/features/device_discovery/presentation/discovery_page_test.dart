import 'package:evt_ble_app/features/device_discovery/presentation/discovery_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('connection command stays disabled until a device is selected', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: DiscoveryPage()));

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });
}
