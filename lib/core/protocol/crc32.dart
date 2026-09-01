abstract final class Crc32IsoHdlc {
  static const _polynomial = 0xEDB88320;

  static int calculate(Iterable<int> bytes) {
    var crc = 0xFFFFFFFF;
    for (final byte in bytes) {
      crc ^= byte & 0xFF;
      for (var bit = 0; bit < 8; bit += 1) {
        crc = (crc & 1) == 1
            ? (crc >> 1) ^ _polynomial
            : crc >> 1;
      }
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}

