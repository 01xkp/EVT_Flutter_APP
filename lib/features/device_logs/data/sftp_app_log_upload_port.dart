import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import '../domain/app_log_upload_port.dart';

class SftpLogUploadConfiguration {
  const SftpLogUploadConfiguration({
    this.host = '',
    this.port = 0,
    this.username = '',
    this.remoteDirectory = '',
    this.hostKeyFingerprint = '',
    this.privateKeyBase64 = '',
  });

  factory SftpLogUploadConfiguration.fromEnvironment() {
    return SftpLogUploadConfiguration(
      host: const String.fromEnvironment('AIPIN_LOG_UPLOAD_SFTP_HOST'),
      port: const int.fromEnvironment('AIPIN_LOG_UPLOAD_SFTP_PORT'),
      username: const String.fromEnvironment('AIPIN_LOG_UPLOAD_SFTP_USERNAME'),
      remoteDirectory: const String.fromEnvironment(
        'AIPIN_LOG_UPLOAD_SFTP_DIRECTORY',
      ),
      hostKeyFingerprint: const String.fromEnvironment(
        'AIPIN_LOG_UPLOAD_SFTP_HOST_FINGERPRINT',
      ),
      privateKeyBase64: const String.fromEnvironment(
        'AIPIN_LOG_UPLOAD_SFTP_PRIVATE_KEY_BASE64',
      ),
    );
  }

  final String host;
  final int port;
  final String username;
  final String remoteDirectory;
  final String hostKeyFingerprint;
  final String privateKeyBase64;

  bool get isComplete {
    if (!RegExp(r'^[A-Za-z0-9.-]{1,253}$').hasMatch(host) ||
        port < 1 ||
        port > 65535 ||
        !RegExp(r'^[A-Za-z0-9._-]{1,64}$').hasMatch(username) ||
        !_isSafeRemoteDirectory(remoteDirectory) ||
        !RegExp(r'^SHA256:[A-Za-z0-9+/]{43}$').hasMatch(hostKeyFingerprint)) {
      return false;
    }
    try {
      return base64.decode(privateKeyBase64).isNotEmpty;
    } on FormatException {
      return false;
    }
  }

  String get normalizedRemoteDirectory =>
      remoteDirectory.replaceFirst(RegExp(r'/+$'), '');

  String decodePrivateKey() => utf8.decode(base64.decode(privateKeyBase64));

  bool verifiesHostFingerprint(Uint8List fingerprint) {
    final actual = utf8.decode(fingerprint, allowMalformed: false);
    if (actual.length != hostKeyFingerprint.length) return false;
    var difference = 0;
    for (var index = 0; index < actual.length; index += 1) {
      difference |=
          actual.codeUnitAt(index) ^ hostKeyFingerprint.codeUnitAt(index);
    }
    return difference == 0;
  }

  static bool _isSafeRemoteDirectory(String value) {
    if (value == '/' ||
        !value.startsWith('/') ||
        value.contains('\\') ||
        value.contains('//')) {
      return false;
    }
    return value.split('/').every((part) {
      return part.isEmpty ||
          (part != '.' &&
              part != '..' &&
              RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(part));
    });
  }
}

abstract interface class SftpLogUploadSessionFactory {
  Future<SftpLogUploadSession> open(SftpLogUploadConfiguration configuration);
}

abstract interface class SftpLogUploadSession {
  Future<void> upload({
    required String localPath,
    required String temporaryRemotePath,
    required String finalRemotePath,
  });

  Future<void> close();
}

class SftpAppLogUploadPort implements AppLogUploadPort {
  SftpAppLogUploadPort({
    required this.configuration,
    required this.snapshotValidator,
    SftpLogUploadSessionFactory? sessionFactory,
    String Function()? requestId,
    this.closeTimeout = _defaultCloseTimeout,
  }) : _sessionFactory = sessionFactory ?? DartSshSftpLogUploadSessionFactory(),
       _requestId = requestId ?? _newRequestId;

  static const _maxSnapshotBytes = 20 * 1024 * 1024;
  static const _defaultCloseTimeout = Duration(seconds: 5);
  static final _snapshotFilename = RegExp(
    r'^aipin-\d{4}-\d{2}-\d{2}-\d{2}-\d{2}-\d{2}(?:-\d+)?\.log$',
  );

  final SftpLogUploadConfiguration configuration;
  final AppLogUploadSnapshotValidator snapshotValidator;
  final SftpLogUploadSessionFactory _sessionFactory;
  final String Function() _requestId;
  final Duration closeTimeout;

  @override
  bool get isConfigured => kDebugMode && configuration.isComplete;

  @override
  Future<AppLogUploadReceipt> upload({required String snapshotPath}) async {
    if (!isConfigured) {
      throw const AppLogUploadFailure(AppLogUploadFailureCode.unconfigured);
    }

    final localFile = File(snapshotPath);
    final filename = localFile.uri.pathSegments.last;
    if (!_snapshotFilename.hasMatch(filename)) {
      throw const AppLogUploadFailure(AppLogUploadFailureCode.invalidSnapshot);
    }
    if (!await snapshotValidator.isTrustedSnapshot(snapshotPath)) {
      throw const AppLogUploadFailure(AppLogUploadFailureCode.invalidSnapshot);
    }
    final bytes = await _snapshotLength(localFile);
    if (bytes > _maxSnapshotBytes) {
      throw const AppLogUploadFailure(AppLogUploadFailureCode.invalidSnapshot);
    }

    final requestId = _requestId();
    if (!RegExp(r'^[a-f0-9]{8,32}$').hasMatch(requestId)) {
      throw const AppLogUploadFailure(AppLogUploadFailureCode.invalidSnapshot);
    }
    final remoteFilename =
        '${filename.substring(0, filename.length - '.log'.length)}-$requestId.log';
    final finalRemotePath =
        '${configuration.normalizedRemoteDirectory}/$remoteFilename';
    final temporaryRemotePath =
        '${configuration.normalizedRemoteDirectory}/.$remoteFilename.part';

    SftpLogUploadSession? session;
    try {
      session = await _sessionFactory
          .open(configuration)
          .timeout(const Duration(seconds: 20));
      await session
          .upload(
            localPath: snapshotPath,
            temporaryRemotePath: temporaryRemotePath,
            finalRemotePath: finalRemotePath,
          )
          .timeout(const Duration(seconds: 60));
      return AppLogUploadReceipt(bytes: bytes);
    } on AppLogUploadFailure {
      rethrow;
    } on Object catch (error) {
      throw _mapFailure(error);
    } finally {
      if (session != null) {
        try {
          await session.close().timeout(closeTimeout);
        } on Object {
          // Closing a transport is best effort and cannot keep the UI locked.
        }
      }
    }
  }

  Future<int> _snapshotLength(File file) async {
    try {
      if (!await file.exists()) {
        throw const AppLogUploadFailure(AppLogUploadFailureCode.noSnapshot);
      }
      return await file.length();
    } on AppLogUploadFailure {
      rethrow;
    } on FileSystemException {
      throw const AppLogUploadFailure(AppLogUploadFailureCode.noSnapshot);
    }
  }

  AppLogUploadFailure _mapFailure(Object error) {
    if (error is TimeoutException) {
      return const AppLogUploadFailure(AppLogUploadFailureCode.timeout);
    }
    if (error is SSHHandshakeError) {
      return _hasTimeoutMessage(error.message)
          ? const AppLogUploadFailure(AppLogUploadFailureCode.timeout)
          : const AppLogUploadFailure(AppLogUploadFailureCode.connection);
    }
    if (error is SSHHostkeyError) {
      return const AppLogUploadFailure(AppLogUploadFailureCode.hostKeyMismatch);
    }
    if (error is SSHAuthAbortError) {
      final reason = error.reason;
      if (reason != null) {
        return _mapFailure(reason);
      }
      return _hasTimeoutMessage(error.message)
          ? const AppLogUploadFailure(AppLogUploadFailureCode.timeout)
          : const AppLogUploadFailure(AppLogUploadFailureCode.connection);
    }
    if (error is SSHAuthError ||
        error is SSHKeyDecodeError ||
        error is FormatException) {
      return const AppLogUploadFailure(AppLogUploadFailureCode.authentication);
    }
    if (error is SSHSocketError || error is SocketException) {
      return const AppLogUploadFailure(AppLogUploadFailureCode.connection);
    }
    if (error is SftpError) {
      return const AppLogUploadFailure(AppLogUploadFailureCode.remoteRejected);
    }
    if (error is FileSystemException) {
      return const AppLogUploadFailure(AppLogUploadFailureCode.noSnapshot);
    }
    return const AppLogUploadFailure(AppLogUploadFailureCode.transfer);
  }

  bool _hasTimeoutMessage(String message) => RegExp(
    r'\b(?:time\s*out|timed\s*out)\b',
    caseSensitive: false,
  ).hasMatch(message);

  static String _newRequestId() {
    final random = Random.secure();
    final hex = StringBuffer();
    for (var index = 0; index < 16; index += 1) {
      hex.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return hex.toString();
  }
}

class DartSshSftpLogUploadSessionFactory
    implements SftpLogUploadSessionFactory {
  @override
  Future<SftpLogUploadSession> open(
    SftpLogUploadConfiguration configuration,
  ) async {
    final identities = SSHKeyPair.fromPem(configuration.decodePrivateKey());
    if (identities.isEmpty) {
      throw const AppLogUploadFailure(AppLogUploadFailureCode.authentication);
    }
    final socket = await SSHSocket.connect(
      configuration.host,
      configuration.port,
      timeout: const Duration(seconds: 15),
    );
    final client = SSHClient(
      socket,
      username: configuration.username,
      identities: identities,
      onVerifyHostKey: (_, fingerprint) =>
          configuration.verifiesHostFingerprint(fingerprint),
      handshakeTimeout: const Duration(seconds: 15),
      authTimeout: const Duration(seconds: 15),
    );
    return _DartSshSftpLogUploadSession(client);
  }
}

class _DartSshSftpLogUploadSession implements SftpLogUploadSession {
  _DartSshSftpLogUploadSession(this._client);

  final SSHClient _client;
  SftpClient? _sftp;

  @override
  Future<void> upload({
    required String localPath,
    required String temporaryRemotePath,
    required String finalRemotePath,
  }) async {
    final sftp = _sftp ??= await _client.sftp();
    SftpFile? remoteFile;
    try {
      remoteFile = await sftp.open(
        temporaryRemotePath,
        mode:
            SftpFileOpenMode.create |
            SftpFileOpenMode.exclusive |
            SftpFileOpenMode.write,
      );
      await remoteFile
          .write(File(localPath).openRead().map(Uint8List.fromList))
          .done;
      await remoteFile.close();
      remoteFile = null;
      await sftp.rename(temporaryRemotePath, finalRemotePath);
    } on Object {
      if (remoteFile != null) {
        try {
          await remoteFile.close();
        } on Object {
          // The session close below releases any remaining remote handle.
        }
      }
      try {
        await sftp.remove(temporaryRemotePath);
      } on Object {
        // A failed cleanup must not hide the upload failure.
      }
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    final sftp = _sftp;
    if (sftp != null) {
      try {
        await sftp.close();
      } on Object {
        // Always close the SSH transport after a failed SFTP close.
      }
    }
    await _client.close();
  }
}
