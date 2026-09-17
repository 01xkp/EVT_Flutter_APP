import 'package:aipin/features/device_session/domain/device_file.dart';
import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/features/device_session/data/dvt_crc32.dart';
import 'package:aipin/features/device_session/domain/device_file_download_checkpoint.dart';
import 'package:aipin/features/device_session/domain/device_file_download_checkpoint_repository.dart';
import 'package:aipin/features/device_session/domain/device_file_import_progress.dart';
import 'package:aipin/features/device_session/domain/device_file_transfer_gateway.dart';
import 'package:aipin/features/device_session/domain/dvt_device_file_import_result.dart';
import 'package:aipin/features/device_session/domain/dvt_device_file_metadata_gateway.dart';
import 'package:aipin/features/device_session/data/io_dvt_local_file_verifier.dart';
import 'package:aipin/features/device_session/data/shared_preferences_dvt_pending_archive_manifest_repository.dart';
import 'package:aipin/features/device_session/domain/dvt_archive_gateway.dart';
import 'package:aipin/features/device_session/domain/dvt_pending_archive_manifest.dart';
import 'package:aipin/features/device_session/domain/dvt_pending_archive_manifest_repository.dart';
import 'package:aipin/features/local_recording/domain/local_recording.dart';
import 'package:aipin/features/local_recording/domain/local_recording_repository.dart';
import 'package:aipin/features/local_recording/domain/recording_file_store.dart';

/// DVT local file acquisition only.
///
/// This service reads V1.6 metadata, transfers `0x23 / 0xA3`, verifies the
/// entire CRC-32, and commits a local recording. It deliberately does not
/// upload to cloud storage or send `0x26 / ARCHIVE_CONFIRM`; callers run that
/// separate action through [DvtDeviceFileArchiveService].
class DvtDeviceFileImportService {
  DvtDeviceFileImportService({
    required this.deviceId,
    required this.metadataGateway,
    required this.transferGateway,
    required this.files,
    required this.checkpoints,
    required this.recordings,
    DvtPendingArchiveManifestRepository? pendingArchives,
    DvtLocalFileVerifier? localFileVerifier,
    DateTime Function()? now,
    SafeAppLogger? logger,
  }) : _pendingArchives =
           pendingArchives ??
           SharedPreferencesDvtPendingArchiveManifestRepository(),
       _localFileVerifier = localFileVerifier ?? const IoDvtLocalFileVerifier(),
       _now = now ?? DateTime.now,
       _logger = logger ?? const DebugSafeAppLogger(scope: 'DVT_FILE');

  final String deviceId;
  final DvtDeviceFileMetadataGateway metadataGateway;
  final DeviceFileTransferGateway transferGateway;
  final RecordingFileStore files;
  final DeviceFileDownloadCheckpointRepository checkpoints;
  final LocalRecordingRepository recordings;
  final DvtPendingArchiveManifestRepository _pendingArchives;
  final DvtLocalFileVerifier _localFileVerifier;
  final DateTime Function() _now;
  final SafeAppLogger _logger;

  Future<DvtDeviceFileImportResult> import(
    DeviceFile file, {
    void Function(DeviceFileImportProgress progress)? onProgress,
  }) async {
    _validateListedFile(file);
    _logInfo(
      'dvt_file_import_requested',
      stage: 'metadata',
      fields: {
        'reason': '【DVT文件导入】【开始】请求文件元数据并准备本地校验',
        'listed_size_bytes': file.length,
      },
    );
    final metadata = await metadataGateway.readDvtFileMetadata(
      nameSlot: file.nameSlot,
    );
    _validateMetadata(file, metadata);
    _logInfo(
      'dvt_file_metadata_verified',
      stage: 'metadata',
      fields: {
        'reason': '【DVT文件导入】【元数据】41B 元数据与文件列表已匹配',
        'file_size_bytes': metadata.fileSize,
        'crc32': metadata.crc32,
        'file_state': metadata.state.name,
        'session_id': metadata.recordingSessionId,
        'segment_index': metadata.segmentIndex,
      },
    );
    final extension = _audioExtension(metadata.name);
    var checkpoint = await checkpoints.find(
      deviceId: deviceId,
      nameSlot: metadata.nameSlot,
    );
    if (checkpoint != null &&
        !checkpoint.matches(length: metadata.fileSize, crc32: metadata.crc32)) {
      _logWarning(
        'dvt_file_checkpoint_rejected',
        stage: 'checkpoint',
        fields: {
          'reason': '【DVT文件导入】【检查点】元数据三元组变化，清理旧本地断点',
          'expected_size_bytes': checkpoint.expectedLength,
          'expected_crc32': checkpoint.expectedCrc32,
          'actual_size_bytes': metadata.fileSize,
          'actual_crc32': metadata.crc32,
        },
      );
      await _discardCheckpointFile(checkpoint, extension);
      checkpoint = null;
    }

    final existing = await _recoverCompletedFile(
      checkpoint: checkpoint,
      metadata: metadata,
      extension: extension,
    );
    if (existing != null) {
      await _persistPendingArchive(existing);
      _logInfo(
        'dvt_file_import_local_ready',
        stage: 'checkpoint',
        fields: {
          'reason': '【DVT文件导入】【本地完成】复用已校验文件，等待单独归档动作',
          'file_size_bytes': existing.completedFile.sizeBytes,
          'crc32': existing.metadata.crc32,
        },
      );
      return existing;
    }

    final recordingId =
        checkpoint?.recordingId ?? 'device-${_now().microsecondsSinceEpoch}';
    final pending = await files.createPending(
      id: recordingId,
      extension: extension,
    );
    var received = await files.pendingLength(pending);
    if (received > metadata.fileSize) {
      await files.discard(pending);
      if (checkpoint != null) {
        await checkpoints.remove(checkpoint.id);
      }
      received = 0;
      checkpoint = null;
    }

    var activeCheckpoint =
        checkpoint ??
        DeviceFileDownloadCheckpoint(
          id: DeviceFileDownloadCheckpoint.idFor(
            deviceId: deviceId,
            nameSlot: metadata.nameSlot,
          ),
          deviceId: deviceId,
          nameSlot: List<int>.unmodifiable(metadata.nameSlot),
          recordingId: recordingId,
          expectedLength: metadata.fileSize,
          expectedCrc32: metadata.crc32,
          receivedBytes: received,
          updatedAt: _now(),
        );
    if (activeCheckpoint.receivedBytes != received ||
        activeCheckpoint.phase != DeviceFileDownloadPhase.downloading) {
      activeCheckpoint = activeCheckpoint.copyWith(
        receivedBytes: received,
        updatedAt: _now(),
        phase: DeviceFileDownloadPhase.downloading,
      );
    }
    await checkpoints.save(activeCheckpoint);
    _logInfo(
      'dvt_file_transfer_started',
      stage: 'transfer',
      fields: {
        'reason': '【DVT文件导入】【传输】开始 0x23/A3 连续下载',
        'received_bytes': received,
        'total_bytes': metadata.fileSize,
        'checkpoint_phase': activeCheckpoint.phase.name,
      },
    );

    final checksum = DvtCrc32Accumulator();
    await for (final bytes in files.readPending(pending)) {
      checksum.add(bytes);
    }
    onProgress?.call(
      DeviceFileImportProgress(received: received, total: metadata.fileSize),
    );

    try {
      var receivedTerminal = false;
      await for (final event in transferGateway.downloadEvtFile(
        nameSlot: metadata.nameSlot,
        startOffset: received,
        chunkSize: 0,
        expectedFileLength: metadata.fileSize,
      )) {
        if (event.isTerminal) {
          if (receivedTerminal) {
            throw const DvtDeviceFileImportException('设备重复返回文件结束帧。');
          }
          receivedTerminal = true;
          continue;
        }
        if (receivedTerminal) {
          throw const DvtDeviceFileImportException('设备在文件结束帧后继续返回数据。');
        }
        received += event.bytes.length;
        if (received > metadata.fileSize) {
          throw const DvtDeviceFileIntegrityException('设备文件长度超过元数据声明值。');
        }
        await files.append(pending, event.bytes);
        checksum.add(event.bytes);
        activeCheckpoint = activeCheckpoint.copyWith(
          receivedBytes: received,
          updatedAt: _now(),
        );
        await checkpoints.save(activeCheckpoint);
        _logInfo(
          'dvt_file_transfer_progress',
          stage: 'transfer',
          fields: {
            'reason': '【DVT文件导入】【传输】已写入连续文件数据',
            'received_bytes': received,
            'total_bytes': metadata.fileSize,
            'chunk_bytes': event.bytes.length,
          },
        );
        onProgress?.call(
          DeviceFileImportProgress(
            received: received,
            total: metadata.fileSize,
          ),
        );
      }
      if (!receivedTerminal) {
        throw const DvtDeviceFileImportException('设备未返回文件结束帧。');
      }
      if (received != metadata.fileSize) {
        throw const DvtDeviceFileIntegrityException('设备文件传输未完成。');
      }
      if (checksum.value != metadata.crc32) {
        _logWarning(
          'dvt_file_crc_mismatch',
          stage: 'verification',
          fields: {
            'reason': '【DVT文件导入】【CRC】本地复算失败，不保存文件也不归档',
            'expected_crc32': metadata.crc32,
            'actual_crc32': checksum.value,
          },
        );
        throw const DvtDeviceFileIntegrityException('设备文件 CRC-32 校验失败。');
      }

      final completed = await files.finalize(pending);
      if (completed.sizeBytes != metadata.fileSize) {
        await files.delete(completed.relativePath);
        throw const DvtDeviceFileIntegrityException('本地文件大小与元数据不一致。');
      }
      final recording = _recordingFor(
        id: recordingId,
        metadata: metadata,
        completed: completed,
      );
      await recordings.save(recording);
      final readyCheckpoint = activeCheckpoint.copyWith(
        receivedBytes: received,
        updatedAt: _now(),
        phase: DeviceFileDownloadPhase.readyForArchive,
      );
      activeCheckpoint = readyCheckpoint;
      await checkpoints.save(activeCheckpoint);
      final imported = DvtDeviceFileImportResult(
        recording: recording,
        completedFile: completed,
        metadata: metadata,
        checkpoint: activeCheckpoint,
      );
      // Do not hand a verified file to an archive caller until the recovery
      // manifest is durable. A lost final Indicate may mean the device has
      // already deleted this source file when the App is next launched.
      await _persistPendingArchive(imported);
      _logInfo(
        'dvt_file_import_local_verified',
        stage: 'verification',
        fields: {
          'reason': '【DVT文件导入】【完成】本地文件已复验并保留，尚未执行云端归档',
          'file_size_bytes': completed.sizeBytes,
          'crc32': checksum.value,
          'checkpoint_phase': activeCheckpoint.phase.name,
        },
      );
      return imported;
    } on DvtDeviceFileIntegrityException {
      await files.discard(pending);
      await checkpoints.remove(activeCheckpoint.id);
      _logWarning(
        'dvt_file_import_integrity_failed',
        stage: 'verification',
        fields: {
          'reason': '【DVT文件导入】【失败】完整性校验失败，已清理不可信本地文件和检查点',
          'received_bytes': received,
          'total_bytes': metadata.fileSize,
        },
      );
      rethrow;
    } catch (error) {
      await checkpoints.save(
        activeCheckpoint.copyWith(receivedBytes: received, updatedAt: _now()),
      );
      _logWarning(
        'dvt_file_import_interrupted',
        stage: 'transfer',
        fields: {
          'reason': '【DVT文件导入】【中断】保留连续下载检查点，后续可从当前偏移恢复',
          'received_bytes': received,
          'total_bytes': metadata.fileSize,
          'error_type': error.runtimeType.toString(),
        },
      );
      rethrow;
    }
  }

  /// Restores files whose cloud archive/device confirmation may have completed
  /// while the App was not running. This is intentionally offline: the device
  /// can already have removed its source file after a lost terminal Indicate,
  /// so this method must not issue `GET_META` or start another file transfer.
  Future<List<DvtDeviceFileImportResult>> restoreReadyImports() async {
    final manifests = await _pendingArchives.listForDevice(deviceId);
    final restored = <DvtDeviceFileImportResult>[];
    for (final manifest in manifests) {
      if (!manifest.isReadyForRestore) {
        _logWarning(
          'dvt_file_restore_manifest_rejected',
          stage: 'checkpoint',
          fields: const {'reason': '【DVT文件恢复】【检查点】待归档清单字段不完整，跳过恢复'},
        );
        continue;
      }
      try {
        final checkpoint = await checkpoints.find(
          deviceId: deviceId,
          nameSlot: manifest.metadata.nameSlot,
        );
        if (!_matchesRestorableCheckpoint(manifest, checkpoint)) {
          _logWarning(
            'dvt_file_restore_checkpoint_rejected',
            stage: 'checkpoint',
            fields: const {'reason': '【DVT文件恢复】【检查点】本地检查点与待归档清单不一致，跳过恢复'},
          );
          continue;
        }

        final completed = await files.recoverPartial(
          manifest.completedRelativePath,
        );
        if (completed == null ||
            completed.relativePath != manifest.completedRelativePath ||
            completed.sizeBytes != manifest.validatedSizeBytes) {
          _logWarning(
            'dvt_file_restore_local_file_unavailable',
            stage: 'local_verification',
            fields: const {'reason': '【DVT文件恢复】【本地文件】已校验文件缺失或大小变化，不发送云端或设备确认'},
          );
          continue;
        }
        final verified = await _localFileVerifier.verify(
          completed.absolutePath,
        );
        if (verified.sizeBytes != manifest.validatedSizeBytes ||
            verified.sizeBytes != manifest.metadata.fileSize ||
            verified.crc32 != manifest.metadata.crc32) {
          _logWarning(
            'dvt_file_restore_local_file_rejected',
            stage: 'local_verification',
            fields: const {'reason': '【DVT文件恢复】【CRC】本地文件复验失败，不发送云端或设备确认'},
          );
          continue;
        }
        restored.add(
          DvtDeviceFileImportResult(
            recording: manifest.recording,
            completedFile: completed,
            metadata: manifest.metadata,
            checkpoint: checkpoint!,
          ),
        );
        _logInfo(
          'dvt_file_restore_local_verified',
          stage: 'local_verification',
          fields: {
            'reason': '【DVT文件恢复】【完成】恢复本地已校验文件，等待归档确认重试',
            'file_size_bytes': verified.sizeBytes,
            'crc32': verified.crc32,
          },
        );
      } catch (error) {
        _logWarning(
          'dvt_file_restore_failed',
          stage: 'local_verification',
          fields: {
            'reason': '【DVT文件恢复】【失败】无法重新验证本地文件，不发送云端或设备确认',
            'error_type': error.runtimeType.toString(),
          },
        );
      }
    }
    return List<DvtDeviceFileImportResult>.unmodifiable(restored);
  }

  Future<DvtDeviceFileImportResult?> _recoverCompletedFile({
    required DeviceFileDownloadCheckpoint? checkpoint,
    required DvtDeviceFileMetadata metadata,
    required String extension,
  }) async {
    if (checkpoint == null) {
      return null;
    }
    final relativePath = '${checkpoint.recordingId}$extension';
    if (!await files.exists(relativePath)) {
      return null;
    }
    final completed = await files.recoverPartial(relativePath);
    if (completed == null || completed.sizeBytes != metadata.fileSize) {
      if (completed != null) {
        await files.delete(completed.relativePath);
      }
      await checkpoints.remove(checkpoint.id);
      return null;
    }
    try {
      final verified = await _localFileVerifier.verify(completed.absolutePath);
      if (verified.sizeBytes != metadata.fileSize ||
          verified.crc32 != metadata.crc32) {
        await files.delete(completed.relativePath);
        await checkpoints.remove(checkpoint.id);
        return null;
      }
    } on Object {
      await files.delete(completed.relativePath);
      await checkpoints.remove(checkpoint.id);
      return null;
    }
    final recording = _recordingFor(
      id: checkpoint.recordingId,
      metadata: metadata,
      completed: completed,
    );
    final readyCheckpoint = checkpoint.copyWith(
      receivedBytes: metadata.fileSize,
      updatedAt: _now(),
      phase: DeviceFileDownloadPhase.readyForArchive,
    );
    if (checkpoint.phase != DeviceFileDownloadPhase.readyForArchive) {
      await recordings.save(recording);
    }
    await checkpoints.save(readyCheckpoint);
    return DvtDeviceFileImportResult(
      recording: recording,
      completedFile: completed,
      metadata: metadata,
      checkpoint: readyCheckpoint,
    );
  }

  Future<void> _persistPendingArchive(DvtDeviceFileImportResult imported) {
    return _pendingArchives.save(
      DvtPendingArchiveManifest(
        checkpoint: imported.checkpoint,
        metadata: imported.metadata,
        recording: imported.recording,
        completedRelativePath: imported.completedFile.relativePath,
        validatedSizeBytes: imported.completedFile.sizeBytes,
      ),
    );
  }

  bool _matchesRestorableCheckpoint(
    DvtPendingArchiveManifest manifest,
    DeviceFileDownloadCheckpoint? checkpoint,
  ) {
    if (checkpoint == null ||
        checkpoint.id != manifest.checkpoint.id ||
        checkpoint.deviceId != deviceId ||
        checkpoint.phase != DeviceFileDownloadPhase.readyForArchive ||
        checkpoint.recordingId != manifest.checkpoint.recordingId ||
        checkpoint.expectedLength != manifest.metadata.fileSize ||
        checkpoint.expectedCrc32 != manifest.metadata.crc32 ||
        checkpoint.receivedBytes != manifest.metadata.fileSize) {
      return false;
    }
    return _sameBytes(checkpoint.nameSlot, manifest.metadata.nameSlot);
  }

  Future<void> _discardCheckpointFile(
    DeviceFileDownloadCheckpoint checkpoint,
    String extension,
  ) async {
    final relativePath = '${checkpoint.recordingId}$extension';
    if (await files.exists(relativePath)) {
      await files.delete(relativePath);
    }
    final pending = await files.createPending(
      id: checkpoint.recordingId,
      extension: extension,
    );
    await files.discard(pending);
    await checkpoints.remove(checkpoint.id);
  }

  LocalRecording _recordingFor({
    required String id,
    required DvtDeviceFileMetadata metadata,
    required CompletedRecordingFile completed,
  }) {
    final completedAt = _now();
    return LocalRecording.saved(
      id: id,
      title: metadata.name,
      relativePath: completed.relativePath,
      createdAt: metadata.startUtc,
      completedAt: completedAt,
      // V1.6 0x26 removed DurationS; callers must not infer one from bytes.
      duration: Duration.zero,
      sizeBytes: completed.sizeBytes,
    );
  }

  void _validateListedFile(DeviceFile file) {
    if (file.length <= 0) {
      throw const DvtDeviceFileImportException('设备文件大小无效。');
    }
    if (file.nameSlot.length != 17) {
      throw const DvtDeviceFileImportException('设备文件名槽长度无效。');
    }
  }

  void _validateMetadata(DeviceFile file, DvtDeviceFileMetadata metadata) {
    if (!metadata.matchesListedFile(file)) {
      throw const DvtDeviceFileImportException('设备文件列表与元数据不一致。');
    }
    if (metadata.fileSize <= 0 || metadata.crc32 < 0) {
      throw const DvtDeviceFileImportException('设备文件元数据无效。');
    }
    if (!metadata.state.canDownload) {
      throw DvtDeviceFileImportException(
        '设备文件尚未就绪，当前状态：${metadata.state.name}。',
      );
    }
  }

  String _audioExtension(String name) {
    final normalized = name.trim().toLowerCase();
    if (normalized.endsWith('.ogg')) {
      return '.ogg';
    }
    if (normalized.endsWith('.m4a')) {
      return '.m4a';
    }
    throw const DvtDeviceFileImportException('设备文件格式不支持。');
  }

  void _logInfo(
    String event, {
    required String stage,
    Map<String, Object?> fields = const {},
  }) {
    try {
      _logger.info(
        event,
        operation: 'device_file_import',
        stage: stage,
        fields: fields,
      );
    } catch (_) {
      // Diagnostics must not change file-transfer or checkpoint behavior.
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
        operation: 'device_file_import',
        stage: stage,
        fields: fields,
      );
    } catch (_) {
      // Diagnostics must not change file-transfer or checkpoint behavior.
    }
  }
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

class DvtDeviceFileImportException implements Exception {
  const DvtDeviceFileImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DvtDeviceFileIntegrityException extends DvtDeviceFileImportException {
  const DvtDeviceFileIntegrityException(super.message);
}
