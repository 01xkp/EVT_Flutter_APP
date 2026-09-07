import 'dart:io';

import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/features/device_session/data/https_device_service_support.dart';
import 'package:aipin/features/device_session/domain/firmware_package.dart';
import 'package:aipin/features/device_session/domain/firmware_package_gateway.dart';

class HttpsFirmwarePackageGateway implements FirmwarePackageGateway {
  HttpsFirmwarePackageGateway({
    required String baseUrl,
    this.allowInsecureHttpForTesting = false,
    HttpClient Function()? clientFactory,
    SafeAppLogger? logger,
  }) : _endpoint = DeviceServiceEndpoint(
         baseUrl: baseUrl,
         allowInsecureHttpForTesting: allowInsecureHttpForTesting,
       ),
       _clientFactory = clientFactory ?? HttpClient.new,
       _logger = logger ?? const DebugSafeAppLogger(scope: 'DEVICE_API');

  final bool allowInsecureHttpForTesting;
  final DeviceServiceEndpoint _endpoint;
  final HttpClient Function() _clientFactory;
  final SafeAppLogger _logger;

  @override
  Future<FirmwarePackage> loadForDevice(String deviceId) async {
    final client = _clientFactory();
    configureDeviceServiceClient(client);
    try {
      final manifestUri = _endpoint
          .path('/v1/firmware-packages')
          .replace(queryParameters: {'device_id': deviceId});
      _logger.info('firmware_manifest_started');
      final manifestRequest = await withDeviceServiceTimeout(
        client.getUrl(manifestUri),
        stage: '固件清单连接',
      );
      final manifestResponse = await withDeviceServiceTimeout(
        manifestRequest.close(),
        stage: '固件清单请求',
      );
      final manifest = await withDeviceServiceTimeout(
        decodeDeviceServiceJson(manifestResponse),
        stage: '固件清单响应',
      );
      final payloadUrl = _requiredString(manifest, 'payload_url');
      final payloadRequest = await withDeviceServiceTimeout(
        client.getUrl(_endpoint.external(payloadUrl)),
        stage: '固件下载连接',
      );
      final payloadResponse = await withDeviceServiceTimeout(
        payloadRequest.close(),
        stage: '固件下载请求',
      );
      final payload = await withDeviceServiceTimeout(
        readDeviceServiceBytes(payloadResponse),
        stage: '固件下载响应',
      );
      final package = FirmwarePackage(
        vendorId: _requiredInt(manifest, 'vendor_id'),
        productId: _requiredInt(manifest, 'product_id'),
        version: _requiredInt(manifest, 'image_version'),
        expectedBusinessVersion: _requiredString(
          manifest,
          'expected_business_version',
        ),
        payload: payload,
        expectedPayloadCrc32: _requiredInt(manifest, 'payload_crc32'),
        wqotaRequestPrefixFlags: _requiredByteList(
          manifest,
          'wqota_request_prefix_flags',
        ),
        wqotaResponsePrefixFlags: _requiredByteList(
          manifest,
          'wqota_response_prefix_flags',
        ),
        wqotaFinalVerificationSupported:
            manifest['wqota_final_verification_supported'] == true,
      );
      _logger.info(
        'firmware_manifest_succeeded',
        fields: {'payload_bytes': payload.length},
      );
      return package;
    } finally {
      client.close(force: true);
    }
  }

  static String _requiredString(Map<String, Object?> value, String key) {
    final raw = value[key];
    if (raw is! String || raw.trim().isEmpty) {
      throw DeviceServiceHttpException('固件包清单缺少 $key。');
    }
    return raw.trim();
  }

  static int _requiredInt(Map<String, Object?> value, String key) {
    final raw = value[key];
    if (raw is! int) {
      throw DeviceServiceHttpException('固件包清单的 $key 必须是整数。');
    }
    return raw;
  }

  static List<int> _requiredByteList(Map<String, Object?> value, String key) {
    final raw = value[key];
    if (raw is! List || raw.length != 4 || raw.any((item) => item is! int)) {
      throw DeviceServiceHttpException('固件包清单的 $key 必须是 4 字节数组。');
    }
    final bytes = raw.cast<int>();
    if (bytes.any((item) => item < 0 || item > 0xFF)) {
      throw DeviceServiceHttpException('固件包清单的 $key 包含非法字节。');
    }
    return List<int>.unmodifiable(bytes);
  }
}
