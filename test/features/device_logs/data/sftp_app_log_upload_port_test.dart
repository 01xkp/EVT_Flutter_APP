import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:aipin/features/device_logs/data/sftp_app_log_upload_port.dart';
import 'package:aipin/features/device_logs/domain/app_log_upload_port.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('aipin-sftp-upload-test-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('uses a temporary remote file then finalizes an upload', () async {
    final snapshot = File(
      '${root.path}${Platform.pathSeparator}aipin-2026-09-16-10-00-00.log',
    );
    await snapshot.writeAsString('sanitized log');
    final session = _FakeSftpSession();
    final port = SftpAppLogUploadPort(
      configuration: _configured(),
      snapshotValidator: const _SnapshotValidator(),
      sessionFactory: _FakeSftpSessionFactory(session),
      requestId: () => 'a1b2c3d4',
    );

    final receipt = await port.upload(snapshotPath: snapshot.path);

    expect(receipt.bytes, 13);
    expect(session.localPath, snapshot.path);
    expect(
      session.temporaryRemotePath,
      '/files/.aipin-2026-09-16-10-00-00-a1b2c3d4.log.part',
    );
    expect(
      session.finalRemotePath,
      '/files/aipin-2026-09-16-10-00-00-a1b2c3d4.log',
    );
    expect(session.closed, isTrue);
  });

  test('does not let a stuck session close block a completed upload', () async {
    final snapshot = File(
      '${root.path}${Platform.pathSeparator}aipin-2026-09-16-10-00-00.log',
    );
    await snapshot.writeAsString('sanitized log');
    final session = _FakeSftpSession(blockClose: true);
    final port = SftpAppLogUploadPort(
      configuration: _configured(),
      snapshotValidator: const _SnapshotValidator(),
      sessionFactory: _FakeSftpSessionFactory(session),
      requestId: () => 'a1b2c3d4',
      closeTimeout: const Duration(milliseconds: 1),
    );

    final receipt = await port.upload(snapshotPath: snapshot.path);

    expect(receipt.bytes, 13);
    expect(session.closed, isTrue);
  });

  test(
    'rejects an incomplete configuration before opening an SFTP session',
    () async {
      final factory = _FakeSftpSessionFactory(_FakeSftpSession());
      final port = SftpAppLogUploadPort(
        configuration: const SftpLogUploadConfiguration(),
        snapshotValidator: const _SnapshotValidator(),
        sessionFactory: factory,
      );

      await expectLater(
        port.upload(
          snapshotPath:
              '${root.path}${Platform.pathSeparator}aipin-2026-09-16-10-00-00.log',
        ),
        throwsA(
          isA<AppLogUploadFailure>().having(
            (failure) => failure.code,
            'code',
            AppLogUploadFailureCode.unconfigured,
          ),
        ),
      );
      expect(factory.openCount, 0);
    },
  );

  test('rejects an unexpected local filename before uploading', () async {
    final snapshot = File('${root.path}${Platform.pathSeparator}unsafe.log');
    await snapshot.writeAsString('sanitized log');
    final factory = _FakeSftpSessionFactory(_FakeSftpSession());
    final port = SftpAppLogUploadPort(
      configuration: _configured(),
      snapshotValidator: const _SnapshotValidator(),
      sessionFactory: factory,
    );

    await expectLater(
      port.upload(snapshotPath: snapshot.path),
      throwsA(
        isA<AppLogUploadFailure>().having(
          (failure) => failure.code,
          'code',
          AppLogUploadFailureCode.invalidSnapshot,
        ),
      ),
    );
    expect(factory.openCount, 0);
  });

  test('rejects a snapshot the app log store did not create', () async {
    final snapshot = File(
      '${root.path}${Platform.pathSeparator}aipin-2026-09-16-10-00-00.log',
    );
    await snapshot.writeAsString('untrusted log');
    final factory = _FakeSftpSessionFactory(_FakeSftpSession());
    final port = SftpAppLogUploadPort(
      configuration: _configured(),
      snapshotValidator: const _SnapshotValidator(trusted: false),
      sessionFactory: factory,
    );

    await expectLater(
      port.upload(snapshotPath: snapshot.path),
      throwsA(
        isA<AppLogUploadFailure>().having(
          (failure) => failure.code,
          'code',
          AppLogUploadFailureCode.invalidSnapshot,
        ),
      ),
    );
    expect(factory.openCount, 0);
  });

  test(
    'preserves a host-key rejection wrapped before authentication',
    () async {
      final snapshot = File(
        '${root.path}${Platform.pathSeparator}aipin-2026-09-16-10-00-00.log',
      );
      await snapshot.writeAsString('sanitized log');
      final port = SftpAppLogUploadPort(
        configuration: _configured(),
        snapshotValidator: const _SnapshotValidator(),
        sessionFactory: _FailingSftpSessionFactory(
          SSHAuthAbortError('connection closed', SSHHostkeyError('rejected')),
        ),
      );

      await expectLater(
        port.upload(snapshotPath: snapshot.path),
        throwsA(
          isA<AppLogUploadFailure>().having(
            (failure) => failure.code,
            'code',
            AppLogUploadFailureCode.hostKeyMismatch,
          ),
        ),
      );
    },
  );

  test('preserves a network failure wrapped before authentication', () async {
    final snapshot = File(
      '${root.path}${Platform.pathSeparator}aipin-2026-09-16-10-00-00.log',
    );
    await snapshot.writeAsString('sanitized log');
    final port = SftpAppLogUploadPort(
      configuration: _configured(),
      snapshotValidator: const _SnapshotValidator(),
      sessionFactory: _FailingSftpSessionFactory(
        SSHAuthAbortError(
          'connection closed',
          SSHSocketError(StateError('network unavailable')),
        ),
      ),
    );

    await expectLater(
      port.upload(snapshotPath: snapshot.path),
      throwsA(
        isA<AppLogUploadFailure>().having(
          (failure) => failure.code,
          'code',
          AppLogUploadFailureCode.connection,
        ),
      ),
    );
  });

  test(
    'maps handshake and aborted-authentication timeouts accurately',
    () async {
      final snapshot = File(
        '${root.path}${Platform.pathSeparator}aipin-2026-09-16-10-00-00.log',
      );
      await snapshot.writeAsString('sanitized log');

      Future<void> expectFailure(
        Object error,
        AppLogUploadFailureCode expected,
      ) async {
        final port = SftpAppLogUploadPort(
          configuration: _configured(),
          snapshotValidator: const _SnapshotValidator(),
          sessionFactory: _FailingSftpSessionFactory(error),
        );
        await expectLater(
          port.upload(snapshotPath: snapshot.path),
          throwsA(
            isA<AppLogUploadFailure>().having(
              (failure) => failure.code,
              'code',
              expected,
            ),
          ),
        );
      }

      await expectFailure(
        SSHHandshakeError('handshake timed out after 15 seconds'),
        AppLogUploadFailureCode.timeout,
      );
      await expectFailure(
        SSHAuthAbortError('authentication timed out after 15 seconds'),
        AppLogUploadFailureCode.timeout,
      );
      await expectFailure(
        SSHAuthAbortError('authentication channel closed'),
        AppLogUploadFailureCode.connection,
      );
    },
  );

  test('rejects a remote directory that escapes the configured root', () {
    const configuration = SftpLogUploadConfiguration(
      host: 'logs.example.test',
      port: 2222,
      username: 'log-uploader',
      remoteDirectory: '/files/../other',
      hostKeyFingerprint: 'SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      privateKeyBase64: 'a2V5',
    );

    expect(configuration.isComplete, isFalse);
  });

  test('accepts only the configured OpenSSH host fingerprint', () {
    final configuration = _configured();
    final expected = Uint8List.fromList(
      utf8.encode(configuration.hostKeyFingerprint),
    );
    final unexpected = Uint8List.fromList(
      utf8.encode('SHA256:BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'),
    );

    expect(configuration.verifiesHostFingerprint(expected), isTrue);
    expect(configuration.verifiesHostFingerprint(unexpected), isFalse);
  });
}

SftpLogUploadConfiguration _configured() => const SftpLogUploadConfiguration(
  host: 'logs.example.test',
  port: 2222,
  username: 'log-uploader',
  remoteDirectory: '/files',
  hostKeyFingerprint: 'SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
  privateKeyBase64: 'a2V5',
);

class _FakeSftpSessionFactory implements SftpLogUploadSessionFactory {
  _FakeSftpSessionFactory(this.session);

  final _FakeSftpSession session;
  var openCount = 0;

  @override
  Future<SftpLogUploadSession> open(
    SftpLogUploadConfiguration configuration,
  ) async {
    openCount += 1;
    return session;
  }
}

class _FailingSftpSessionFactory implements SftpLogUploadSessionFactory {
  const _FailingSftpSessionFactory(this.error);

  final Object error;

  @override
  Future<SftpLogUploadSession> open(SftpLogUploadConfiguration configuration) =>
      Future<SftpLogUploadSession>.error(error);
}

class _SnapshotValidator implements AppLogUploadSnapshotValidator {
  const _SnapshotValidator({this.trusted = true});

  final bool trusted;

  @override
  Future<bool> isTrustedSnapshot(String snapshotPath) async => trusted;
}

class _FakeSftpSession implements SftpLogUploadSession {
  _FakeSftpSession({this.blockClose = false});

  final bool blockClose;
  String? localPath;
  String? temporaryRemotePath;
  String? finalRemotePath;
  var closed = false;

  @override
  Future<void> close() {
    closed = true;
    if (blockClose) return Completer<void>().future;
    return Future<void>.value();
  }

  @override
  Future<void> upload({
    required String localPath,
    required String temporaryRemotePath,
    required String finalRemotePath,
  }) async {
    this.localPath = localPath;
    this.temporaryRemotePath = temporaryRemotePath;
    this.finalRemotePath = finalRemotePath;
  }
}
