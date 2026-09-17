import 'dart:typed_data';

import 'package:aipin/core/protocol/wqota_codec.dart';
import 'package:aipin/features/device_session/domain/firmware_package.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final format = WqotaWireFormat.captured(
    captureId: 'dvt-v1.6-target-capture-001',
    requestPrefixFlags: const <int>[0x70, 0x07, 0x6E, 0xC1],
    responsePrefixFlags: const <int>[0x70, 0x07, 0x6E, 0x01],
  );

  FirmwarePackage package({bool finalVerificationSupported = true}) =>
      FirmwarePackage(
        vendorId: 0x1234,
        productId: 0x5678,
        version: 2,
        expectedBusinessVersion: '1.0.2',
        payload: Uint8List.fromList(const <int>[1, 2, 3]),
        expectedPayloadCrc32: 0x55BC801D,
        wireFormat: format,
        finalVerificationSupported: finalVerificationSupported,
      );

  test('builds the V1.6 18-byte big-endian E2 header', () {
    final value = package();
    value.validateFor(
      const WqotaDeviceIdentity(vendorId: 0x1234, productId: 0x5678),
    );

    expect(value.imageHeader, <int>[
      0x12,
      0x34,
      0x56,
      0x78,
      0,
      2,
      0,
      0,
      0,
      3,
      0,
      0,
      0,
      0,
      0x55,
      0xBC,
      0x80,
      0x1D,
    ]);
  });

  test('blocks a target without a proven E8 final verification state', () {
    expect(
      () => package(finalVerificationSupported: false).validateFor(
        const WqotaDeviceIdentity(vendorId: 0x1234, productId: 0x5678),
      ),
      throwsA(isA<FirmwarePackageValidationException>()),
    );
  });
}
