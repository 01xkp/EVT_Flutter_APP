import 'dart:typed_data';

import 'package:aipin/core/protocol/crc32.dart';

class WqotaDeviceIdentity {
  const WqotaDeviceIdentity(this.vendorId, this.productId);

  final int vendorId;
  final int productId;
}

class FirmwarePackage {
  FirmwarePackage({
    required this.vendorId,
    required this.productId,
    required this.version,
    required this.expectedBusinessVersion,
    required Uint8List payload,
    required this.expectedPayloadCrc32,
    required List<int> wqotaRequestPrefixFlags,
    required List<int> wqotaResponsePrefixFlags,
  }) : payload = Uint8List.fromList(payload),
       wqotaRequestPrefixFlags = List<int>.unmodifiable(
         wqotaRequestPrefixFlags,
       ),
       wqotaResponsePrefixFlags = List<int>.unmodifiable(
         wqotaResponsePrefixFlags,
       );

  final int vendorId;
  final int productId;
  final int version;
  final String expectedBusinessVersion;
  final Uint8List payload;
  final int expectedPayloadCrc32;
  final List<int> wqotaRequestPrefixFlags;
  final List<int> wqotaResponsePrefixFlags;

  void validateFor(WqotaDeviceIdentity device) {
    if (vendorId < 0 ||
        vendorId > 0xFFFF ||
        productId < 0 ||
        productId > 0xFFFF ||
        version < 0 ||
        version > 0xFFFF) {
      throw const FirmwarePackageValidationException('固件包镜像头字段无效。');
    }
    if (payload.isEmpty) {
      throw const FirmwarePackageValidationException('固件包不包含镜像数据。');
    }
    if (expectedBusinessVersion.trim().isEmpty) {
      throw const FirmwarePackageValidationException('固件包未声明升级后的设备版本。');
    }
    if (expectedPayloadCrc32 < 0 || expectedPayloadCrc32 > 0xFFFFFFFF) {
      throw const FirmwarePackageValidationException('固件包 CRC32 字段无效。');
    }
    if (wqotaRequestPrefixFlags.length != 4 ||
        wqotaResponsePrefixFlags.length != 4) {
      throw const FirmwarePackageValidationException('未配置目标固件的 WQOTA 请求和响应前缀。');
    }
    if ((wqotaRequestPrefixFlags[3] & 0x80) == 0 ||
        (wqotaResponsePrefixFlags[3] & 0x80) != 0) {
      throw const FirmwarePackageValidationException('WQOTA 请求和响应标志不符合协议。');
    }
    if (vendorId != device.vendorId || productId != device.productId) {
      throw const FirmwarePackageValidationException('固件包与当前设备 VID/PID 不匹配。');
    }
    if (Crc32IsoHdlc.calculate(payload) != expectedPayloadCrc32) {
      throw const FirmwarePackageValidationException('固件包镜像 CRC32 校验失败。');
    }
  }

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

  Uint8List get image => Uint8List.fromList(<int>[...imageHeader, ...payload]);
}

class FirmwarePackageValidationException implements Exception {
  const FirmwarePackageValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}
