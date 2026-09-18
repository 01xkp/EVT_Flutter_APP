import 'dart:io';

import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/features/device_logs/domain/app_log_store.dart';
import 'package:aipin/features/device_logs/domain/app_log_upload_port.dart';

class AppLogUploadController {
  AppLogUploadController({
    required this.store,
    required this.uploader,
    required this.logger,
  });

  final AppLogStore store;
  final AppLogUploadPort uploader;
  final SafeAppLogger logger;
  Future<AppLogUploadReceipt>? _activeUpload;

  bool get isUploading => _activeUpload != null;

  Future<AppLogUploadReceipt> uploadLatest() {
    final active = _activeUpload;
    if (active != null) {
      return active;
    }
    final upload = _uploadLatest();
    _activeUpload = upload;
    upload.then<void>(
      (_) {
        if (identical(_activeUpload, upload)) _activeUpload = null;
      },
      onError: (Object _, StackTrace _) {
        if (identical(_activeUpload, upload)) _activeUpload = null;
      },
    );
    return upload;
  }

  Future<AppLogUploadReceipt> _uploadLatest() async {
    if (!uploader.isConfigured) {
      logger.warning(
        'app_log_upload_unconfigured',
        stage: 'upload',
        result: 'unconfigured',
      );
      throw const AppLogUploadFailure(AppLogUploadFailureCode.unconfigured);
    }

    logger.info('app_log_upload_requested', stage: 'upload', result: 'pending');
    String? snapshotPath;
    try {
      snapshotPath = await store.createUploadSnapshot();
    } on Object {
      const failure = AppLogUploadFailure(AppLogUploadFailureCode.noSnapshot);
      _logFailure(failure);
      throw failure;
    }
    if (snapshotPath == null) {
      const failure = AppLogUploadFailure(AppLogUploadFailureCode.noSnapshot);
      _logFailure(failure);
      throw failure;
    }

    try {
      final receipt = await uploader.upload(snapshotPath: snapshotPath);
      logger.info(
        'app_log_upload_succeeded',
        stage: 'upload',
        result: 'success',
        fields: {'bytes': receipt.bytes},
      );
      return receipt;
    } on AppLogUploadFailure catch (failure) {
      _logFailure(failure);
      rethrow;
    } on Object {
      const failure = AppLogUploadFailure(AppLogUploadFailureCode.transfer);
      _logFailure(failure);
      throw failure;
    } finally {
      // The store creates these private snapshots, but they are immutable
      // transport inputs rather than user-visible exports. Remove each one
      // after the attempt; cleanup must never mask the upload result/code.
      try {
        await File(snapshotPath).delete();
      } on Object {
        // A failed cleanup is recoverable and must not hide the upload result.
      }
    }
  }

  void _logFailure(AppLogUploadFailure failure) {
    logger.warning(
      'app_log_upload_failed',
      stage: 'upload',
      result: 'failed',
      fields: {'error_code': failure.code.name},
    );
  }
}
