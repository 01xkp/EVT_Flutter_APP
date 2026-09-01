import 'dart:typed_data';

import 'package:aipin/core/ble/ble_transport.dart';
import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/features/device_discovery/domain/device_candidate.dart';
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

  test('transport exposes write and write-without-response primitives', () async {
    final transport = FakeBleTransport();
    final characteristic = const BleCharacteristic(
      deviceId: 'device-1',
      serviceUuid: '0000FA10-0000-1000-8000-00805F9B34FB',
      characteristicUuid: '0000FA15-0000-1000-8000-00805F9B34FB',
    );

    await transport.write(characteristic, Uint8List.fromList([1, 2]));
    await transport.writeWithoutResponse(
      characteristic,
      Uint8List.fromList([3, 4]),
    );

    expect(transport.writes, hasLength(1));
    expect(transport.writesWithoutResponse, hasLength(1));
  });
}
