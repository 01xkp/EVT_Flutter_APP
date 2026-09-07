import 'dart:convert';

class ProtocolWriter {
  final List<int> bytes = <int>[];

  void u8(int value) {
    _check(value, 0xFF);
    bytes.add(value);
  }

  void u16Le(int value) {
    _check(value, 0xFFFF);
    bytes
      ..add(value & 0xFF)
      ..add((value >> 8) & 0xFF);
  }

  void u32Le(int value) {
    _check(value, 0xFFFFFFFF);
    bytes
      ..add(value & 0xFF)
      ..add((value >> 8) & 0xFF)
      ..add((value >> 16) & 0xFF)
      ..add((value >> 24) & 0xFF);
  }

  void s32Le(int value) => u32Le(value < 0 ? value + 0x100000000 : value);

  void u16Be(int value) {
    _check(value, 0xFFFF);
    bytes
      ..add((value >> 8) & 0xFF)
      ..add(value & 0xFF);
  }

  void u32Be(int value) {
    _check(value, 0xFFFFFFFF);
    bytes
      ..add((value >> 24) & 0xFF)
      ..add((value >> 16) & 0xFF)
      ..add((value >> 8) & 0xFF)
      ..add(value & 0xFF);
  }

  void asciiSlot17(String value) {
    final encoded = ascii.encode(value);
    if (encoded.length > 16 ||
        encoded.any((byte) => byte < 0x20 || byte > 0x7E)) {
      throw const FormatException('FileName[17] 只能是最多 16 字节 ASCII。');
    }
    bytes
      ..addAll(encoded)
      ..add(0)
      ..addAll(List<int>.filled(16 - encoded.length, 0));
  }

  void addAll(Iterable<int> values) {
    for (final value in values) {
      _check(value, 0xFF);
      bytes.add(value);
    }
  }

  static void _check(int value, int max) {
    if (value < 0 || value > max) {
      throw RangeError.range(value, 0, max);
    }
  }
}
