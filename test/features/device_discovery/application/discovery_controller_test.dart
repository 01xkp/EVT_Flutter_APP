import 'package:aipin/features/device_discovery/application/discovery_controller.dart';
import 'package:aipin/features/device_discovery/domain/advertisement_filter.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_ble_transport.dart';

void main() {
  test(
    'lists only advertisements that satisfy the V1.5 EVT contract',
    () async {
      final transport = FakeBleTransport();
      final controller = DiscoveryController(
        transport,
        const AdvertisementFilter(),
      );
      addTearDown(controller.dispose);

      controller.start();
      transport.emitCandidate(
        FakeBleTransport.weakMatchingCandidate.copyWith(
          connectionId: 'A3:89:01:02:03:04',
          name: 'AIPIN_0506',
          manufacturerData: const [
            0xA3,
            0x89,
            0x01,
            0x02,
            0x03,
            0x04,
            0x05,
            0x06,
          ],
          serviceUuids: const ['AF30'],
        ),
      );
      transport.emitCandidate(
        FakeBleTransport.weakMatchingCandidate.copyWith(
          connectionId: 'unknown-device',
          name: 'Unknown BLE',
          manufacturerData: const [],
          serviceUuids: const [],
        ),
      );
      transport.emitCandidate(FakeBleTransport.matchingCandidate);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.candidates, hasLength(2));
      expect(controller.state.candidates.first.name, 'AIPIN_8423');
      expect(controller.state.candidates.first.rssi, -48);
      expect(
        controller.state.candidates.map((candidate) => candidate.connectionId),
        isNot(contains('unknown-device')),
      );
      expect(controller.state.connectEnabled, isFalse);
    },
  );

  test('does not list advertisements without a local name', () async {
    final transport = FakeBleTransport();
    final controller = DiscoveryController(
      transport,
      const AdvertisementFilter(),
    );
    addTearDown(controller.dispose);

    controller.start();
    transport.emitCandidate(
      FakeBleTransport.matchingCandidate.copyWith(name: '   '),
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.candidates, isEmpty);
  });

  test(
    'lists named advertisements when strict EVT filtering is disabled',
    () async {
      final transport = FakeBleTransport();
      final controller = DiscoveryController(
        transport,
        const AdvertisementFilter(),
        filterByV15Advertisement: false,
      );
      addTearDown(controller.dispose);

      controller.start();
      transport.emitCandidate(
        FakeBleTransport.weakMatchingCandidate.copyWith(
          connectionId: 'temporary-evt-device',
          name: 'EVT debug peripheral',
          manufacturerData: const [],
          serviceUuids: const [],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.candidates, hasLength(1));
      expect(
        controller.state.candidates.single.connectionId,
        'temporary-evt-device',
      );
      controller.select(controller.state.candidates.single);
      expect(controller.state.connectEnabled, isTrue);
    },
  );

  test(
    'merges V1.5 primary advertisement and scan response before filtering',
    () async {
      final transport = FakeBleTransport();
      final controller = DiscoveryController(
        transport,
        const AdvertisementFilter(),
      );
      addTearDown(controller.dispose);

      final primaryAdvertisement = FakeBleTransport.matchingCandidate.copyWith(
        name: '',
        serviceUuids: const [],
      );
      final scanResponse = FakeBleTransport.matchingCandidate.copyWith(
        manufacturerData: const [],
      );

      controller.start();
      transport.emitCandidate(primaryAdvertisement);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.candidates, isEmpty);

      transport.emitCandidate(scanResponse);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.candidates, hasLength(1));
      expect(controller.state.candidates.single.name, 'AIPIN_8423');

      await controller.stop();
      controller.start();
      transport.emitCandidate(scanResponse);
      transport.emitCandidate(primaryAdvertisement);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.candidates, hasLength(1));
      expect(
        controller.state.candidates.single.manufacturerData,
        FakeBleTransport.matchingCandidate.manufacturerData,
      );
      expect(
        controller.state.candidates.single.serviceUuids,
        FakeBleTransport.matchingCandidate.serviceUuids,
      );
    },
  );

  test(
    'scan failure exposes a recoverable state without retaining selection',
    () async {
      final transport = FakeBleTransport();
      final controller = DiscoveryController(
        transport,
        const AdvertisementFilter(),
      );
      addTearDown(controller.dispose);

      controller.start();
      transport.emitScanError(StateError('bluetooth off'));
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.failure, isNotNull);
      expect(controller.state.connectEnabled, isFalse);
    },
  );

  test('a new scan clears devices from the previous scan', () async {
    final transport = FakeBleTransport();
    final controller = DiscoveryController(
      transport,
      const AdvertisementFilter(),
    );
    addTearDown(controller.dispose);

    controller.start();
    transport.emitCandidate(FakeBleTransport.matchingCandidate);
    await Future<void>.delayed(Duration.zero);
    await controller.stop();

    controller.start();

    expect(controller.state.candidates, isEmpty);
    expect(controller.state.selected, isNull);
  });

  test(
    'a repeated device advertisement updates one row without duplication',
    () async {
      final transport = FakeBleTransport();
      final controller = DiscoveryController(
        transport,
        const AdvertisementFilter(),
      );
      addTearDown(controller.dispose);

      controller.start();
      transport.emitCandidate(FakeBleTransport.weakMatchingCandidate);
      transport.emitCandidate(
        FakeBleTransport.weakMatchingCandidate.copyWith(rssi: -52),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.candidates, hasLength(1));
      expect(controller.state.candidates.single.rssi, -52);
    },
  );

  test('removes a device when its advertisements stop arriving', () async {
    final transport = FakeBleTransport();
    final controller = DiscoveryController(
      transport,
      const AdvertisementFilter(),
      staleDeviceTimeout: const Duration(milliseconds: 40),
      expiryCheckInterval: const Duration(milliseconds: 10),
    );
    addTearDown(controller.dispose);

    controller.start();
    transport.emitCandidate(FakeBleTransport.matchingCandidate);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.candidates, hasLength(1));

    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(controller.state.candidates, isEmpty);
  });

  test('does not list an App-connected device', () async {
    final transport = FakeBleTransport();
    final controller = DiscoveryController(
      transport,
      const AdvertisementFilter(),
    );
    addTearDown(controller.dispose);

    controller.setExcludedDeviceIds({
      FakeBleTransport.matchingCandidate.connectionId,
    });
    controller.start();
    transport.emitCandidate(FakeBleTransport.matchingCandidate);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.candidates, isEmpty);
  });

  test('clears the selected device when it becomes excluded', () async {
    final transport = FakeBleTransport();
    final controller = DiscoveryController(
      transport,
      const AdvertisementFilter(),
    );
    addTearDown(controller.dispose);

    controller.start();
    transport.emitCandidate(FakeBleTransport.matchingCandidate);
    await Future<void>.delayed(Duration.zero);
    controller.select(FakeBleTransport.matchingCandidate);

    controller.setExcludedDeviceIds({
      FakeBleTransport.matchingCandidate.connectionId,
    });

    expect(controller.state.candidates, isEmpty);
    expect(controller.state.selected, isNull);
  });
}
