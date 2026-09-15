import 'dart:typed_data';

import 'package:aipin/core/protocol/device_event.dart';
import 'package:aipin/core/protocol/evt_frame.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps EVT 0x87 recording state indications by RecordStatus', () {
    expect(
      DeviceEvent.fromFrame(
        EvtFrame(
          command: 0x87,
          content: Uint8List.fromList([1, 0, 0, 0, 0, 0, 0, 0]),
        ),
        source: 'test',
      ).kind,
      DeviceEventKind.recordingStarted,
    );
    expect(
      DeviceEvent.fromFrame(
        EvtFrame(command: 0x87, content: Uint8List.fromList([0])),
        source: 'test',
      ).kind,
      DeviceEventKind.silenceEnded,
    );
    expect(
      DeviceEvent.fromFrame(
        EvtFrame(
          command: 0x87,
          content: Uint8List.fromList([2, 0, 0, 0, 0, 0, 0, 0]),
        ),
        source: 'test',
      ).kind,
      DeviceEventKind.statusChanged,
    );
  });

  test('only classifies structurally valid V1.6 A3 Notify as file data', () {
    final event = DeviceEvent.fromFrame(
      EvtFrame(command: 0xA3, content: Uint8List(0)),
      source: 'test',
    );

    expect(event.kind, DeviceEventKind.unknown);

    final valid = DeviceEvent.fromFrame(
      EvtFrame(
        command: 0xA3,
        content: Uint8List.fromList([0, 0, 0, 0, 2, 0, 0xAA, 0xBB]),
      ),
      source: 'test',
    );
    expect(valid.kind, DeviceEventKind.fileDataReceived);

    final outbound = DeviceEvent.fromFrame(
      EvtFrame(command: 0x23, content: Uint8List(17)),
      source: 'test',
    );
    expect(outbound.kind, DeviceEventKind.unknown);
  });
}
