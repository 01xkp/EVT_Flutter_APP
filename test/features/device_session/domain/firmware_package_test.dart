import 'dart:typed_data';

import 'package:aipin/features/device_session/domain/firmware_package.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rejects a firmware package whose payload CRC does not match', () {
    final package = FirmwarePackage(
      vendorId: 0x1234,
      productId: 0x5678,
      version: 2,
      expectedBusinessVersion: '1.0.2',
      payload: Uint8List.fromList(const [1, 2, 3]),
      expectedPayloadCrc32: 0,
      wqotaRequestPrefixFlags: const [0x70, 0x07, 0x6E, 0xC1],
      wqotaResponsePrefixFlags: const [0x70, 0x07, 0x6E, 0x01],
    );

    expect(
      () => package.validateFor(const WqotaDeviceIdentity(0x1234, 0x5678)),
      throwsA(isA<FirmwarePackageValidationException>()),
    );
  });

  test('rejects a valid package for a different target device', () {
    final package = FirmwarePackage(
      vendorId: 0x1234,
      productId: 0x5678,
      version: 2,
      expectedBusinessVersion: '1.0.2',
      payload: Uint8List.fromList(const [1, 2, 3]),
      expectedPayloadCrc32: 0x55BC801D,
      wqotaRequestPrefixFlags: const [0x70, 0x07, 0x6E, 0xC1],
      wqotaResponsePrefixFlags: const [0x70, 0x07, 0x6E, 0x01],
    );

    expect(
      () => package.validateFor(const WqotaDeviceIdentity(0x1234, 0x9999)),
      throwsA(isA<FirmwarePackageValidationException>()),
    );
  });

  test('rejects a package without a target-firmware prefix capture', () {
    final package = FirmwarePackage(
      vendorId: 0x1234,
      productId: 0x5678,
      version: 2,
      expectedBusinessVersion: '1.0.2',
      payload: Uint8List.fromList(const [1, 2, 3]),
      expectedPayloadCrc32: 0x55BC801D,
      wqotaRequestPrefixFlags: const [],
      wqotaResponsePrefixFlags: const [0x70, 0x07, 0x6E, 0x01],
    );

    expect(
      () => package.validateFor(const WqotaDeviceIdentity(0x1234, 0x5678)),
      throwsA(isA<FirmwarePackageValidationException>()),
    );
  });

  test('builds the exact 18-byte WQOTA image header after validation', () {
    final package = FirmwarePackage(
      vendorId: 0x1234,
      productId: 0x5678,
      version: 2,
      expectedBusinessVersion: '1.0.2',
      payload: Uint8List.fromList(const [1, 2, 3]),
      expectedPayloadCrc32: 0x55BC801D,
      wqotaRequestPrefixFlags: const [0x70, 0x07, 0x6E, 0xC1],
      wqotaResponsePrefixFlags: const [0x70, 0x07, 0x6E, 0x01],
    );

    package.validateFor(const WqotaDeviceIdentity(0x1234, 0x5678));

    expect(
      package.imageHeader,
      Uint8List.fromList(const [
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
      ]),
    );
  });

  test('rejects a package without an explicit business-version mapping', () {
    final package = FirmwarePackage(
      vendorId: 0x1234,
      productId: 0x5678,
      version: 2,
      expectedBusinessVersion: '  ',
      payload: Uint8List.fromList(const [1, 2, 3]),
      expectedPayloadCrc32: 0x55BC801D,
      wqotaRequestPrefixFlags: const [0x70, 0x07, 0x6E, 0xC1],
      wqotaResponsePrefixFlags: const [0x70, 0x07, 0x6E, 0x01],
    );

    expect(
      () => package.validateFor(const WqotaDeviceIdentity(0x1234, 0x5678)),
      throwsA(isA<FirmwarePackageValidationException>()),
    );
  });
}
