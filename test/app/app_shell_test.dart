import 'package:aipin/app/evt_app.dart';
import 'package:aipin/app/providers.dart';
import 'package:aipin/core/design_system/widgets/app_button.dart';
import 'package:aipin/core/protocol/evt_protocol_codec.dart';
import 'package:aipin/features/device_discovery/presentation/discovery_page.dart';
import 'package:aipin/features/device_logs/data/file_app_log_store.dart';
import 'package:aipin/features/device_session/domain/device_connection_history_repository.dart';
import 'package:aipin/features/device_session/domain/remembered_device.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_ble_transport.dart';
import '../support/fake_onboarding_store.dart';

void main() {
  testWidgets(
    'manual disconnect suppresses the old authentication failure toast',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final transport = FakeBleTransport.withGattReadyProfile();
      final appLogStore = _FlushTrackingAppLogStore();
      addTearDown(transport.dispose);
      addTearDown(appLogStore.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            onboardingStoreProvider.overrideWithValue(
              FakeOnboardingStore(completed: true),
            ),
            bleTransportProvider.overrideWithValue(transport),
            deviceConnectionHistoryRepositoryProvider.overrideWithValue(
              _MemoryConnectionHistory(const <RememberedDevice>[]),
            ),
            appLogStoreProvider.overrideWithValue(appLogStore),
          ],
          child: const EvtApp(),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('连接设备').first);
      await tester.pump();
      await tester.pump();
      transport.emitCandidate(FakeBleTransport.matchingCandidate);
      await tester.pump();
      await tester.tap(find.text(FakeBleTransport.matchingCandidate.name));
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(DiscoveryPage),
          matching: find.widgetWithText(AppButton, '连接设备'),
        ),
      );
      await tester.pump();
      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (transport.discoveryRequests.isEmpty &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.widgetWithText(AppButton, '认证设备'), findsOneWidget);

      await tester.tap(find.widgetWithText(AppButton, '认证设备'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField), '313233343536');
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, '开始认证'));
      await tester.pump();
      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        // V1.6 performs the admission read first (FA11/0x01), so waiting for
        // a non-empty list can return before the user authentication write.
        while (transport.writes.length < 2 &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump(const Duration(milliseconds: 300));
      expect(transport.writes, hasLength(2));

      final disconnect = find.widgetWithText(AppButton, '断开设备');
      await tester.scrollUntilVisible(
        disconnect,
        500,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(disconnect);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(AppButton, '断开设备').last);
      await tester.pump();
      for (
        var attempt = 0;
        attempt < 30 && transport.disconnectedDeviceIds.isEmpty;
        attempt++
      ) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(transport.disconnectedDeviceIds, hasLength(1));
      expect(find.text('设备认证失败，请重新连接后重试。'), findsNothing);
      expect(find.textContaining('命令客户端已关闭'), findsNothing);
      expect(transport.writes, hasLength(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('completed onboarding exposes only EVT device navigation', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onboardingStoreProvider.overrideWithValue(
            FakeOnboardingStore(completed: true),
          ),
        ],
        child: const EvtApp(),
      ),
    );

    expect(find.byKey(const ValueKey('aipinBrandSplash')), findsOneWidget);
    await tester.pump();

    expect(find.text('首页'), findsWidgets);
    expect(find.text('检查记录'), findsOneWidget);
    expect(find.text('我的设备'), findsOneWidget);
    expect(find.text('本机录音'), findsNothing);
    expect(find.text('AI 语音'), findsNothing);
    expect(find.text('先用本机录音'), findsNothing);
  });

  testWidgets(
    'automatically reconnects a remembered named device and waits for V1 authentication',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final transport = FakeBleTransport.withGattReadyProfile();
      final appLogStore = FileAppLogStore(enabled: false);
      final candidate = FakeBleTransport.matchingCandidate;
      final history = _MemoryConnectionHistory(<RememberedDevice>[
        RememberedDevice(
          connectionId: candidate.connectionId,
          physicalMacAddress: candidate.physicalDeviceId,
          displayName: candidate.name,
          lastConnectedAt: DateTime.utc(2026, 9, 4, 10),
        ),
      ]);
      addTearDown(transport.dispose);
      addTearDown(appLogStore.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            onboardingStoreProvider.overrideWithValue(
              FakeOnboardingStore(completed: true),
            ),
            bleTransportProvider.overrideWithValue(transport),
            deviceConnectionHistoryRepositoryProvider.overrideWithValue(
              history,
            ),
            appLogStoreProvider.overrideWithValue(appLogStore),
          ],
          child: const EvtApp(),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(transport.scanCallCount, 1);
      expect((await history.load()).single.matches(candidate), isTrue);

      transport.emitCandidate(candidate);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 350)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(transport.discoveryRequests, <String>[candidate.connectionId]);
      expect(history.upserts, isEmpty);
      expect(
        (await history.load()).single.connectionId,
        candidate.connectionId,
      );
    },
  );

  testWidgets(
    'automatically reconnects a remembered device while EVT advertisement filtering is relaxed',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final transport = FakeBleTransport.withGattReadyProfile();
      final appLogStore = FileAppLogStore(enabled: false);
      final candidate = FakeBleTransport.matchingCandidate.copyWith(
        serviceUuids: const <String>[],
      );
      final history = _MemoryConnectionHistory(<RememberedDevice>[
        RememberedDevice(
          connectionId: candidate.connectionId,
          physicalMacAddress: candidate.physicalDeviceId,
          displayName: candidate.name,
          lastConnectedAt: DateTime.utc(2026, 9, 4, 10),
        ),
      ]);
      addTearDown(transport.dispose);
      addTearDown(appLogStore.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            onboardingStoreProvider.overrideWithValue(
              FakeOnboardingStore(completed: true),
            ),
            bleTransportProvider.overrideWithValue(transport),
            deviceConnectionHistoryRepositoryProvider.overrideWithValue(
              history,
            ),
            appLogStoreProvider.overrideWithValue(appLogStore),
          ],
          child: const EvtApp(),
        ),
      );
      await tester.pump();
      await tester.pump();

      transport.emitCandidate(candidate);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 350)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(transport.discoveryRequests, <String>[candidate.connectionId]);
    },
  );

  testWidgets(
    'lists a named non-EVT advertisement for a manual connection attempt',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final transport = FakeBleTransport.withGattReadyProfile();
      final appLogStore = FileAppLogStore(enabled: false);
      addTearDown(transport.dispose);
      addTearDown(appLogStore.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            onboardingStoreProvider.overrideWithValue(
              FakeOnboardingStore(completed: true),
            ),
            bleTransportProvider.overrideWithValue(transport),
            appLogStoreProvider.overrideWithValue(appLogStore),
          ],
          child: const EvtApp(),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('连接设备'));
      await tester.pump(const Duration(milliseconds: 350));
      final invalidCandidate = FakeBleTransport.matchingCandidate.copyWith(
        name: 'OTHER_8423',
      );
      transport.emitCandidate(invalidCandidate);
      await tester.pump();

      expect(find.text(invalidCandidate.name), findsOneWidget);
      await tester.tap(find.text(invalidCandidate.name));
      await tester.pump();
      final connectButton = find.descendant(
        of: find.byType(DiscoveryPage),
        matching: find.widgetWithText(AppButton, '连接设备'),
      );
      expect(tester.widget<AppButton>(connectButton).onPressed, isNotNull);
      await tester.tap(connectButton);
      await tester.pump();
      await tester.runAsync(() async {
        final timeoutAt = DateTime.now().add(const Duration(seconds: 3));
        while (transport.discoveryRequests.isEmpty &&
            DateTime.now().isBefore(timeoutAt)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(transport.discoveryRequests, <String>[
        invalidCandidate.connectionId,
      ]);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets(
    'stops a first-time manual scan in background and does not restart it on foreground',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final transport = FakeBleTransport.withGattReadyProfile();
      final appLogStore = FileAppLogStore(enabled: false);
      addTearDown(transport.dispose);
      addTearDown(appLogStore.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            onboardingStoreProvider.overrideWithValue(
              FakeOnboardingStore(completed: true),
            ),
            bleTransportProvider.overrideWithValue(transport),
            appLogStoreProvider.overrideWithValue(appLogStore),
          ],
          child: const EvtApp(),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('连接设备').first);
      await tester.pump();
      await tester.pump();
      expect(transport.scanCallCount, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await tester.pump();

      transport.emitCandidate(FakeBleTransport.matchingCandidate);
      await tester.pump();
      expect(find.text(FakeBleTransport.matchingCandidate.name), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();

      expect(transport.scanCallCount, 1);
      expect(find.text(FakeBleTransport.matchingCandidate.name), findsNothing);
    },
  );

  testWidgets('flushes diagnostics before the App is backgrounded', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final transport = FakeBleTransport.withGattReadyProfile();
    final appLogStore = _FlushTrackingAppLogStore();
    addTearDown(transport.dispose);
    addTearDown(appLogStore.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onboardingStoreProvider.overrideWithValue(
            FakeOnboardingStore(completed: true),
          ),
          bleTransportProvider.overrideWithValue(transport),
          appLogStoreProvider.overrideWithValue(appLogStore),
        ],
        child: const EvtApp(),
      ),
    );
    await tester.pump();
    await tester.pump();

    final flushesBeforeBackground = appLogStore.flushCount;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(appLogStore.flushCount, flushesBeforeBackground);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));

    expect(appLogStore.flushCount, greaterThan(flushesBeforeBackground));
  });

  testWidgets(
    'pauses remembered-device scan in background and restores it on foreground',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final transport = FakeBleTransport.withGattReadyProfile();
      final appLogStore = FileAppLogStore(enabled: false);
      final candidate = FakeBleTransport.matchingCandidate;
      final history = _MemoryConnectionHistory(<RememberedDevice>[
        RememberedDevice(
          connectionId: candidate.connectionId,
          physicalMacAddress: candidate.physicalDeviceId,
          displayName: candidate.name,
          lastConnectedAt: DateTime.utc(2026, 9, 4, 10),
        ),
      ]);
      addTearDown(transport.dispose);
      addTearDown(appLogStore.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            onboardingStoreProvider.overrideWithValue(
              FakeOnboardingStore(completed: true),
            ),
            bleTransportProvider.overrideWithValue(transport),
            deviceConnectionHistoryRepositoryProvider.overrideWithValue(
              history,
            ),
            appLogStoreProvider.overrideWithValue(appLogStore),
          ],
          child: const EvtApp(),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(transport.scanCallCount, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await tester.pump();
      transport.emitCandidate(candidate);
      await tester.pump();
      expect(transport.discoveryRequests, isEmpty);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await _pumpUntil(tester, () => transport.scanCallCount == 2);

      expect(transport.scanCallCount, 2);
    },
  );

  testWidgets('opens device details after a manual EVT connection', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final transport = FakeBleTransport.withGattReadyProfile();
    final appLogStore = FileAppLogStore(enabled: false);
    final candidate = FakeBleTransport.matchingCandidate;
    final history = _MemoryConnectionHistory(const <RememberedDevice>[]);
    addTearDown(transport.dispose);
    addTearDown(appLogStore.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          onboardingStoreProvider.overrideWithValue(
            FakeOnboardingStore(completed: true),
          ),
          bleTransportProvider.overrideWithValue(transport),
          deviceConnectionHistoryRepositoryProvider.overrideWithValue(history),
          appLogStoreProvider.overrideWithValue(appLogStore),
        ],
        child: const EvtApp(),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('连接设备').first);
    await tester.pump();
    await tester.pump();
    expect(transport.scanCallCount, 1);
    transport.emitCandidate(candidate);
    await tester.pump();
    await tester.tap(find.text(candidate.name));
    await tester.pump();
    final connectButton = find.descendant(
      of: find.byType(DiscoveryPage),
      matching: find.widgetWithText(AppButton, '连接设备'),
    );
    expect(tester.widget<AppButton>(connectButton).onPressed, isNotNull);
    await tester.tap(connectButton);
    await tester.pump();
    await tester.pump();
    await tester.runAsync(() async {
      final timeoutAt = DateTime.now().add(const Duration(seconds: 3));
      while (transport.discoveryRequests.isEmpty &&
          DateTime.now().isBefore(timeoutAt)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(transport.discoveryRequests, <String>[candidate.connectionId]);
    expect(find.byType(DiscoveryPage), findsNothing);
    expect(find.text('设备详情'), findsOneWidget);
  });

  testWidgets(
    'manual EVT authentication opens the code sheet and writes V1.6 0x09 to FA19',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final transport = FakeBleTransport.withGattReadyProfile();
      final appLogStore = _FlushTrackingAppLogStore();
      final candidate = FakeBleTransport.matchingCandidate;
      final history = _MemoryConnectionHistory(const <RememberedDevice>[]);
      addTearDown(transport.dispose);
      addTearDown(appLogStore.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            onboardingStoreProvider.overrideWithValue(
              FakeOnboardingStore(completed: true),
            ),
            bleTransportProvider.overrideWithValue(transport),
            deviceConnectionHistoryRepositoryProvider.overrideWithValue(
              history,
            ),
            appLogStoreProvider.overrideWithValue(appLogStore),
          ],
          child: const EvtApp(),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('连接设备').first);
      await tester.pump();
      await tester.pump();
      transport.emitCandidate(candidate);
      await tester.pump();
      await tester.tap(find.text(candidate.name));
      await tester.pump();
      final connectButton = find.descendant(
        of: find.byType(DiscoveryPage),
        matching: find.widgetWithText(AppButton, '连接设备'),
      );
      await tester.tap(connectButton);
      await tester.pump();
      await tester.runAsync(() async {
        final timeoutAt = DateTime.now().add(const Duration(seconds: 3));
        while (transport.discoveryRequests.isEmpty &&
            DateTime.now().isBefore(timeoutAt)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.text('设备详情'), findsOneWidget);
      expect(find.text('设备认证（DVT）'), findsOneWidget);
      expect(find.widgetWithText(AppButton, '认证设备'), findsOneWidget);
      expect(find.widgetWithText(AppButton, '首次绑定设备'), findsOneWidget);

      await tester.tap(find.widgetWithText(AppButton, '认证设备'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('安全码（6 位文本 / 12 位十六进制）'), findsOneWidget);

      final mirrorsBeforeCancel = appLogStore.publicMirrorSyncCount;
      await tester.tap(find.widgetWithText(AppButton, '取消'));
      await tester.pump();
      await tester.runAsync(() async {
        final timeoutAt = DateTime.now().add(const Duration(seconds: 3));
        while (appLogStore.publicMirrorSyncCount == mirrorsBeforeCancel &&
            DateTime.now().isBefore(timeoutAt)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump();

      expect(
        transport.writes.map(
          (bytes) => EvtProtocolCodec().decode(bytes).value?.command,
        ),
        contains(0x01),
      );
      expect(appLogStore.publicMirrorSyncCount, mirrorsBeforeCancel + 1);

      await tester.tap(find.widgetWithText(AppButton, '认证设备'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(find.byType(TextField), '313233343536');
      await tester.pump();
      await tester.tap(find.widgetWithText(AppButton, '开始认证'));
      await tester.pump();
      await tester.runAsync(() async {
        final timeoutAt = DateTime.now().add(const Duration(seconds: 3));
        while (transport.writes.isEmpty && DateTime.now().isBefore(timeoutAt)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump();

      expect(transport.writes, hasLength(2));
      expect(transport.writtenCharacteristics, hasLength(2));
      expect(
        transport.writtenCharacteristics.last.characteristicUuid,
        '0000FA19-1212-EFDE-1523-785FEABCD123',
      );
      expect(transport.writes.last, <int>[
        0xED,
        0x0A,
        0x00,
        0x09,
        0x00,
        0x31,
        0x32,
        0x33,
        0x34,
        0x35,
        0x36,
        0xD3,
        0x48,
      ]);

      // Resolve the pending authentication request so the test proves the
      // outbound path without leaving its response-timeout timer active.
      final flushesBeforeTerminalResponse = appLogStore.flushCount;
      transport.emitSubscriptionBytesForCharacteristic(
        '0000FA19-1212-EFDE-1523-785FEABCD123',
        EvtProtocolCodec().encodeRequest(0x89, const [0]),
      );
      await tester.pump();
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));

      expect(
        appLogStore.flushCount,
        greaterThan(flushesBeforeTerminalResponse),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maximumPumps = 12,
}) async {
  for (var attempt = 0; attempt < maximumPumps && !condition(); attempt += 1) {
    await tester.pump();
  }
}

class _MemoryConnectionHistory implements DeviceConnectionHistoryRepository {
  _MemoryConnectionHistory(Iterable<RememberedDevice> initial)
    : _records = List<RememberedDevice>.of(initial);

  final List<RememberedDevice> _records;
  final List<RememberedDevice> upserts = <RememberedDevice>[];

  @override
  Future<List<RememberedDevice>> load() async =>
      List<RememberedDevice>.unmodifiable(_records);

  @override
  Future<void> removeMatching({
    required String connectionId,
    String? physicalMacAddress,
  }) async {
    _records.removeWhere((record) {
      if (physicalMacAddress != null && record.physicalMacAddress != null) {
        return physicalMacAddress == record.physicalMacAddress;
      }
      return connectionId == record.connectionId;
    });
  }

  @override
  Future<void> upsert(RememberedDevice record) async {
    await removeMatching(
      connectionId: record.connectionId,
      physicalMacAddress: record.physicalMacAddress,
    );
    _records.add(record);
    upserts.add(record);
  }
}

class _FlushTrackingAppLogStore extends FileAppLogStore {
  _FlushTrackingAppLogStore() : super(enabled: false);

  var flushCount = 0;
  var publicMirrorSyncCount = 0;

  @override
  Future<void> flush() async {
    flushCount += 1;
    await super.flush();
  }

  @override
  Future<void> syncPublicMirror() async {
    publicMirrorSyncCount += 1;
    await super.syncPublicMirror();
  }
}
