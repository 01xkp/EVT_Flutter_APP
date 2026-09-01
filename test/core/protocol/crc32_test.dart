import 'package:aipin/core/protocol/crc32.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('matches CRC-32/ISO-HDLC reference vector', () {
    expect(Crc32IsoHdlc.calculate('123456789'.codeUnits), 0xCBF43926);
  });
}
