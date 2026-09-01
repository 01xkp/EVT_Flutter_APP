import 'dart:typed_data';

enum WqotaOpcode {
  getDeviceInfo(0x02),
  reboot(0x03),
  getFileInfoOffset(0xE1),
  inquiryIfCanUpdate(0xE2),
  enterUpdateMode(0xE3),
  exitUpdateMode(0xE4),
  sendFirmwareBlock(0xE5),
  getRefreshStatus(0xE6),
  getSyncState(0xE8);

  const WqotaOpcode(this.value);

  final int value;

  static WqotaOpcode fromValue(int value) => WqotaOpcode.values.firstWhere(
    (opcode) => opcode.value == value,
    orElse: () =>
        throw FormatException('未知 WQOTA opcode: 0x${value.toRadixString(16)}'),
  );
}

class WqotaWireFormat {
  const WqotaWireFormat({
    required this.requestPrefixFlags,
    required this.responsePrefixFlags,
    this.suffix = 0x33,
  });

  /// Each four-byte vector contains the captured 24-bit prefix and flags.
  /// The protocol makes request and response flags distinct, so neither is
  /// synthesized from a packed C bitfield or reused for the opposite route.
  final List<int> requestPrefixFlags;
  final List<int> responsePrefixFlags;
  final int suffix;
}

class WqotaFrame {
  const WqotaFrame({required this.opcode, required this.data});

  final WqotaOpcode opcode;
  final Uint8List data;
}

class WqotaCodec {
  const WqotaCodec({required this.wireFormat});

  final WqotaWireFormat wireFormat;

  Uint8List encode({required WqotaOpcode opcode, required List<int> data}) {
    _validateWireFormat();
    if (data.length > 0xFFFF) {
      throw RangeError.range(data.length, 0, 0xFFFF, 'data.length');
    }
    return Uint8List.fromList(<int>[
      ...wireFormat.requestPrefixFlags,
      opcode.value,
      (data.length >> 8) & 0xFF,
      data.length & 0xFF,
      ...data,
      wireFormat.suffix,
    ]);
  }

  WqotaFrame decode(List<int> bytes) {
    _validateWireFormat();
    if (bytes.length < 9) {
      throw const FormatException('WQOTA 帧长度不足。');
    }
    for (
      var index = 0;
      index < wireFormat.responsePrefixFlags.length;
      index += 1
    ) {
      if (bytes[index] != wireFormat.responsePrefixFlags[index]) {
        throw const FormatException('WQOTA 前缀不匹配。');
      }
    }
    if (bytes.last != wireFormat.suffix) {
      throw const FormatException('WQOTA 后缀不匹配。');
    }
    final dataLength = (bytes[5] << 8) | bytes[6];
    if (bytes.length != 8 + dataLength) {
      throw const FormatException('WQOTA DataLen 不匹配。');
    }
    return WqotaFrame(
      opcode: WqotaOpcode.fromValue(bytes[4]),
      data: Uint8List.fromList(bytes.sublist(7, 7 + dataLength)),
    );
  }

  void _validateWireFormat() {
    if (wireFormat.requestPrefixFlags.length != 4 ||
        wireFormat.responsePrefixFlags.length != 4) {
      throw const FormatException('WQOTA 请求和响应前缀均必须为 4 字节。');
    }
  }
}
