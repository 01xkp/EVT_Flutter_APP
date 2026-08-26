import 'package:aipin/core/ble/ble_transport.dart';
import 'package:aipin/core/ble/bluetooth_enable_gateway.dart';
import 'package:aipin/core/diagnostics/evt_failure.dart';
import 'package:aipin/features/device_discovery/application/discovery_controller.dart';
import 'package:aipin/features/device_discovery/domain/advertisement_filter.dart';
import 'package:aipin/features/device_discovery/presentation/discovery_page.dart';
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

  testWidgets(
    'discovery exposes retry without connection help after scan failure',
    (tester) async {
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
      expect(find.text('查看连接帮助'), findsNothing);
    },
  );

  testWidgets('scanning shows a centered radar loading indicator', (
    tester,
  ) async {
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
    await tester.pump();

    expect(
      find.byKey(const ValueKey('discoveryScanningLoader')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.radar_outlined), findsOneWidget);
  });

  testWidgets('a discovered device is rendered without a list transition', (
    tester,
  ) async {
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
    transport.emitCandidate(FakeBleTransport.matchingCandidate);
    await tester.pump();

    expect(find.text('AIPIN_8423'), findsOneWidget);
    expect(find.byType(AnimatedSwitcher), findsNothing);
  });

  testWidgets('bluetooth-off scan failure asks the user to enable bluetooth', (
    tester,
  ) async {
    final transport = FakeBleTransport();
    final controller = DiscoveryController(
      transport,
      const AdvertisementFilter(),
    );
    final bluetooth = _FakeBluetoothEnableGateway();
    addTearDown(() async {
      controller.dispose();
      await transport.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryPage(
          controller: controller,
          bluetoothEnableGateway: bluetooth,
        ),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, '查找附近设备'));
    transport.emitScanError(
      BleTransportException(
        EvtFailure.environment(message: '蓝牙未开启。'),
        issue: BleTransportIssue.bluetoothOff,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('蓝牙未开启？'), findsOneWidget);
  });

  testWidgets(
    'android confirmation requests bluetooth enable and retries scan',
    (tester) async {
      final transport = FakeBleTransport();
      final controller = DiscoveryController(
        transport,
        const AdvertisementFilter(),
      );
      final bluetooth = _FakeBluetoothEnableGateway();
      addTearDown(() async {
        controller.dispose();
        await transport.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryPage(
            controller: controller,
            bluetoothEnableGateway: bluetooth,
          ),
        ),
      );
      await tester.tap(find.widgetWithText(FilledButton, '查找附近设备'));
      transport.emitScanError(
        BleTransportException(
          EvtFailure.environment(message: '蓝牙未开启。'),
          issue: BleTransportIssue.bluetoothOff,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('开启蓝牙'), findsOneWidget);
      await tester.tap(find.text('开启蓝牙'));
      await tester.pump();

      expect(bluetooth.requestCount, 1);
    },
  );

  testWidgets(
    'iOS guidance retries discovery after returning from app settings',
    (tester) async {
      final transport = FakeBleTransport();
      final controller = DiscoveryController(
        transport,
        const AdvertisementFilter(),
      );
      final bluetooth = _FakeBluetoothEnableGateway(canRequestEnable: false);
      var settingsOpenCount = 0;
      addTearDown(() async {
        controller.dispose();
        await transport.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryPage(
            controller: controller,
            bluetoothEnableGateway: bluetooth,
            onOpenBluetoothSettings: () async => settingsOpenCount += 1,
          ),
        ),
      );
      await tester.tap(find.widgetWithText(FilledButton, '查找附近设备'));
      transport.emitScanError(
        BleTransportException(
          EvtFailure.environment(message: '蓝牙未开启。'),
          issue: BleTransportIssue.bluetoothOff,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('请开启蓝牙'), findsOneWidget);
      expect(find.text('打开应用设置'), findsOneWidget);
      await tester.tap(find.text('打开应用设置'));
      await tester.pumpAndSettle();

      expect(settingsOpenCount, 1);
      expect(bluetooth.requestCount, 0);
      expect(transport.scanCallCount, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(transport.scanCallCount, 2);
    },
  );
}

class _FakeBluetoothEnableGateway implements BluetoothEnableGateway {
  _FakeBluetoothEnableGateway({this.canRequestEnable = true});

  @override
  final bool canRequestEnable;
  var requestCount = 0;

  @override
  Future<BluetoothEnableResult> requestEnable() async {
    requestCount += 1;
    return BluetoothEnableResult.enabled;
  }
}
