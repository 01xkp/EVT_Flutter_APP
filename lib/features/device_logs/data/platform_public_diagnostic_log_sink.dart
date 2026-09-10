import 'dart:io';

import 'package:flutter/services.dart';

import '../domain/public_diagnostic_log_sink.dart';

class PlatformPublicDiagnosticLogSink implements PublicDiagnosticLogSink {
  PlatformPublicDiagnosticLogSink({
    MethodChannel? channel,
    bool Function()? isAndroid,
    bool Function()? isIOS,
  }) : _channel = channel ?? _defaultChannel,
       _isAndroid = isAndroid ?? (() => Platform.isAndroid),
       _isIOS = isIOS ?? (() => Platform.isIOS);

  static const _defaultChannel = MethodChannel('aipin/public_diagnostic_logs');

  final MethodChannel _channel;
  final bool Function() _isAndroid;
  final bool Function() _isIOS;

  @override
  Future<PublicDiagnosticLogMirrorStatus> mirrorCanonicalFile({
    required String sourcePath,
    required String filename,
    bool requestPermission = false,
  }) async {
    if (!_isAndroid() && !_isIOS()) {
      return const PublicDiagnosticLogMirrorStatus.unavailable();
    }
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'mirrorCanonicalLog',
        <String, Object?>{
          'sourcePath': sourcePath,
          'filename': filename,
          'requestPermission': requestPermission,
        },
      );
      if (result == null || result['available'] != true) {
        return PublicDiagnosticLogMirrorStatus.failure(
          result?['failureCode'] as String? ?? 'storage_error',
        );
      }
      final relativePath = result['relativePath'];
      final timestamp = result['lastUpdatedAtEpochMilliseconds'];
      if (relativePath is! String || timestamp is! int) {
        return PublicDiagnosticLogMirrorStatus.failure('invalid_response');
      }
      return PublicDiagnosticLogMirrorStatus.success(
        relativePath: relativePath,
        lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(timestamp),
      );
    } on PlatformException {
      return PublicDiagnosticLogMirrorStatus.failure('channel_error');
    } on MissingPluginException {
      return PublicDiagnosticLogMirrorStatus.failure('channel_unavailable');
    } on Object {
      return PublicDiagnosticLogMirrorStatus.failure('storage_error');
    }
  }
}
