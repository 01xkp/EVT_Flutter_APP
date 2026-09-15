import 'dart:typed_data';

import 'package:aipin/core/protocol/evt_frame.dart';

enum DeviceEventKind {
  deviceInfo,
  storageUpdated,
  statusChanged,
  recordingStarted,
  silenceEnded,
  authenticationUpdated,
  batteryChanged,
  fileCountUpdated,
  fileListUpdated,
  fileDataReceived,
  unknown,
}

class DeviceEvent {
  DeviceEvent({
    required this.kind,
    required this.occurredAt,
    required this.source,
    this.command = 0,
    Uint8List? payload,
  }) : payload = Uint8List.fromList(payload ?? Uint8List(0));

  factory DeviceEvent.fromFrame(EvtFrame frame, {required String source}) {
    return DeviceEvent(
      kind: _kindFor(frame),
      occurredAt: DateTime.now(),
      source: source,
      command: frame.command,
      payload: frame.content,
    );
  }

  final DeviceEventKind kind;
  final DateTime occurredAt;
  final String source;
  final int command;
  final Uint8List payload;

  static DeviceEventKind _kindFor(EvtFrame frame) => switch (frame.command) {
    0x01 || 0x81 => DeviceEventKind.deviceInfo,
    0x05 || 0x85 => DeviceEventKind.storageUpdated,
    0x06 || 0x86 => DeviceEventKind.statusChanged,
    0x07 => DeviceEventKind.recordingStarted,
    // V1.6 uses the first byte of a 0x87 indication as RecordStatus:
    // 0 stopped, 1 recording, 2 paused, 0xFF error. Treating every 0x87 as a
    // stop event makes a real start -> stop sequence impossible to verify.
    0x87 => _recordingEventKind(frame.content),
    0x09 || 0x89 => DeviceEventKind.authenticationUpdated,
    0x11 || 0x91 => DeviceEventKind.batteryChanged,
    0x21 || 0xA1 => DeviceEventKind.fileCountUpdated,
    0x22 || 0xA2 => DeviceEventKind.fileListUpdated,
    // V1.6 reserves 0x23 for the outbound request. Only a structurally
    // valid 0xA3 Notify (FileOffset:u32 + DataLength:u16 + payload) is an
    // inbound file-data event; malformed/empty frames stay unknown.
    0xA3 =>
      _isValidFileDataFrame(frame.content)
          ? DeviceEventKind.fileDataReceived
          : DeviceEventKind.unknown,
    _ => DeviceEventKind.unknown,
  };

  static DeviceEventKind _recordingEventKind(Uint8List content) {
    if (content.isEmpty) {
      return DeviceEventKind.unknown;
    }
    return switch (content.first) {
      0 => DeviceEventKind.silenceEnded,
      1 => DeviceEventKind.recordingStarted,
      2 => DeviceEventKind.statusChanged,
      _ => DeviceEventKind.unknown,
    };
  }

  static bool _isValidFileDataFrame(Uint8List content) {
    if (content.length < 6) {
      return false;
    }
    final dataLength = content[4] | (content[5] << 8);
    return dataLength <= 480 && content.length == 6 + dataLength;
  }
}
