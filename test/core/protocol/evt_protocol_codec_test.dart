import 'package:evt_ble_app/core/diagnostics/evt_failure.dart';
import 'package:evt_ble_app/core/protocol/crc16.dart';
import 'package:evt_ble_app/core/protocol/evt_protocol_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the documented CRC-16/CCITT-FALSE test vector', () {
    expect(
      Crc16CcittFalse.calculate(const [0x09, 0x00, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36]),
      0x48D3,
    );
  });

  test('decodes a complete 0xED frame after CRC validation', () {
    final result = EvtProtocolCodec().decode(const [0xED, 0x03, 0x00, 0x01, 0xD1, 0xF1]);

    expect(result.isSuccess, isTrue);
    expect(result.value!.command, 0x01);
    expect(result.value!.content, isEmpty);
  });

  test('rejects a frame whose declared length differs from content', () {
    final result = EvtProtocolCodec().decode(const [0xED, 0x04, 0x00, 0x01, 0xD1, 0xF1]);

    expect(result.failure!.kind, EvtFailureKind.protocol);
  });

  test('rejects an invalid CRC and retains unknown commands when valid', () {
    final invalid = EvtProtocolCodec().decode(const [0xED, 0x03, 0x00, 0x01, 0x00, 0x00]);
    final unknown = EvtProtocolCodec().decode(const [0xED, 0x03, 0x00, 0x7E, 0xA9, 0x7E]);

    expect(invalid.failure!.kind, EvtFailureKind.protocol);
    expect(unknown.isSuccess, isTrue);
    expect(unknown.value!.command, 0x7E);
  });
}
