import 'package:aipin/features/device_discovery/application/discovery_controller.dart';
import 'package:aipin/features/device_discovery/domain/advertisement_filter.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_ble_transport.dart';

void main() {
  test(
    'all scanned candidates become selectable and sort by strongest RSSI',
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
          id: 'unnamed-device',
          name: '   ',
          manufacturerData: const [],
          serviceUuids: const [],
        ),
      );
      transport.emitCandidate(
        FakeBleTransport.weakMatchingCandidate.copyWith(
          id: 'unknown-device',
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
      expect(controller.state.connectEnabled, isFalse);
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

    controller.setExcludedDeviceIds({FakeBleTransport.matchingCandidate.id});
    controller.start();
    transport.emitCandidate(FakeBleTransport.matchingCandidate);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.candidates, isEmpty);
  });
}
