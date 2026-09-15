import 'dart:typed_data';

class EvtFrame {
  EvtFrame({
    required this.command,
    required Uint8List content,
    Uint8List? rawBytes,
  }) : content = Uint8List.fromList(content),
       rawBytes = rawBytes == null ? null : Uint8List.fromList(rawBytes);

  final int command;
  final Uint8List content;

  /// The exact bytes accepted by the protocol decoder, when this frame came
  /// from a wire payload. Frames assembled directly by tests or callers may
  /// leave this null. Keeping the original value lets diagnostics and file
  /// import preserve the device response byte-for-byte instead of re-encoding
  /// a semantically equivalent frame.
  final Uint8List? rawBytes;
}
