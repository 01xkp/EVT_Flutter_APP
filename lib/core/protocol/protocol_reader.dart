import 'dart:convert';

class ProtocolReader {
  ProtocolReader(Iterable<int> bytes) : bytes = List.unmodifiable(bytes);

  final List<int> bytes;

  int u8(int offset) => _at(offset);

  int u16Le(int offset) => _at(offset) | (_at(offset + 1) << 8);

  int u32Le(int offset) =>
      _at(offset) |
      (_at(offset + 1) << 8) |
      (_at(offset + 2) << 16) |
      (_at(offset + 3) << 24);

  int s32Le(int offset) {
    final value = u32Le(offset);
    return value >= 0x80000000 ? value - 0x100000000 : value;
  }

  int u16Be(int offset) => (_at(offset) << 8) | _at(offset + 1);

  int u32Be(int offset) =>
      (_at(offset) << 24) |
      (_at(offset + 1) << 16) |
      (_at(offset + 2) << 8) |
      _at(offset + 3);

  String asciiSlot17(int offset) {
    _check(offset, 17);
    final slot = bytes.sublist(offset, offset + 17);
    final nul = slot.indexOf(0);
    if (nul < 0 || slot.skip(nul + 1).any((byte) => byte != 0)) {
      throw const FormatException('FileName[17] 必须包含 NUL 且尾部为零。');
    }
    if (slot.take(nul).any((byte) => byte < 0x20 || byte > 0x7E)) {
      throw const FormatException('FileName[17] 只能包含 ASCII 可打印字符。');
    }
    final value = ascii.decode(slot.take(nul).toList());
    if (value.isEmpty) {
      throw const FormatException('FileName[17] 不能为空。');
    }
    if (value.contains('/') || value.contains(r'\')) {
      throw const FormatException('FileName[17] 不能包含路径分隔符。');
    }
    return value;
  }

  int _at(int offset) {
    _check(offset, 1);
    final value = bytes[offset];
    if (value < 0 || value > 0xFF) {
      throw const FormatException('协议字节超出范围。');
    }
    return value;
  }

  void _check(int offset, int length) {
    if (offset < 0 || length < 0 || offset + length > bytes.length) {
      throw const FormatException('协议字段长度不足。');
    }
  }
}
