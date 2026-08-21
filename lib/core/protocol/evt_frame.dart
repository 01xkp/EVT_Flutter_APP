import 'dart:typed_data';

class EvtFrame {
  EvtFrame({required this.command, required Uint8List content})
      : content = Uint8List.fromList(content);

  final int command;
  final Uint8List content;
}
