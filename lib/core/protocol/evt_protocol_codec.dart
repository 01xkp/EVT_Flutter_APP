import 'dart:typed_data';

import 'package:aipin/core/diagnostics/evt_failure.dart';
import 'package:aipin/core/protocol/crc16.dart';
import 'package:aipin/core/protocol/evt_frame.dart';
import 'package:aipin/core/protocol/protocol_writer.dart';

class EvtProtocolCodec {
  static const _head = 0xED;
  static const _minimumLengthField = 3;
  static const _prefixLength = 3;
  static const _minimumFrameLength = 6;

  Uint8List encodeRequest(int command, Iterable<int> content) {
    if (command < 0 || command > 0xFF) {
      throw RangeError.range(command, 0, 0xFF);
    }
    final writer = ProtocolWriter()..u8(command);
    writer.addAll(content);
    final crc = Crc16CcittFalse.calculate(writer.bytes);
    final length = writer.bytes.length + 2;
    if (length > 0xFFFF) {
      throw StateError('业务帧长度超出协议上限。');
    }
    return Uint8List.fromList([
      _head,
      length & 0xFF,
      (length >> 8) & 0xFF,
      ...writer.bytes,
      crc & 0xFF,
      (crc >> 8) & 0xFF,
    ]);
  }

  ProtocolDecodeResult decode(List<int> bytes) {
    if (bytes.length < _minimumFrameLength) {
      return ProtocolDecodeResult.failure(
        EvtFailure.protocol(message: '业务帧长度不足。'),
      );
    }
    if (bytes.first != _head) {
      return ProtocolDecodeResult.failure(
        EvtFailure.protocol(message: '业务帧同步字无效。'),
      );
    }

    final declaredLength = bytes[1] | (bytes[2] << 8);
    if (declaredLength < _minimumLengthField ||
        bytes.length != declaredLength + _prefixLength) {
      return ProtocolDecodeResult.failure(
        EvtFailure.protocol(
          message: '业务帧声明长度与实际长度不一致。',
          detail: 'declared=$declaredLength actual=${bytes.length}',
        ),
      );
    }

    final contentLength = declaredLength - _minimumLengthField;
    final command = bytes[3];
    final contentEnd = 4 + contentLength;
    final expectedCrc = bytes[contentEnd] | (bytes[contentEnd + 1] << 8);
    final actualCrc = Crc16CcittFalse.calculate(bytes.sublist(3, contentEnd));
    if (actualCrc != expectedCrc) {
      return ProtocolDecodeResult.failure(
        EvtFailure.protocol(
          message: 'CRC 校验失败。',
          detail: 'expected=${_hex(expectedCrc)} actual=${_hex(actualCrc)}',
        ),
      );
    }

    return ProtocolDecodeResult.success(
      EvtFrame(
        command: command,
        content: Uint8List.fromList(bytes.sublist(4, contentEnd)),
        rawBytes: Uint8List.fromList(bytes),
      ),
    );
  }

  static String _hex(int value) =>
      '0x${value.toRadixString(16).padLeft(4, '0').toUpperCase()}';
}

sealed class ProtocolDecodeResult {
  const ProtocolDecodeResult();

  const factory ProtocolDecodeResult.success(EvtFrame frame) =
      ProtocolDecodeSuccess;
  const factory ProtocolDecodeResult.failure(EvtFailure failure) =
      ProtocolDecodeFailure;

  bool get isSuccess => this is ProtocolDecodeSuccess;

  EvtFrame? get value => switch (this) {
    ProtocolDecodeSuccess(:final frame) => frame,
    ProtocolDecodeFailure() => null,
  };

  EvtFailure? get failure => switch (this) {
    ProtocolDecodeSuccess() => null,
    ProtocolDecodeFailure(:final failure) => failure,
  };
}

class ProtocolDecodeSuccess extends ProtocolDecodeResult {
  const ProtocolDecodeSuccess(this.frame);

  final EvtFrame frame;
}

class ProtocolDecodeFailure extends ProtocolDecodeResult {
  const ProtocolDecodeFailure(this.failure);

  @override
  final EvtFailure failure;
}
