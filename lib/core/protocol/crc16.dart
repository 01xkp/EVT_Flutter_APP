abstract final class Crc16CcittFalse {
  static const _polynomial = 0x1021;
  static const _initialValue = 0xFFFF;

  static int calculate(Iterable<int> bytes) {
    var crc = _initialValue;
    for (final byte in bytes) {
      crc ^= (byte & 0xFF) << 8;
      for (var bit = 0; bit < 8; bit += 1) {
        crc = (crc & 0x8000) == 0
            ? (crc << 1) & 0xFFFF
            : ((crc << 1) ^ _polynomial) & 0xFFFF;
      }
    }
    return crc;
  }
}
