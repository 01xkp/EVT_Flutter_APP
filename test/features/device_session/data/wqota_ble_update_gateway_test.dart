import 'dart:typed_data';

import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/protocol/wqota_client.dart';
import 'package:aipin/core/protocol/wqota_codec.dart';
import 'package:aipin/features/device_session/data/wqota_ble_update_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_ble_transport.dart';

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

  test('derives the E5 payload limit from the negotiated ATT MTU', () {
    expect(WqotaBleUpdateGateway.maximumBlockBytesForMtu(23), 3);
    expect(WqotaBleUpdateGateway.maximumBlockBytesForMtu(185), 165);
    expect(WqotaBleUpdateGateway.maximumBlockBytesForMtu(517), 497);
    expect(
      () => WqotaBleUpdateGateway.maximumBlockBytesForMtu(20),
      throwsRangeError,
    );
  });

  test(
    'rejects transport preparation when E2 cannot fit in one ATT write',
    () async {
      final transport = FakeBleTransport();
      final client = WqotaClient(
        transport: transport,
        writeCharacteristic: characteristic,
        notifications: transport.subscriptionStream,
        codec: codec,
      );
      addTearDown(client.close);
      final gateway = WqotaBleUpdateGateway(
        client: client,
        requestMtu: () async => 27,
        verifyBusinessVersionCallback: (_) async => true,
      );

      await expectLater(gateway.prepareTransport(), throwsStateError);
    },
  );

  test(
    'sends one E5 window with continuous offsets, serials, and CRC32',
    () async {
      final transport = FakeBleTransport();
      final client = WqotaClient(
        transport: transport,
        writeCharacteristic: characteristic,
        notifications: transport.subscriptionStream,
        codec: codec,
      );
      addTearDown(client.close);
      final gateway = WqotaBleUpdateGateway(
        client: client,
        maximumBlockBytes: 2,
        verifyBusinessVersionCallback: (_) async => true,
      );

      final result = gateway.transferWindow(
        offset: 18,
        bytes: Uint8List.fromList(const [0xAA, 0xBB, 0xCC]),
      );
      await Future<void>.delayed(Duration.zero);

      transport.emitSubscriptionBytes(
        _responseFrame(
          opcode: WqotaOpcode.sendFirmwareBlock,
          data: const [0, 2, 0, 0, 0, 0, 21, 0, 0, 0, 0],
        ),
      );
      final next = await result;

      expect(transport.writesWithoutResponse, hasLength(2));
      expect(transport.writesWithoutResponse[0].sublist(0, 7), const [
        0x70,
        0x07,
        0x6E,
        0xC1,
        0xE5,
        0,
        11,
      ]);
      expect(transport.writesWithoutResponse[0].sublist(7, 18), const [
        1,
        0,
        0,
        0,
        18,
        0xAA,
        0xBB,
        0x49,
        0x82,
        0x2C,
        0x98,
      ]);
      expect(transport.writesWithoutResponse[1].sublist(0, 7), const [
        0x70,
        0x07,
        0x6E,
        0xC1,
        0xE5,
        0,
        10,
      ]);
      expect(transport.writesWithoutResponse[1].sublist(7, 17), const [
        2,
        0,
        0,
        0,
        20,
        0xCC,
        0x40,
        0xD0,
        0x61,
        0x16,
      ]);

      expect(next.offset, 21);
      expect(next.length, 0);
    },
  );

  test('rejects an E5 response whose result is not successful', () async {
    final transport = FakeBleTransport();
    final client = WqotaClient(
      transport: transport,
      writeCharacteristic: characteristic,
      notifications: transport.subscriptionStream,
      codec: codec,
    );
    addTearDown(client.close);
    final gateway = WqotaBleUpdateGateway(
      client: client,
      maximumBlockBytes: 2,
      verifyBusinessVersionCallback: (_) async => true,
    );

    final result = gateway.transferWindow(
      offset: 18,
      bytes: Uint8List.fromList(const [0xAA]),
    );
    await Future<void>.delayed(Duration.zero);
    transport.emitSubscriptionBytes(
      _responseFrame(
        opcode: WqotaOpcode.sendFirmwareBlock,
        data: const [0, 1, 5, 0, 0, 0, 18, 0, 1, 0, 0],
      ),
    );

    await expectLater(result, throwsStateError);
  });
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
