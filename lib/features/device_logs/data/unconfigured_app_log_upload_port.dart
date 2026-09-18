import '../domain/app_log_upload_port.dart';

class UnconfiguredAppLogUploadPort implements AppLogUploadPort {
  const UnconfiguredAppLogUploadPort();

  @override
  bool get isConfigured => false;

  @override
  Future<AppLogUploadReceipt> upload({required String snapshotPath}) {
    throw const AppLogUploadFailure(AppLogUploadFailureCode.unconfigured);
  }
}
