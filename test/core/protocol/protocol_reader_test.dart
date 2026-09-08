import 'package:aipin/core/protocol/protocol_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads documented little-endian and big-endian integers', () {
    final reader = ProtocolReader(const [
      0x34,
      0x12,
      0x78,
      0x56,
      0x34,
      0x12,
      0x80,
      0xFF,
      0xFF,
      0xFF,
      0x12,
      0x34,
      0x56,
      0x78,
    ]);

    expect(reader.u16Le(0), 0x1234);
    expect(reader.u32Le(2), 0x12345678);
    expect(reader.s32Le(6), -128);
    expect(reader.u32Be(10), 0x12345678);
  });

  test('reads a fixed ASCII filename slot only when it is valid', () {
    final reader = ProtocolReader(const [
      0x61,
      0x62,
      0x63,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
    ]);

    expect(reader.asciiSlot17(0), 'abc');
    expect(
      () => ProtocolReader(const [0xFF]).asciiSlot17(0),
      throwsFormatException,
    );
    expect(
      () => ProtocolReader(List<int>.filled(17, 0)).asciiSlot17(0),
      throwsFormatException,
    );
    for (final invalidName in <String>['file/one.ogg', r'file\one.ogg']) {
      expect(
        () => ProtocolReader([
          ...invalidName.codeUnits,
          0,
          ...List<int>.filled(16 - invalidName.length, 0),
        ]).asciiSlot17(0),
        throwsFormatException,
      );
    }
  });
}
