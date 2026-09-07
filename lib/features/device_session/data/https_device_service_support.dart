import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class DeviceServiceHttpException implements Exception {
  const DeviceServiceHttpException(this.message);

  final String message;

  @override
  String toString() => message;
}

const deviceServiceConnectionTimeout = Duration(seconds: 10);
const deviceServiceOperationTimeout = Duration(seconds: 30);

void configureDeviceServiceClient(HttpClient client) {
  client.connectionTimeout = deviceServiceConnectionTimeout;
}

Future<T> withDeviceServiceTimeout<T>(
  Future<T> future, {
  required String stage,
}) async {
  try {
    return await future.timeout(deviceServiceOperationTimeout);
  } on TimeoutException {
    throw DeviceServiceHttpException('设备服务$stage超时，请稍后重试。');
  }
}

class DeviceServiceEndpoint {
  DeviceServiceEndpoint({
    required String baseUrl,
    required this.allowInsecureHttpForTesting,
  }) : baseUri = _parse(
         baseUrl,
         allowInsecureHttpForTesting: allowInsecureHttpForTesting,
       );

  final Uri baseUri;
  final bool allowInsecureHttpForTesting;

  Uri path(String value) => baseUri.resolve(value);

  Uri external(String value) =>
      _parse(value, allowInsecureHttpForTesting: allowInsecureHttpForTesting);

  static Uri? tryParseConfiguredHttpsUrl(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      return _parse(trimmed, allowInsecureHttpForTesting: false);
    } on ArgumentError {
      return null;
    }
  }

  static Uri _parse(
    String rawValue, {
    required bool allowInsecureHttpForTesting,
  }) {
    final uri = Uri.tryParse(rawValue.trim());
    final secure = uri?.scheme.toLowerCase() == 'https';
    final explicitTestHttp =
        allowInsecureHttpForTesting &&
        uri?.scheme.toLowerCase() == 'http' &&
        _isLoopback(uri?.host);
    if (uri == null || uri.host.isEmpty || (!secure && !explicitTestHttp)) {
      throw ArgumentError.value(rawValue, 'baseUrl', '设备服务必须使用 HTTPS 地址。');
    }
    return uri;
  }

  static bool _isLoopback(String? host) =>
      host == '127.0.0.1' || host == 'localhost' || host == '::1';
}

Future<Map<String, Object?>> decodeDeviceServiceJson(
  HttpClientResponse response,
) async {
  final body = await utf8.decodeStream(response);
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    decoded = null;
  }
  if (response.statusCode < 200 || response.statusCode >= 300) {
    final message = decoded is Map
        ? _nonBlank(decoded['message']) ?? _nonBlank(decoded['detail'])
        : null;
    throw DeviceServiceHttpException(
      message ?? '设备服务请求失败（${response.statusCode}）。',
    );
  }
  if (decoded is! Map) {
    throw const DeviceServiceHttpException('设备服务返回 JSON 格式无效。');
  }
  return decoded.map<String, Object?>((key, value) => MapEntry('$key', value));
}

Future<Uint8List> readDeviceServiceBytes(HttpClientResponse response) async {
  final bytes = <int>[];
  await for (final value in response) {
    bytes.addAll(value);
  }
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw DeviceServiceHttpException('固件包下载失败（${response.statusCode}）。');
  }
  if (bytes.isEmpty) {
    throw const DeviceServiceHttpException('固件包服务返回空镜像。');
  }
  return Uint8List.fromList(bytes);
}

String? _nonBlank(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
