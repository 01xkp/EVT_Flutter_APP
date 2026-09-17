import 'dart:convert';
import 'dart:io';

import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/features/device_session/domain/dvt_archive_gateway.dart';

/// Optional application/backend adapter, NOT an endpoint defined by BLE V1.6.
/// Its response must acknowledge durable storage of the exact immutable triple.
class HttpsDvtArchiveGateway implements DvtArchiveGateway {
  const HttpsDvtArchiveGateway({required this.endpoint, required this.logger});
  final String endpoint;
  final SafeAppLogger logger;

  @override
  Future<void> archive(DvtArchiveRequest request) async {
    final uri = Uri.tryParse(endpoint);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const DvtArchiveGatewayUnavailableException();
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      await _upload(client, uri, request).timeout(const Duration(minutes: 5));
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _upload(
    HttpClient client,
    Uri uri,
    DvtArchiveRequest request,
  ) async {
    logger.info(
      'dvt_archive_upload_started',
      fields: {
        'reason': '【DVT云端归档】开始上传已校验音频，等待服务端可靠保存回执',
        'size': request.sizeBytes,
        'crc32': request.crc32,
      },
    );
    final upload = await client.postUrl(uri);
    upload.followRedirects = false;
    upload.headers.contentType = ContentType.binary;
    upload.headers.set(
      'X-DVT-File-Metadata',
      base64Url.encode(
        utf8.encode(
          jsonEncode({
            'device_id': request.deviceId,
            'name_slot': request.metadata.nameSlot,
            'file_size': request.sizeBytes,
            'crc32': request.crc32,
            'recording_session_id': request.metadata.recordingSessionId,
            'segment_index': request.metadata.segmentIndex,
          }),
        ),
      ),
    );
    upload.contentLength = request.sizeBytes;
    await upload.addStream(File(request.absolutePath).openRead());
    final response = await upload.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('归档服务返回 HTTP ${response.statusCode}，本次未发送设备归档确认。');
    }
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
      if (bytes.length > 64 * 1024) throw const FormatException('归档回执过大。');
    }
    final receipt = jsonDecode(utf8.decode(bytes));
    validateReceipt(receipt, request);
    logger.info(
      'dvt_archive_durable_confirmed',
      fields: {
        'reason': '【DVT云端归档】可靠保存回执与文件键、大小、CRC32 全部匹配，可请求设备归档确认',
        'size': request.sizeBytes,
        'crc32': request.crc32,
      },
    );
  }

  static void validateReceipt(Object? receipt, DvtArchiveRequest request) {
    if (receipt is! Map<String, dynamic> ||
        receipt['durable'] != true ||
        receipt['device_id'] != request.deviceId ||
        jsonEncode(receipt['name_slot']) !=
            jsonEncode(request.metadata.nameSlot) ||
        receipt['file_size'] != request.sizeBytes ||
        receipt['crc32'] != request.crc32 ||
        receipt['archive_id'] is! String ||
        (receipt['archive_id'] as String).trim().isEmpty) {
      throw const FormatException('云端未确认当前文件已可靠保存，禁止删除设备源文件。');
    }
  }
}
