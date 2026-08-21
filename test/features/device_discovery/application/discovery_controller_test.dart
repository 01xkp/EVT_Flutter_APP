import 'package:evt_ble_app/features/device_discovery/application/discovery_controller.dart';
import 'package:evt_ble_app/features/device_discovery/domain/advertisement_filter.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_ble_transport.dart';

void main() {
  test('only matching candidates become selectable and sort by strongest RSSI', () async {
    final transport = FakeBleTransport();
    final controller = DiscoveryController(transport, const AdvertisementFilter());
    addTearDown(controller.dispose);

    controller.start();
    transport.emitCandidate(FakeBleTransport.weakMatchingCandidate);
    transport.emitCandidate(FakeBleTransport.matchingCandidate);
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.candidates.first.name, 'AIPIN_8423');
    expect(controller.state.candidates.first.rssi, -48);
    expect(controller.state.connectEnabled, isFalse);
  });

  test('scan failure exposes a recoverable state without retaining selection', () async {
    final transport = FakeBleTransport();
    final controller = DiscoveryController(transport, const AdvertisementFilter());
    addTearDown(controller.dispose);

    controller.start();
    transport.emitScanError(StateError('bluetooth off'));
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.failure, isNotNull);
    expect(controller.state.connectEnabled, isFalse);
  });
}
