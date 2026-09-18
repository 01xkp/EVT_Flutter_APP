import 'dart:convert';
import 'dart:io';

import 'package:aipin/features/device_logs/data/https_app_log_upload_port.dart';
import 'package:aipin/features/device_logs/domain/app_log_upload_port.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('evt-log-upload-');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('uploads a trusted log snapshot using the diagnostic log API', () async {
    final source = File(
      '${root.path}${Platform.pathSeparator}aipin-2026-09-17-10-30-00.log',
    );
    await source.writeAsString(
      '2026-09-17T10:30:00Z | INFO | BLE | connected\n',
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/api/v1/diagnostic-logs');
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer upload-token',
      );
      expect(request.headers.contentType?.mimeType, 'multipart/form-data');
      final body = await utf8.decodeStream(request);
      expect(body, contains('name="app_id"\r\n\r\naipin_evt'));
      expect(body, contains('name="app_version"\r\n\r\n0.0.4+5'));
      expect(body, contains('name="platform"\r\n\r\nandroid'));
      expect(
        body,
        contains('name="uploaded_at"\r\n\r\n2026-09-17T10:30:00.000Z'),
      );
      expect(
        body,
        contains('name="file"; filename="aipin-2026-09-17-10-30-00.log"'),
      );
      expect(body, contains('abcdef12'));
      expect(body, contains('connected'));
      request.response
        ..statusCode = HttpStatus.created
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(<String, Object?>{
            'id': 'log_01J',
            'status': 'stored',
            'received_at': '2026-09-17T10:30:01Z',
            'bytes': 53,
            'sha256': 'abc123',
          }),
        );
      await request.response.close();
    });

    final receipt = await _gateway(server).upload(snapshotPath: source.path);

    expect(receipt.bytes, 53);
  });

  test(
    'maps server authentication failures without exposing response details',
    () async {
      final source = File(
        '${root.path}${Platform.pathSeparator}aipin-2026-09-17-10-30-00.log',
      );
      await source.writeAsString('sanitized log');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        request.response
          ..statusCode = HttpStatus.unauthorized
          ..headers.contentType = ContentType.json
          ..write('{"code":"unauthorized","message":"token details"}');
        await request.response.close();
      });

      await expectLater(
        _gateway(server).upload(snapshotPath: source.path),
        throwsA(
          isA<AppLogUploadFailure>().having(
            (failure) => failure.code,
            'code',
            AppLogUploadFailureCode.authentication,
          ),
        ),
      );
    },
  );

  test('does not treat a quarantined receipt as a successful upload', () async {
    final source = File(
      '${root.path}${Platform.pathSeparator}aipin-2026-09-17-10-30-00.log',
    );
    await source.writeAsString('sanitized log');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.created
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(<String, Object?>{
            'id': 'log_01J',
            'status': 'quarantined',
            'received_at': '2026-09-17T10:30:01Z',
            'bytes': 13,
            'sha256': 'abc123',
          }),
        );
      await request.response.close();
    });

    await expectLater(
      _gateway(server).upload(snapshotPath: source.path),
      throwsA(
        isA<AppLogUploadFailure>().having(
          (failure) => failure.code,
          'code',
          AppLogUploadFailureCode.remoteRejected,
        ),
      ),
    );
  });

  test('rejects a snapshot that the app log store did not create', () async {
    final source = File(
      '${root.path}${Platform.pathSeparator}aipin-2026-09-17-10-30-00.log',
    );
    await source.writeAsString('sanitized log');

    await expectLater(
      HttpsAppLogUploadPort(
        configuration: const HttpsLogUploadConfiguration(
          baseUrl: 'https://log.moreuos.com',
          accessToken: 'upload-token',
          appId: 'aipin_evt',
          appVersion: '0.0.4+5',
        ),
        snapshotValidator: const _SnapshotValidator(trusted: false),
      ).upload(snapshotPath: source.path),
      throwsA(
        isA<AppLogUploadFailure>().having(
          (failure) => failure.code,
          'code',
          AppLogUploadFailureCode.invalidSnapshot,
        ),
      ),
    );
  });
}

HttpsAppLogUploadPort _gateway(HttpServer server) => HttpsAppLogUploadPort(
  configuration: HttpsLogUploadConfiguration(
    baseUrl: 'http://${server.address.address}:${server.port}',
    accessToken: 'upload-token',
    appId: 'aipin_evt',
    appVersion: '0.0.4+5',
  ),
  snapshotValidator: const _SnapshotValidator(),
  allowInsecureHttpForTesting: true,
  now: () => DateTime.utc(2026, 9, 17, 10, 30),
  platform: () => 'android',
  requestIdGenerator: () => 'abcdef12',
);

class _SnapshotValidator implements AppLogUploadSnapshotValidator {
  const _SnapshotValidator({this.trusted = true});

  final bool trusted;

  @override
  Future<bool> isTrustedSnapshot(String snapshotPath) async => trusted;
}
