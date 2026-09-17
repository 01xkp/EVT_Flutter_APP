import 'dart:typed_data';

/// WQOTA is a separate protocol carried by the 0x7033 service. It must not
/// be passed to the 0xED business-frame codec.
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
    orElse: () => throw FormatException(
      'Unknown WQOTA opcode: 0x${value.toRadixString(16).padLeft(2, '0')}.',
    ),
  );
}

/// A target-firmware-captured four-byte WQOTA prefix and flags vector.
///
/// V1.6 defines the logical 24-bit prefix as 0x6E0770, but the byte order of
/// the packed C field must be frozen from an actual target capture. The App
/// accepts the two endian encodings of that logical value, while requiring a
/// non-empty [captureId] so an arbitrary guessed vector cannot be enabled.
class WqotaWireFormat {
  factory WqotaWireFormat.captured({
    required String captureId,
    required List<int> requestPrefixFlags,
    required List<int> responsePrefixFlags,
  }) {
    final value = WqotaWireFormat._(
      captureId: captureId.trim(),
      requestPrefixFlags: List<int>.unmodifiable(requestPrefixFlags),
      responsePrefixFlags: List<int>.unmodifiable(responsePrefixFlags),
    );
    value.validate();
    return value;
  }

  const WqotaWireFormat._({
    required this.captureId,
    required this.requestPrefixFlags,
    required this.responsePrefixFlags,
  });

  static const suffix = 0x33;
  static const _littleEndianPrefix = <int>[0x70, 0x07, 0x6E];
  static const _bigEndianPrefix = <int>[0x6E, 0x07, 0x70];

  /// Identifies the firmware packet capture that produced these vectors.
  final String captureId;

  /// Prefix bytes followed by the packed request flags byte.
  final List<int> requestPrefixFlags;

  /// Prefix bytes followed by the packed response flags byte.
  final List<int> responsePrefixFlags;

  void validate() {
    if (captureId.isEmpty) {
      throw const FormatException(
        'WQOTA requires a target firmware capture ID.',
      );
    }
    _validateVector(requestPrefixFlags, isRequest: true);
    _validateVector(responsePrefixFlags, isRequest: false);
  }

  static void _validateVector(List<int> vector, {required bool isRequest}) {
    if (vector.length != 4 || vector.any((byte) => byte < 0 || byte > 0xFF)) {
      throw const FormatException(
        'WQOTA captured prefix/flags must contain 4 bytes.',
      );
    }
    final prefix = vector.sublist(0, 3);
    if (!_sameBytes(prefix, _littleEndianPrefix) &&
        !_sameBytes(prefix, _bigEndianPrefix)) {
      throw const FormatException(
        'WQOTA captured prefix is not logical 0x6E0770.',
      );
    }
    final flags = vector[3];
    if ((flags & 0x38) != 0) {
      throw const FormatException(
        'WQOTA packed flags reserve bits 3 through 5.',
      );
    }
    final isCommand = (flags & 0x80) != 0;
    if (isRequest && !isCommand) {
      throw const FormatException('WQOTA requests must set is_cmd.');
    }
    if (!isRequest && isCommand) {
      throw const FormatException('WQOTA responses must clear is_cmd.');
    }
  }

  static bool _sameBytes(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }
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
    wireFormat.validate();
    if (data.length > 0xFFFF) {
      throw RangeError.range(data.length, 0, 0xFFFF, 'data.length');
    }
    _validateBytes(data, field: 'data');
    return Uint8List.fromList(<int>[
      ...wireFormat.requestPrefixFlags,
      opcode.value,
      (data.length >> 8) & 0xFF,
      data.length & 0xFF,
      ...data,
      WqotaWireFormat.suffix,
    ]);
  }

  WqotaFrame decode(List<int> bytes) {
    wireFormat.validate();
    // A WQOTA frame is prefix/flags (4) + opcode (1) + DataLen (2) + suffix
    // (1); DataLen may legally be zero.
    if (bytes.length < 8) {
      throw const FormatException(
        'WQOTA frame is shorter than its fixed header.',
      );
    }
    _validateBytes(bytes, field: 'frame');
    for (var index = 0; index < 4; index += 1) {
      if (bytes[index] != wireFormat.responsePrefixFlags[index]) {
        throw const FormatException(
          'WQOTA response prefix/flags do not match.',
        );
      }
    }
    if (bytes.last != WqotaWireFormat.suffix) {
      throw const FormatException('WQOTA response suffix does not match.');
    }
    final dataLength = (bytes[5] << 8) | bytes[6];
    if (bytes.length != 8 + dataLength) {
      throw const FormatException(
        'WQOTA response DataLen does not match frame length.',
      );
    }
    return WqotaFrame(
      opcode: WqotaOpcode.fromValue(bytes[4]),
      data: Uint8List.fromList(bytes.sublist(7, 7 + dataLength)),
    );
  }

  static void _validateBytes(List<int> bytes, {required String field}) {
    for (final byte in bytes) {
      if (byte < 0 || byte > 0xFF) {
        throw RangeError.range(byte, 0, 0xFF, field);
      }
    }
  }
}
