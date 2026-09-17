import 'package:aipin/core/protocol/wqota_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final format = WqotaWireFormat.captured(
    captureId: 'dvt-v1.6-target-capture-001',
    requestPrefixFlags: const <int>[0x70, 0x07, 0x6E, 0xC1],
    responsePrefixFlags: const <int>[0x70, 0x07, 0x6E, 0x01],
  );
  final codec = WqotaCodec(wireFormat: format);

  test('encodes V1.6 WQOTA DataLen as big endian', () {
    expect(
      codec.encode(opcode: WqotaOpcode.getFileInfoOffset, data: const <int>[7]),
      <int>[0x70, 0x07, 0x6E, 0xC1, 0xE1, 0, 1, 7, 0x33],
    );
  });

  test('decodes an exactly delimited response including zero-length data', () {
    final frame = codec.decode(const <int>[
      0x70,
      0x07,
      0x6E,
      0x01,
      0x03,
      0,
      0,
      0x33,
    ]);

    expect(frame.opcode, WqotaOpcode.reboot);
    expect(frame.data, isEmpty);
  });

  test('rejects a response with a mismatched declared data length', () {
    expect(
      () => codec.decode(const <int>[
        0x70,
        0x07,
        0x6E,
        0x01,
        0xE5,
        0,
        3,
        1,
        2,
        0x33,
      ]),
      throwsFormatException,
    );
  });

  test('requires target-captured prefix and legal packed flag bits', () {
    expect(
      () => WqotaWireFormat.captured(
        captureId: '',
        requestPrefixFlags: const <int>[0x70, 0x07, 0x6E, 0xC1],
        responsePrefixFlags: const <int>[0x70, 0x07, 0x6E, 0x01],
      ),
      throwsFormatException,
    );
    expect(
      () => WqotaWireFormat.captured(
        captureId: 'bad-prefix',
        requestPrefixFlags: const <int>[0x70, 0x07, 0x6F, 0xC1],
        responsePrefixFlags: const <int>[0x70, 0x07, 0x6F, 0x01],
      ),
      throwsFormatException,
    );
    expect(
      () => WqotaWireFormat.captured(
        captureId: 'reserved-flag',
        requestPrefixFlags: const <int>[0x70, 0x07, 0x6E, 0xC9],
        responsePrefixFlags: const <int>[0x70, 0x07, 0x6E, 0x01],
      ),
      throwsFormatException,
    );
    expect(
      () => WqotaWireFormat.captured(
        captureId: 'wrong-direction',
        requestPrefixFlags: const <int>[0x70, 0x07, 0x6E, 0x41],
        responsePrefixFlags: const <int>[0x70, 0x07, 0x6E, 0x81],
      ),
      throwsFormatException,
    );
  });
}
