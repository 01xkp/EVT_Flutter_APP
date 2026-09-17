import 'package:aipin/features/device_session/data/https_dvt_archive_gateway.dart';
import 'package:aipin/features/device_session/domain/device_file.dart';
import 'package:aipin/features/device_session/domain/dvt_archive_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final slot = <int>[...('6a7be704_001.ogg'.codeUnits), 0];
  final metadata = DvtDeviceFileMetadata(
    name: '6a7be704_001.ogg',
    nameSlot: slot,
    startUtc: DateTime.utc(2026),
    recordingSessionId: 123,
    segmentIndex: 1,
    clockQuality: 1,
    utcCorrectionMilliseconds: 0,
    fileSize: 9,
    crc32: 0xCBF43926,
    state: DvtDeviceFileState.ready,
  );
  final request = DvtArchiveRequest(
    deviceId: 'device-a',
    metadata: metadata,
    absolutePath: 'unused',
    sizeBytes: 9,
    crc32: 0xCBF43926,
  );
  Map<String, dynamic> receipt() => {
    'durable': true,
    'archive_id': 'archive-1',
    'device_id': 'device-a',
    'name_slot': slot,
    'file_size': 9,
    'crc32': 0xCBF43926,
  };
  test('accepts durable exact file receipt only', () {
    expect(
      () => HttpsDvtArchiveGateway.validateReceipt(receipt(), request),
      returnsNormally,
    );
  });
  for (final invalid in <String, Object?>{
    'durable': false,
    'archive_id': '',
    'device_id': 'another-device',
    'name_slot': List<int>.filled(17, 0),
    'file_size': 8,
    'crc32': 0,
  }.entries) {
    test('rejects archive receipt with wrong ${invalid.key}', () {
      final value = receipt()..[invalid.key] = invalid.value;
      expect(
        () => HttpsDvtArchiveGateway.validateReceipt(value, request),
        throwsFormatException,
      );
    });
  }
}
