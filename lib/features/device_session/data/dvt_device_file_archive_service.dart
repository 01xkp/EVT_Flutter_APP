import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/features/device_session/data/io_dvt_local_file_verifier.dart';
import 'package:aipin/features/device_session/domain/device_file_download_checkpoint.dart';
import 'package:aipin/features/device_session/domain/device_file_download_checkpoint_repository.dart';
import 'package:aipin/features/device_session/domain/dvt_archive_gateway.dart';
import 'package:aipin/features/device_session/domain/dvt_device_file_import_result.dart';
import 'package:aipin/features/device_session/domain/dvt_device_file_metadata_gateway.dart';
import 'package:aipin/features/device_session/domain/dvt_pending_archive_manifest.dart';
import 'package:aipin/features/device_session/data/shared_preferences_dvt_pending_archive_manifest_repository.dart';
import 'package:aipin/features/device_session/domain/dvt_pending_archive_manifest_repository.dart';

/// Runs the DVT archive action after [DvtDeviceFileImportService] has already
/// produced a verified local file.
///
/// A cloud gateway failure or non-terminal device response deliberately leaves
/// the `readyForArchive` checkpoint intact. This lets a caller retry without
/// transferring the recording again and, crucially, avoids deleting the
/// device source before durable archive success.
class DvtDeviceFileArchiveService {
  DvtDeviceFileArchiveService({
    required this.metadataGateway,
    required this.archiveGateway,
    required this.checkpoints,
    DvtPendingArchiveManifestRepository? pendingArchives,
    DvtLocalFileVerifier? localFileVerifier,
    SafeAppLogger? logger,
  }) : _pendingArchives =
           pendingArchives ??
           SharedPreferencesDvtPendingArchiveManifestRepository(),
       _localFileVerifier = localFileVerifier ?? const IoDvtLocalFileVerifier(),
       _logger = logger ?? const DebugSafeAppLogger(scope: 'DVT_ARCHIVE');

  final DvtDeviceFileMetadataGateway metadataGateway;
  final DvtArchiveGateway archiveGateway;
  final DeviceFileDownloadCheckpointRepository checkpoints;
  final DvtPendingArchiveManifestRepository _pendingArchives;
  final DvtLocalFileVerifier _localFileVerifier;
  final SafeAppLogger _logger;

  Future<DvtDeviceFileArchiveResult> archiveAndConfirm(
    DvtDeviceFileImportResult imported,
  ) async {
    _validateImportedFile(imported);
    // The importer normally wrote this already. Writing it again makes this
    // boundary safe for an App restart between an older import and its first
    // archive attempt, and prevents any cloud/device dispatch without a
    // durable recovery record.
    await _pendingArchives.save(
      DvtPendingArchiveManifest(
        checkpoint: imported.checkpoint,
        metadata: imported.metadata,
        recording: imported.recording,
        completedRelativePath: imported.completedFile.relativePath,
        validatedSizeBytes: imported.completedFile.sizeBytes,
      ),
    );
    _logInfo(
      'dvt_file_archive_requested',
      stage: 'local_verification',
      fields: {
        'reason': '【DVT文件归档】【开始】重新读取最终本地文件，防止旧校验结果失效',
        'expected_size_bytes': imported.metadata.fileSize,
        'expected_crc32': imported.metadata.crc32,
        'checkpoint_phase': imported.checkpoint.phase.name,
      },
    );
    try {
      final verified = await _localFileVerifier.verify(
        imported.completedFile.absolutePath,
      );
      if (verified.sizeBytes != imported.metadata.fileSize ||
          verified.crc32 != imported.metadata.crc32) {
        throw DvtDeviceFileArchiveException(
          '最终本地文件复验失败：size=${verified.sizeBytes} crc=${verified.crc32}。',
        );
      }
      _logInfo(
        'dvt_file_archive_local_reverified',
        stage: 'local_verification',
        fields: {
          'reason': '【DVT文件归档】【本地复验】大小和 CRC-32 与设备元数据一致',
          'file_size_bytes': verified.sizeBytes,
          'crc32': verified.crc32,
        },
      );
      _logInfo(
        'dvt_file_archive_cloud_started',
        stage: 'cloud_archive',
        fields: {
          'reason': '【DVT文件归档】【云端】开始等待持久化确认，尚未通知设备删除',
          'file_size_bytes': verified.sizeBytes,
          'crc32': verified.crc32,
        },
      );
      await archiveGateway.archive(
        DvtArchiveRequest(
          deviceId: imported.checkpoint.deviceId,
          metadata: imported.metadata,
          absolutePath: imported.completedFile.absolutePath,
          sizeBytes: verified.sizeBytes,
          crc32: verified.crc32,
        ),
      );
      _logInfo(
        'dvt_file_archive_cloud_completed',
        stage: 'cloud_archive',
        fields: {
          'reason': '【DVT文件归档】【云端】已确认持久化，现在请求设备受控删除',
          'file_size_bytes': verified.sizeBytes,
          'crc32': verified.crc32,
        },
      );
      final confirmation = await metadataGateway.confirmDvtArchive(
        confirmation: DvtDeviceArchiveConfirmation(
          nameSlot: imported.metadata.nameSlot,
          fileSize: verified.sizeBytes,
          crc32: verified.crc32,
        ),
      );
      if (!confirmation.isTerminal) {
        throw DvtDeviceFileArchiveException(
          '设备归档确认状态无效：${confirmation.state.name}。',
        );
      }
      // The terminal indication can be lost after the device deletes its own
      // source file. Remove the recovery manifest first, then the checkpoint;
      // if checkpoint cleanup throws, a restart cannot re-send a destructive
      // confirmation from a stale manifest.
      await _pendingArchives.remove(imported.checkpoint.id);
      await checkpoints.remove(imported.checkpoint.id);
      _logInfo(
        'dvt_file_archive_device_completed',
        stage: 'device_confirmation',
        fields: {
          'reason': '【DVT文件归档】【设备】已收到归档最终状态并清除恢复清单和本地检查点',
          'device_file_state': confirmation.state.name,
          'file_size_bytes': verified.sizeBytes,
          'crc32': verified.crc32,
        },
      );
      return DvtDeviceFileArchiveResult(
        imported: imported,
        deviceConfirmation: confirmation,
      );
    } catch (error) {
      _logWarning(
        'dvt_file_archive_pending',
        stage: 'archive',
        fields: {
          'reason': '【DVT文件归档】【待重试】未得到设备终态，保留本地文件和 readyForArchive 检查点',
          'error_type': error.runtimeType.toString(),
        },
      );
      rethrow;
    }
  }

  void _validateImportedFile(DvtDeviceFileImportResult imported) {
    if (imported.checkpoint.phase != DeviceFileDownloadPhase.readyForArchive) {
      throw const DvtDeviceFileArchiveException('本地文件尚未完成 CRC 校验。');
    }
    if (imported.completedFile.sizeBytes != imported.metadata.fileSize ||
        !imported.metadata.matchesArchiveTriple(
          otherNameSlot: imported.checkpoint.nameSlot,
          otherFileSize: imported.checkpoint.expectedLength,
          otherCrc32: imported.checkpoint.expectedCrc32,
        )) {
      throw const DvtDeviceFileArchiveException('本地文件与设备元数据三元组不一致。');
    }
  }

  void _logInfo(
    String event, {
    required String stage,
    Map<String, Object?> fields = const {},
  }) {
    try {
      _logger.info(
        event,
        operation: 'device_archive',
        stage: stage,
        fields: fields,
      );
    } catch (_) {
      // Diagnostics must never advance or roll back an archive operation.
    }
  }

  void _logWarning(
    String event, {
    required String stage,
    Map<String, Object?> fields = const {},
  }) {
    try {
      _logger.warning(
        event,
        operation: 'device_archive',
        stage: stage,
        fields: fields,
      );
    } catch (_) {
      // Diagnostics must never advance or roll back an archive operation.
    }
  }
}

class DvtDeviceFileArchiveException implements Exception {
  const DvtDeviceFileArchiveException(this.message);

  final String message;

  @override
  String toString() => message;
}
