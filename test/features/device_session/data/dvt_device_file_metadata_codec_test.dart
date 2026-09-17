import 'dart:typed_data';

import 'package:aipin/core/protocol/evt_frame.dart';
import 'package:aipin/features/device_session/data/device_protocol_repository.dart';
import 'package:aipin/features/device_session/domain/device_file.dart';
import 'package:aipin/features/device_session/domain/dvt_device_file_metadata_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

const _nameSlot = <int>[
  0x36,
  0x61,
  0x37,
  0x62,
  0x65,
  0x37,
  0x30,
  0x34,
  0x5f,
  0x30,
  0x30,
  0x31,
  0x2e,
  0x6f,
  0x67,
  0x67,
  0x00,
];

void main() {
  test('encodes the exact V1.6 GET_META and ARCHIVE_CONFIRM payloads', () {
    expect(
      DeviceProtocolRepository.encodeDvtReadFileMetadataContent(_nameSlot),
      <int>[0x01, 0x11, ..._nameSlot],
    );
    expect(
      DeviceProtocolRepository.encodeDvtArchiveConfirmationContent(
        const DvtDeviceArchiveConfirmation(
          nameSlot: _nameSlot,
          fileSize: 8192,
          crc32: 0xCBF43926,
        ),
      ),
      <int>[
        0x02,
        0x1A,
        ..._nameSlot,
        0x00,
        0x20,
        0x00,
        0x00,
        0x26,
        0x39,
        0xF4,
        0xCB,
        0x01,
      ],
    );
  });

  test('decodes the V1.6 41-byte GET_META payload without DurationS', () {
    final metadata = DeviceProtocolRepository.decodeDvtFileMetadata(
      _frame(0xA6, <int>[
        0x01,
        0x00,
        0x29,
        ..._nameSlot,
        0x00,
        0x09,
        0x7D,
        0x6A,
        0x80,
        0x70,
        0x60,
        0x50,
        0x00,
        0x00,
        0x01,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x20,
        0x00,
        0x00,
        0x26,
        0x39,
        0xF4,
        0xCB,
        0x01,
      ]),
    );

    expect(metadata.name, '6a7be704_001.ogg');
    expect(metadata.nameSlot, _nameSlot);
    expect(metadata.startUtc, DateTime.utc(2026, 8, 13));
    expect(metadata.recordingSessionId, 0x50607080);
    expect(metadata.segmentIndex, 0);
    expect(metadata.clockQuality, 1);
    expect(metadata.utcCorrectionMilliseconds, 0);
    expect(metadata.fileSize, 8192);
    expect(metadata.crc32, 0xCBF43926);
    expect(metadata.state, DvtDeviceFileState.ready);
  });

  test('rejects the retired 45-byte V1.5 GET_META data layout', () {
    final v15Data = <int>[
      ..._nameSlot,
      0,
      0,
      0,
      0,
      // Retired DurationS; a V1.6 decoder must not shift later fields.
      5,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      1,
    ];
    expect(v15Data, hasLength(45));

    expect(
      () => DeviceProtocolRepository.decodeDvtFileMetadata(
        _frame(0xA6, <int>[0x01, 0x00, 45, ...v15Data]),
      ),
      throwsFormatException,
    );
  });

  test('accepts only DELETE or RECLAIMABLE archive terminal responses', () {
    final deleted = DeviceProtocolRepository.decodeDvtArchiveConfirmation(
      _frame(0xA6, const <int>[0x02, 0x00, 0x01, 0x06]),
    );
    final reclaimable = DeviceProtocolRepository.decodeDvtArchiveConfirmation(
      _frame(0xA6, const <int>[0x02, 0x00, 0x01, 0x04]),
    );

    expect(deleted.deviceDeleted, isTrue);
    expect(reclaimable.retainedForRecovery, isTrue);
    expect(
      () => DeviceProtocolRepository.decodeDvtArchiveConfirmation(
        _frame(0xA6, const <int>[0x02, 0x00, 0x01, 0x03]),
      ),
      throwsFormatException,
    );
  });

  test('rejects a failed 0x26 response before parsing response data', () {
    expect(
      () => DeviceProtocolRepository.decodeDvtFileMetadata(
        _frame(0xA6, const <int>[0x01, 0x05, 0x00]),
      ),
      throwsFormatException,
    );
  });
}

EvtFrame _frame(int command, List<int> content) =>
    EvtFrame(command: command, content: Uint8List.fromList(content));
