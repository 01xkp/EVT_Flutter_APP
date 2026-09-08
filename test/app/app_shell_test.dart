import 'package:aipin/app/evt_app.dart';
import 'package:aipin/app/providers.dart';
import 'package:aipin/core/design_system/widgets/app_button.dart';
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
    expect(find.text('设备活动'), findsOneWidget);
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
