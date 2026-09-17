enum AppLogUploadFailureCode {
  unconfigured,
  noSnapshot,
  invalidSnapshot,
  connection,
  timeout,
  hostKeyMismatch,
  authentication,
  remoteRejected,
  transfer,
}

class AppLogUploadFailure implements Exception {
  const AppLogUploadFailure(this.code);

  final AppLogUploadFailureCode code;

  String get userMessage => switch (code) {
    AppLogUploadFailureCode.unconfigured => '日志上报尚未配置，请联系联调人员。',
    AppLogUploadFailureCode.noSnapshot => '当前没有可上报的日志，请稍后重试。',
    AppLogUploadFailureCode.invalidSnapshot => '日志快照无效，请重新生成后重试。',
    AppLogUploadFailureCode.connection => '无法连接日志服务器，请检查网络后重试。',
    AppLogUploadFailureCode.timeout => '日志上报超时，请稍后重试。',
    AppLogUploadFailureCode.hostKeyMismatch => '日志服务器身份校验失败，请联系联调人员。',
    AppLogUploadFailureCode.authentication => '日志服务器认证失败，请联系联调人员。',
    AppLogUploadFailureCode.remoteRejected => '日志服务器拒绝接收，请联系联调人员。',
    AppLogUploadFailureCode.transfer => '日志上报失败，请重试。',
  };

  @override
  String toString() => 'AppLogUploadFailure(${code.name})';
}

class AppLogUploadReceipt {
  const AppLogUploadReceipt({required this.bytes});

  final int bytes;
}

abstract interface class AppLogUploadSnapshotValidator {
  /// Confirms that a path is a private, transport-safe snapshot owned by the
  /// app log store rather than an arbitrary similarly named file.
  Future<bool> isTrustedSnapshot(String snapshotPath);
}

abstract interface class AppLogUploadPort {
  bool get isConfigured;

  Future<AppLogUploadReceipt> upload({required String snapshotPath});
}
