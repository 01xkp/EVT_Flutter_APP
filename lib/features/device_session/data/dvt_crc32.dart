/// Incremental CRC-32/ISO-HDLC implementation frozen by the V1.6 file spec.
class DvtCrc32Accumulator {
  static const _polynomial = 0xEDB88320;
  var _crc = 0xFFFFFFFF;

  void add(Iterable<int> bytes) {
    for (final byte in bytes) {
      _crc ^= byte & 0xFF;
      for (var bit = 0; bit < 8; bit += 1) {
        _crc = (_crc & 1) == 1 ? (_crc >> 1) ^ _polynomial : _crc >> 1;
      }
    }
  }

  int get value => (_crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
