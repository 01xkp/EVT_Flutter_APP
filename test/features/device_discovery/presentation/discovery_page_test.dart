import 'dart:async';

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

  testWidgets('coordinates the outer reconnect cycle before starting a scan', (
    tester,
  ) async {
    final transport = FakeBleTransport();
    final controller = DiscoveryController(
      transport,
      const AdvertisementFilter(),
    );
    final startCoordinator = Completer<void>();
    var startCallbackCalls = 0;
    addTearDown(() async {
      controller.dispose();
      await transport.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryPage(
          controller: controller,
          onStartScan: () {
            startCallbackCalls += 1;
            return startCoordinator.future;
          },
        ),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, '查找附近设备'));
    await tester.pump();

    expect(startCallbackCalls, 1);
    expect(transport.scanCallCount, 0);

    startCoordinator.complete();
    await tester.pump();

    expect(transport.scanCallCount, 1);
    expect(controller.state.isScanning, isTrue);
  });

  testWidgets('coordinates reconnect cancellation before stopping a scan', (
    tester,
  ) async {
    final transport = FakeBleTransport();
    final controller = DiscoveryController(
      transport,
      const AdvertisementFilter(),
    );
    var stopCallbackCalls = 0;
    var wasScanningWhenCancelled = false;
    addTearDown(() async {
      controller.dispose();
      await transport.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryPage(
          controller: controller,
          onStopScan: () async {
            stopCallbackCalls += 1;
            wasScanningWhenCancelled = controller.state.isScanning;
          },
        ),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, '查找附近设备'));
    await tester.pump();
    expect(controller.state.isScanning, isTrue);

    await tester.tap(find.text('停止查找'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(stopCallbackCalls, 1);
    expect(wasScanningWhenCancelled, isTrue);
    expect(controller.state.isScanning, isFalse);
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

  testWidgets(
    'keeps the discovery page open and shows a retryable error when connection fails',
    (tester) async {
      final transport = FakeBleTransport();
      final controller = DiscoveryController(
        transport,
        const AdvertisementFilter(),
      );
      var attempts = 0;
      addTearDown(() async {
        controller.dispose();
        await transport.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryPage(
            controller: controller,
            onConnect: (_) async {
              attempts += 1;
              return false;
            },
          ),
        ),
      );
      await tester.tap(find.widgetWithText(FilledButton, '查找附近设备'));
      transport.emitCandidate(FakeBleTransport.matchingCandidate);
      await tester.pump();
      await tester.tap(find.text(FakeBleTransport.matchingCandidate.name));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, '连接设备'));
      await tester.pump();

      expect(attempts, 1);
      expect(find.byType(DiscoveryPage), findsOneWidget);
      expect(find.text('连接失败，请确认设备状态后重试'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '连接设备'), findsOneWidget);
    },
  );

  testWidgets('does not start a duplicate connection while one is pending', (
    tester,
  ) async {
    final transport = FakeBleTransport();
    final controller = DiscoveryController(
      transport,
      const AdvertisementFilter(),
    );
    final connection = Completer<bool>();
    var attempts = 0;
    addTearDown(() async {
      controller.dispose();
      await transport.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: DiscoveryPage(
          controller: controller,
          onConnect: (_) {
            attempts += 1;
            return connection.future;
          },
        ),
      ),
    );
    await tester.tap(find.widgetWithText(FilledButton, '查找附近设备'));
    transport.emitCandidate(FakeBleTransport.matchingCandidate);
    await tester.pump();
    await tester.tap(find.text(FakeBleTransport.matchingCandidate.name));
    await tester.pump();

    final connectButton = find.widgetWithText(FilledButton, '连接设备');
    await tester.tap(connectButton);
    await tester.tap(connectButton);
    await tester.pump();

    expect(attempts, 1);
    expect(find.widgetWithText(FilledButton, '正在连接'), findsOneWidget);
    connection.complete(false);
    await tester.pump();
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
    'iOS guidance opens App Settings and retries after the app resumes',
    (tester) async {
      final transport = FakeBleTransport();
      final controller = DiscoveryController(
        transport,
        const AdvertisementFilter(),
      );
      final bluetooth = _FakeBluetoothEnableGateway(canRequestEnable: false);
      var openedSystemSettings = 0;
      addTearDown(() async {
        controller.dispose();
        await transport.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryPage(
            controller: controller,
            bluetoothEnableGateway: bluetooth,
            onOpenSystemSettings: () async {
              openedSystemSettings += 1;
              return true;
            },
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
      expect(
        find.text('iPhone 不允许 App 直接开启蓝牙。请在控制中心或系统设置中打开蓝牙后返回。'),
        findsOneWidget,
      );
      expect(find.text('打开设置'), findsOneWidget);
      await tester.tap(find.text('打开设置'));
      await tester.pumpAndSettle();

      expect(bluetooth.requestCount, 0);
      expect(openedSystemSettings, 1);
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
