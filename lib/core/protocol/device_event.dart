import 'dart:typed_data';

import 'package:evt_ble_app/core/protocol/evt_frame.dart';

enum DeviceEventKind {
  deviceInfo,
  storageUpdated,
  statusChanged,
  recordingStarted,
  silenceEnded,
  audioReceived,
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
      kind: _kindFor(frame.command),
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

  static DeviceEventKind _kindFor(int command) => switch (command) {
    0x01 || 0x81 => DeviceEventKind.deviceInfo,
    0x05 || 0x85 => DeviceEventKind.storageUpdated,
    0x06 || 0x86 => DeviceEventKind.statusChanged,
    0x07 => DeviceEventKind.recordingStarted,
    0x87 => DeviceEventKind.silenceEnded,
    0x08 => DeviceEventKind.audioReceived,
    0x09 || 0x89 => DeviceEventKind.authenticationUpdated,
    0x11 || 0x91 => DeviceEventKind.batteryChanged,
    0x21 || 0xA1 => DeviceEventKind.fileCountUpdated,
    0x22 || 0xA2 => DeviceEventKind.fileListUpdated,
    0x23 || 0xA3 => DeviceEventKind.fileDataReceived,
    _ => DeviceEventKind.unknown,
  };
}
