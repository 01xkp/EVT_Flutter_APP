import 'dart:typed_data';

import 'package:aipin/core/protocol/crc32.dart';
import 'package:aipin/core/protocol/wqota_codec.dart';

class WqotaDeviceIdentity {
  const WqotaDeviceIdentity({required this.vendorId, required this.productId});

  final int vendorId;
  final int productId;
}

/// A DVT firmware payload and the target-captured WQOTA wire definition.
///
/// This model intentionally contains no URL or backend contract. A future
/// package source must construct it only from a verified target firmware
/// manifest and an actual request/response packet capture.
class FirmwarePackage {
  FirmwarePackage({
    required this.vendorId,
    required this.productId,
    required this.version,
    required this.expectedBusinessVersion,
    required Uint8List payload,
    required this.expectedPayloadCrc32,
    required this.wireFormat,
    required this.finalVerificationSupported,
  }) : payload = Uint8List.fromList(payload);

  final int vendorId;
  final int productId;
  final int version;
  final String expectedBusinessVersion;
  final Uint8List payload;
  final int expectedPayloadCrc32;
  final WqotaWireFormat wireFormat;

  /// True only when target firmware guarantees E8 state=0 is emitted after,
  /// rather than before, the asynchronous whole-image CRC verification.
  final bool finalVerificationSupported;

  /// Validates the immutable package before either a fresh transfer or a
  /// post-reboot checkpoint verification. Device matching is deliberately
  /// separate because the latter only has the authenticated business channel.
  void validateManifest() {
    if (!_isU16(vendorId) || !_isU16(productId) || !_isU16(version)) {
      throw const FirmwarePackageValidationException(
        'WQOTA image header contains an out-of-range u16 field.',
      );
    }
    if (payload.isEmpty || payload.length > 0xFFFFFFFF) {
      throw const FirmwarePackageValidationException(
        'WQOTA firmware payload length is invalid.',
      );
    }
    if (expectedBusinessVersion.trim().isEmpty) {
      throw const FirmwarePackageValidationException(
        'WQOTA package does not declare the expected business version.',
      );
    }
    if (expectedPayloadCrc32 < 0 || expectedPayloadCrc32 > 0xFFFFFFFF) {
      throw const FirmwarePackageValidationException(
        'WQOTA package CRC32 is invalid.',
      );
    }
    try {
      wireFormat.validate();
    } on FormatException catch (error) {
      throw FirmwarePackageValidationException(
        'WQOTA wire format is invalid: $error',
      );
    }
    if (!finalVerificationSupported) {
      throw const FirmwarePackageValidationException(
        'Target firmware does not provide a verified WQOTA E8 final state.',
      );
    }
    if (Crc32IsoHdlc.calculate(payload) != expectedPayloadCrc32) {
      throw const FirmwarePackageValidationException(
        'WQOTA firmware payload CRC32 does not match the manifest.',
      );
    }
  }

  void validateFor(WqotaDeviceIdentity device) {
    validateManifest();
    if (vendorId != device.vendorId || productId != device.productId) {
      throw const FirmwarePackageValidationException(
        'WQOTA package VID/PID does not match the connected device.',
      );
    }
  }

  /// V1.6 E2 image header. All multi-byte values in WQOTA are big-endian.
  Uint8List get imageHeader => Uint8List.fromList(<int>[
    (vendorId >> 8) & 0xFF,
    vendorId & 0xFF,
    (productId >> 8) & 0xFF,
    productId & 0xFF,
    (version >> 8) & 0xFF,
    version & 0xFF,
    (payload.length >> 24) & 0xFF,
    (payload.length >> 16) & 0xFF,
    (payload.length >> 8) & 0xFF,
    payload.length & 0xFF,
    0,
    0,
    0,
    0,
    (expectedPayloadCrc32 >> 24) & 0xFF,
    (expectedPayloadCrc32 >> 16) & 0xFF,
    (expectedPayloadCrc32 >> 8) & 0xFF,
    expectedPayloadCrc32 & 0xFF,
  ]);

  /// Device offsets include the 18-byte WQOTA header.
  Uint8List get image => Uint8List.fromList(<int>[...imageHeader, ...payload]);

  static bool _isU16(int value) => value >= 0 && value <= 0xFFFF;
}

class FirmwarePackageValidationException implements Exception {
  const FirmwarePackageValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}
