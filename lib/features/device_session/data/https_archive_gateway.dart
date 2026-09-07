import 'dart:convert';
import 'dart:io';

import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/features/device_session/data/https_device_service_support.dart';
import 'package:aipin/features/device_session/domain/archive_gateway.dart';

class HttpsArchiveGateway implements ArchiveGateway {
  HttpsArchiveGateway({
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
  Future<void> archive(DeviceArchiveRequest request) async {
    final source = File(request.absolutePath);
    if (!await source.exists() || await source.length() != request.sizeBytes) {
      throw const DeviceServiceHttpException('待归档的设备音频文件无效。');
    }
    final client = _clientFactory();
    configureDeviceServiceClient(client);
    try {
      final boundary = 'aipin-archive-${DateTime.now().microsecondsSinceEpoch}';
      final httpRequest = await withDeviceServiceTimeout(
        client.postUrl(_endpoint.path('/v1/device-archives')),
        stage: '归档连接',
      );
      httpRequest.headers.contentType = ContentType(
        'multipart',
        'form-data',
        parameters: {'boundary': boundary},
      );
      final fields = <String, String>{
        'device_id': request.deviceId,
        'file_name_slot_base64': base64Encode(request.metadata.nameSlot),
        'file_size_bytes': request.sizeBytes.toString(),
        'file_crc32': request.crc32.toString(),
        'recording_start_utc': request.metadata.startUtc
            .toUtc()
            .toIso8601String(),
        'duration_seconds': request.metadata.durationSeconds.toString(),
        'recording_session_id': request.metadata.recordingSessionId.toString(),
        'segment_index': request.metadata.segmentIndex.toString(),
      };
      for (final entry in fields.entries) {
        httpRequest.add(_fieldBytes(boundary, entry.key, entry.value));
      }
      httpRequest.add(_fileHeader(boundary, _filename(source)));
      await withDeviceServiceTimeout(
        httpRequest.addStream(source.openRead()),
        stage: '归档上传',
      );
      httpRequest.add(utf8.encode('\r\n--$boundary--\r\n'));
      _logger.info(
        'archive_upload_started',
        fields: {'bytes': request.sizeBytes},
      );
      final response = await withDeviceServiceTimeout(
        httpRequest.close(),
        stage: '归档请求',
      );
      final body = await withDeviceServiceTimeout(
        decodeDeviceServiceJson(response),
        stage: '归档响应',
      );
      if (body['durable'] != true) {
        throw const DeviceServiceHttpException('云端未确认设备音频已持久化。');
      }
      _logger.info(
        'archive_upload_succeeded',
        fields: {'bytes': request.sizeBytes},
      );
    } finally {
      client.close(force: true);
    }
  }

  static List<int> _fieldBytes(String boundary, String name, String value) =>
      utf8.encode(
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="$name"\r\n\r\n'
        '$value\r\n',
      );

  static List<int> _fileHeader(String boundary, String filename) => utf8.encode(
    '--$boundary\r\n'
    'Content-Disposition: form-data; name="audio"; filename="$filename"\r\n'
    'Content-Type: application/octet-stream\r\n\r\n',
  );

  static String _filename(File file) => file.uri.pathSegments.last;
}
