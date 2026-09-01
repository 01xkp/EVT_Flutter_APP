import 'package:aipin/core/protocol/wqota_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const codec = WqotaCodec(
    wireFormat: WqotaWireFormat(
      requestPrefixFlags: [0x70, 0x07, 0x6E, 0xC1],
      responsePrefixFlags: [0x70, 0x07, 0x6E, 0x01],
    ),
  );

  test('encodes the independent WQOTA frame with big-endian data length', () {
    expect(
      codec.encode(opcode: WqotaOpcode.getFileInfoOffset, data: const [7]),
      <int>[0x70, 0x07, 0x6E, 0xC1, 0xE1, 0, 1, 7, 0x33],
    );
  });

  test('decodes only an exactly delimited WQOTA frame', () {
    final frame = codec.decode(const [
      0x70,
      0x07,
      0x6E,
      0x01,
      0xE5,
      0,
      2,
      8,
      9,
      0x33,
    ]);

    expect(frame.opcode, WqotaOpcode.sendFirmwareBlock);
    expect(frame.data, <int>[8, 9]);
    expect(
      () =>
          codec.decode(const [0x70, 0x07, 0x6E, 0x01, 0xE5, 0, 3, 8, 9, 0x33]),
      throwsFormatException,
    );
  });

  test('encodes the WQOTA reboot opcode outside the business frame codec', () {
    expect(codec.encode(opcode: WqotaOpcode.reboot, data: const [8, 0]), <int>[
      0x70,
      0x07,
      0x6E,
      0xC1,
      0x03,
      0,
      2,
      8,
      0,
      0x33,
    ]);
  });
}
