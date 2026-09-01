import 'dart:typed_data';

import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/protocol/wqota_client.dart';
import 'package:aipin/core/protocol/wqota_codec.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_ble_transport.dart';

void main() {
  const codec = WqotaCodec(
    wireFormat: WqotaWireFormat(
      requestPrefixFlags: [0x70, 0x07, 0x6E, 0xC1],
      responsePrefixFlags: [0x70, 0x07, 0x6E, 0x01],
    ),
  );
  const characteristic = BleCharacteristic(
    deviceId: 'device-1',
    serviceUuid: '00007033-0000-1000-8000-00805F9B34FB',
    characteristicUuid: '00002001-0000-1000-8000-00805F9B34FB',
  );

  test(
    'writes WQOTA without response and matches the reply serial number',
    () async {
      final transport = FakeBleTransport();
      final client = WqotaClient(
        transport: transport,
        writeCharacteristic: characteristic,
        notifications: transport.subscriptionStream,
        codec: codec,
      );

      final request = client.execute(
        opcode: WqotaOpcode.getFileInfoOffset,
        data: const [7],
        serialNumber: 7,
      );
      await Future<void>.delayed(Duration.zero);
      expect(transport.writesWithoutResponse, hasLength(1));
      transport.emitSubscriptionBytes(
        _responseFrame(
          opcode: WqotaOpcode.getFileInfoOffset,
          data: const [0, 7, 0, 0, 0, 18, 0],
        ),
      );

      final response = await request;
      expect(response.data.sublist(0, 2), <int>[0, 7]);
      await client.close();
    },
  );

  test(
    'waits for the last serial of a window sent without responses',
    () async {
      final transport = FakeBleTransport();
      final client = WqotaClient(
        transport: transport,
        writeCharacteristic: characteristic,
        notifications: transport.subscriptionStream,
        codec: codec,
      );
      addTearDown(client.close);

      final response = client.waitForNotification(
        opcode: WqotaOpcode.sendFirmwareBlock,
        serialNumber: 9,
      );
      await client.sendWithoutResponse(
        opcode: WqotaOpcode.sendFirmwareBlock,
        data: const [9, 0, 0, 0, 18, 1, 2, 3, 0, 0, 0, 0],
      );
      transport.emitSubscriptionBytes(
        _responseFrame(
          opcode: WqotaOpcode.sendFirmwareBlock,
          data: const [0, 9, 0, 0, 0, 21, 0, 0, 0, 0, 0],
        ),
      );

      expect((await response).data.sublist(0, 2), [0, 9]);
      expect(transport.writesWithoutResponse, hasLength(1));
    },
  );
}

Uint8List _responseFrame({
  required WqotaOpcode opcode,
  required List<int> data,
}) => Uint8List.fromList(<int>[
  0x70,
  0x07,
  0x6E,
  0x01,
  opcode.value,
  (data.length >> 8) & 0xFF,
  data.length & 0xFF,
  ...data,
  0x33,
]);
