import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/protocol/evt_protocol_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EVT V1.6 framed write admission contract', () {
    test('maps every framed command to its documented endpoint', () {
      expect(
        EvtProtocolContract.writeCommandEndpoints,
        <int, BleLogicalEndpoint>{
          0x01: BleLogicalEndpoint.fa10Fa11,
          0x02: BleLogicalEndpoint.fa10Fa12,
          0x05: BleLogicalEndpoint.fa10Fa15,
          0x06: BleLogicalEndpoint.fa10Fa16,
          0x07: BleLogicalEndpoint.fa10Fa17,
          0x09: BleLogicalEndpoint.fa10Fa19,
          0x21: BleLogicalEndpoint.ff10Ff11,
          0x22: BleLogicalEndpoint.ff10Ff12,
          0x23: BleLogicalEndpoint.ff10Ff13,
          0x26: BleLogicalEndpoint.ff10Ff16,
        },
      );
      expect(EvtProtocolContract.writeEndpointForCommand(0x11), isNull);
    });

    test('accepts the fixed V1.6 payload shapes used by the repository', () {
      EvtProtocolContract.validateWritePayload(0x01, const []);
      EvtProtocolContract.validateWritePayload(0x02, [
        0,
        0,
        0,
        0,
        0x08,
        0x07,
        1,
        2,
        0,
        0,
        1,
        0,
      ]);
      EvtProtocolContract.validateWritePayload(0x02, [
        0,
        0,
        0,
        0,
        0x08,
        0x07,
        1,
        2,
        0,
        0,
        1,
        1,
      ]);
      EvtProtocolContract.validateWritePayload(0x05, const []);
      for (final payload in <List<int>>[
        [0x01],
        [0x02, 0x01, 1],
        [0x03],
        [0x04, 0x01, 3],
      ]) {
        EvtProtocolContract.validateWritePayload(0x06, payload);
      }
      EvtProtocolContract.validateWritePayload(0x07, [3]);
      EvtProtocolContract.validateWritePayload(0x09, [2, 1, 2, 3, 4, 5, 6]);
      EvtProtocolContract.validateWritePayload(0x21, const []);
      EvtProtocolContract.validateWritePayload(0x22, [0xFF, 0xFF, 20]);
      EvtProtocolContract.validateWritePayload(0x23, _nameSlot);
      EvtProtocolContract.validateWritePayload(0x23, [
        ..._nameSlot,
        0,
        0,
        0,
        0,
        0,
        0,
      ]);
      EvtProtocolContract.validateWritePayload(0x26, [
        0x01,
        0x11,
        ..._nameSlot,
      ]);
      EvtProtocolContract.validateWritePayload(0x26, [
        0x02,
        0x1A,
        ..._nameSlot,
        0x78,
        0x56,
        0x34,
        0x12,
        0xEF,
        0xCD,
        0xAB,
        0x90,
        0x01,
      ]);
    });

    test('rejects fixed-length and enum violations before native write', () {
      _expectRejected(0x01, [0]);
      _expectRejected(0x05, [0]);
      _expectRejected(0x02, List<int>.filled(11, 0));
      _expectRejected(0x02, [...List<int>.filled(6, 0), 2, 2, 0, 0, 0, 0]);
      _expectRejected(0x02, [...List<int>.filled(7, 0), 3, 0, 0, 0, 0]);
      _expectRejected(0x02, [...List<int>.filled(8, 0), 2, 0, 0, 0]);
      _expectRejected(0x02, [0, 0, 0, 0, 0x08, 0x07, 1, 2, 0, 0, 0, 2]);
      _expectRejected(0x07, [4]);
      _expectRejected(0x09, [3, 1, 2, 3, 4, 5, 6]);
      _expectRejected(0x11, const []);
    });

    test('rejects malformed status, page and file transfer payloads', () {
      _expectRejected(0x06, const []);
      _expectRejected(0x06, [0x01, 0]);
      _expectRejected(0x06, [0x02, 0, 1]);
      _expectRejected(0x06, [0x02, 1, 2]);
      _expectRejected(0x06, [0x04, 1, 4]);
      _expectRejected(0x06, [0x80]);
      _expectRejected(0x22, [0, 0]);
      _expectRejected(0x22, [0, 0, 0]);
      _expectRejected(0x22, [0, 0, 21]);
      _expectRejected(0x23, List<int>.filled(16, 0));
      _expectRejected(0x23, [..._nameSlot, 1]);
      _expectRejected(0x23, [..._nameSlot, 0, 0, 0, 0, 0, 0xE1, 0x01]);
      _expectRejected(0x23, [..._nameSlot, 1, 0, 0, 0, 0, 0xE1, 0x01]);
      _expectRejected(0x23, [
        ..._nameSlot.sublist(0, 2),
        0x2F,
        ...List<int>.filled(14, 0),
      ]);
      _expectRejected(0x26, [0x01, 0x11, ...List<int>.filled(16, 0)]);
      _expectRejected(0x26, [0x01, 0x10, ..._nameSlot]);
      _expectRejected(0x26, [
        0x02,
        0x19,
        ..._nameSlot,
        ...List<int>.filled(8, 0),
        0x01,
      ]);
      _expectRejected(0x26, [
        0x02,
        0x1A,
        ..._nameSlot,
        ...List<int>.filled(8, 0),
        0x00,
      ]);
      _expectRejected(0x26, [
        0x01,
        0x11,
        ..._nameSlot.sublist(0, 2),
        0x2F,
        ...List<int>.filled(14, 0),
      ]);
    });
  });
}

void _expectRejected(int command, List<int> content) {
  expect(
    () => EvtProtocolContract.validateWritePayload(command, content),
    throwsA(isA<StateError>()),
    reason: 'command=0x${command.toRadixString(16)} content=$content',
  );
}

const _nameSlot = <int>[
  0x36,
  0x61,
  0x37,
  0x62,
  0x65,
  0x37,
  0x30,
  0x34,
  0x5F,
  0x30,
  0x30,
  0x31,
  0x2E,
  0x6F,
  0x67,
  0x67,
  0,
];
