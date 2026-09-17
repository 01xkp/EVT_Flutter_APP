import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aipin/core/protocol/wqota_codec.dart';
import 'package:aipin/features/device_session/domain/firmware_package.dart';
import 'package:crypto/crypto.dart';

/// DVT package distribution format owned by the App, not a new BLE protocol.
class HttpsFirmwarePackageSource {
  Future<FirmwarePackage> load(String manifestUrl) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      return await _load(
        client,
        manifestUrl,
      ).timeout(const Duration(minutes: 3));
    } finally {
      client.close(force: true);
    }
  }

  Future<FirmwarePackage> _load(HttpClient client, String url) async {
    final bytes = await _get(client, Uri.parse(url), 64 * 1024);
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map<String, dynamic>) {
      throw const FormatException('升级清单必须是 JSON 对象。');
    }
    final payload = await _get(
      client,
      Uri.parse(json['payload_url'] as String),
      32 * 1024 * 1024,
    );
    if (sha256.convert(payload).toString() !=
        (json['payload_sha256'] as String).toLowerCase()) {
      throw const FormatException('固件 SHA256 校验失败。');
    }
    return parseManifest(json, payload);
  }

  static FirmwarePackage parseManifest(
    Map<String, dynamic> json,
    Uint8List payload,
  ) {
    final wire = json['wire_format'] as Map<String, dynamic>;
    final package = FirmwarePackage(
      vendorId: json['vid'] as int,
      productId: json['pid'] as int,
      version: json['version'] as int,
      expectedBusinessVersion: json['expected_business_version'] as String,
      payload: payload,
      expectedPayloadCrc32: json['payload_crc32'] as int,
      wireFormat: WqotaWireFormat.captured(
        captureId: wire['capture_id'] as String,
        requestPrefixFlags: (wire['request_prefix_flags'] as List).cast<int>(),
        responsePrefixFlags: (wire['response_prefix_flags'] as List)
            .cast<int>(),
      ),
      finalVerificationSupported:
          json['e8_final_verification_supported'] == true,
    );
    package.validateFor(
      WqotaDeviceIdentity(
        vendorId: package.vendorId,
        productId: package.productId,
      ),
    );
    return package;
  }

  Future<Uint8List> _get(HttpClient client, Uri uri, int limit) async {
    if (uri.scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const FormatException('固件清单和文件必须使用 HTTPS 地址。');
    }
    final request = await client.getUrl(uri);
    request.followRedirects = false;
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('固件下载失败：HTTP ${response.statusCode}');
    }
    if (response.contentLength > limit) {
      throw const FormatException('固件文件超过 DVT 大小限制。');
    }
    final result = BytesBuilder(copy: false);
    await for (final chunk in response) {
      if (result.length + chunk.length > limit) {
        throw const FormatException('固件文件超过 DVT 大小限制。');
      }
      result.add(chunk);
    }
    return result.takeBytes();
  }
}
