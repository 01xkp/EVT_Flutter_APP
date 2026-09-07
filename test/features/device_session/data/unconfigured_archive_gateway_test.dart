import 'package:aipin/features/device_session/data/unconfigured_archive_gateway.dart';
import 'package:aipin/features/device_session/domain/archive_gateway.dart';
import 'package:aipin/features/device_session/domain/device_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'unconfigured archive gateway never reports a durable archive',
    () async {
      const gateway = UnconfiguredArchiveGateway();
      final request = DeviceArchiveRequest(
        deviceId: 'device-1',
        metadata: DeviceFileMetadata(
          name: 'capture.ogg',
          nameSlot: const [1, 0],
          startUtc: DateTime.utc(2026, 1, 1),
          durationSeconds: 5,
          recordingSessionId: 1,
          segmentIndex: 0,
          clockQuality: 1,
          utcCorrectionMilliseconds: 0,
          length: 5,
          crc32: 0x470B99F4,
          state: 1,
        ),
        absolutePath: '/capture.ogg',
        sizeBytes: 5,
        crc32: 0x470B99F4,
      );

      await expectLater(
        gateway.archive(request),
        throwsA(isA<ArchiveGatewayUnavailableException>()),
      );
    },
  );
}
