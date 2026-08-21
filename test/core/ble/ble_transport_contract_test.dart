import 'package:evt_ble_app/core/ble/ble_transport.dart';
import 'package:evt_ble_app/features/device_discovery/domain/device_candidate.dart';
import '../../support/fake_ble_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('transport exposes scan candidates and controlled disconnect', () async {
    final transport = FakeBleTransport();
    final candidates = <DeviceCandidate>[];
    final subscription = transport.scan().listen(candidates.add);

    transport.emitCandidate(FakeBleTransport.matchingCandidate);
    await Future<void>.delayed(Duration.zero);

    expect(candidates, [FakeBleTransport.matchingCandidate]);
    await subscription.cancel();
    await transport.disconnect(FakeBleTransport.matchingCandidate.id);
    expect(
      transport.disconnectedDeviceIds,
      contains(FakeBleTransport.matchingCandidate.id),
    );
  });

  test('transport contracts keep plugin types out of feature code', () {
    final transport = FakeBleTransport();

    expect(transport, isA<BleTransport>());
  });
}
