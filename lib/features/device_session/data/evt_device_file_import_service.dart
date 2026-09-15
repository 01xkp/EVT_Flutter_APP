import 'dart:async';

import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/core/protocol/evt_protocol_contract.dart';
import 'package:aipin/features/device_session/domain/device_file.dart';
import 'package:aipin/features/device_session/domain/device_file_download_checkpoint.dart';
import 'package:aipin/features/device_session/domain/device_file_download_checkpoint_repository.dart';
import 'package:aipin/features/device_session/domain/device_file_import_progress.dart';
import 'package:aipin/features/device_session/domain/device_file_transfer_gateway.dart';
import 'package:aipin/features/local_recording/domain/local_recording.dart';
import 'package:aipin/features/local_recording/domain/local_recording_repository.dart';
import 'package:aipin/features/local_recording/domain/recording_file_store.dart';

/// Imports an EVT device file through the declared 0x23 transfer flow.
///
/// The app verifies transport continuity and final length before retaining the
/// local recording. No undeclared file command is issued by this service.
class EvtDeviceFileImportService {
  EvtDeviceFileImportService({
    required this.deviceId,
    required this.gateway,
    required this.files,
    required this.checkpoints,
    required this.recordings,
    DateTime Function()? now,
    SafeAppLogger? logger,
  }) : _now = now ?? DateTime.now,
       _logger = logger ?? const DebugSafeAppLogger(scope: 'FILE');

  final String deviceId;
  final DeviceFileTransferGateway gateway;
  final RecordingFileStore files;
  final DeviceFileDownloadCheckpointRepository checkpoints;
  final LocalRecordingRepository recordings;
  final DateTime Function() _now;
  final SafeAppLogger _logger;

  Future<LocalRecording> import(
    DeviceFile file, {
    void Function(DeviceFileImportProgress progress)? onProgress,
  }) async {
    final startedAt = DateTime.now();
    try {
      _validateFile(file);
    } catch (error) {
      _logWarning(
        'device_file_import_validation_failed',
        result: 'failed',
        elapsed: DateTime.now().difference(startedAt),
        fields: {
          'total_bytes': file.length,
          'error_type': error.runtimeType.toString(),
        },
      );
      rethrow;
    }
    _logInfo(
      'device_file_import_requested',
      result: 'pending',
      fields: {'total_bytes': file.length},
    );
    final extension = _audioExtension(file.name);
    var checkpoint = await checkpoints.find(
      deviceId: deviceId,
      nameSlot: file.nameSlot,
    );
    if (checkpoint != null &&
        (checkpoint.expectedLength != file.length ||
            checkpoint.expectedCrc32 != 0)) {
      await _discardCheckpoint(checkpoint, extension);
      checkpoint = null;
    }
    _logInfo(
      checkpoint == null
          ? 'device_file_import_new_transfer'
          : 'device_file_import_checkpoint_found',
      result: 'pending',
      elapsed: DateTime.now().difference(startedAt),
      fields: {
        'total_bytes': file.length,
        'offset': checkpoint?.receivedBytes ?? 0,
      },
    );

    final recordingId =
        checkpoint?.recordingId ?? 'device-${_now().microsecondsSinceEpoch}';
    final relativePath = '$recordingId$extension';
    if (checkpoint != null && await files.exists(relativePath)) {
      // A final file can be left behind if the app stops after finalizing it
      // but before it persists the recording row. Never call recoverPartial
      // for a .part file here: that API promotes it to a final file, which
      // would discard the valid resume offset.
      final completed = await files.recoverPartial(relativePath);
      if (completed != null) {
        if (completed.sizeBytes != file.length) {
          await files.delete(completed.relativePath);
          await checkpoints.remove(checkpoint.id);
          checkpoint = null;
        } else {
          final recording = _recordingFor(
            id: recordingId,
            file: file,
            completed: completed,
          );
          await recordings.save(recording);
          await checkpoints.remove(checkpoint.id);
          _logInfo(
            'device_file_import_recovered_complete',
            result: 'success',
            elapsed: DateTime.now().difference(startedAt),
            fields: {'total_bytes': file.length},
          );
          return recording;
        }
      }
    }

    final pending = await files.createPending(
      id: recordingId,
      extension: extension,
    );
    var received = await files.pendingLength(pending);
    if (received > file.length) {
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
            nameSlot: file.nameSlot,
          ),
          deviceId: deviceId,
          nameSlot: List<int>.unmodifiable(file.nameSlot),
          recordingId: recordingId,
          expectedLength: file.length,
          // EVT's file-list and transfer frames do not carry a file checksum.
          expectedCrc32: 0,
          receivedBytes: received,
          updatedAt: _now(),
        );
    if (activeCheckpoint.receivedBytes != received) {
      activeCheckpoint = activeCheckpoint.copyWith(
        receivedBytes: received,
        updatedAt: _now(),
      );
    }
    await checkpoints.save(activeCheckpoint);
    onProgress?.call(
      DeviceFileImportProgress(received: received, total: file.length),
    );

    try {
      var receivedTerminal = false;
      var lastLoggedReceived = received;
      _logInfo(
        'device_file_import_transfer_started',
        result: 'pending',
        elapsed: DateTime.now().difference(startedAt),
        fields: {'total_bytes': file.length, 'offset': received},
      );
      await for (final event in gateway.downloadEvtFile(
        nameSlot: file.nameSlot,
        startOffset: received,
        chunkSize: 0,
        expectedFileLength: file.length,
      )) {
        if (event.isTerminal) {
          if (receivedTerminal) {
            throw const EvtDeviceFileImportException('设备重复返回文件结束帧。');
          }
          receivedTerminal = true;
          continue;
        }
        if (receivedTerminal) {
          throw const EvtDeviceFileImportException('设备在文件结束帧后继续返回数据。');
        }
        received += event.bytes.length;
        if (received > file.length) {
          throw const EvtDeviceFileImportException('设备文件长度超过文件列表声明值。');
        }
        await files.append(pending, event.bytes);
        activeCheckpoint = activeCheckpoint.copyWith(
          receivedBytes: received,
          updatedAt: _now(),
        );
        await checkpoints.save(activeCheckpoint);
        onProgress?.call(
          DeviceFileImportProgress(received: received, total: file.length),
        );
        if (received == file.length || received - lastLoggedReceived >= 65536) {
          lastLoggedReceived = received;
          _logInfo(
            'device_file_import_progress',
            result: 'pending',
            elapsed: DateTime.now().difference(startedAt),
            fields: {
              'total_bytes': file.length,
              'offset': received,
              'chunk_length': event.bytes.length,
              'percent': (received * 100 ~/ file.length),
            },
          );
        }
      }
      if (!receivedTerminal) {
        throw const EvtDeviceFileImportException('设备未返回文件结束帧。');
      }
      if (received != file.length) {
        throw const EvtDeviceFileImportException('设备文件传输未完成。');
      }
      final completed = await files.finalize(pending);
      final recording = _recordingFor(
        id: recordingId,
        file: file,
        completed: completed,
      );
      await recordings.save(recording);
      await checkpoints.remove(activeCheckpoint.id);
      _logInfo(
        'device_file_import_completed',
        result: 'success',
        elapsed: DateTime.now().difference(startedAt),
        fields: {
          'total_bytes': file.length,
          'offset': received,
          'percent': 100,
        },
      );
      return recording;
    } catch (error) {
      await checkpoints.save(
        activeCheckpoint.copyWith(receivedBytes: received, updatedAt: _now()),
      );
      _logWarning(
        'device_file_import_failed',
        result: 'failed',
        elapsed: DateTime.now().difference(startedAt),
        fields: {
          'total_bytes': file.length,
          'offset': received,
          'error_type': error.runtimeType.toString(),
        },
      );
      rethrow;
    }
  }

  Future<void> _discardCheckpoint(
    DeviceFileDownloadCheckpoint checkpoint,
    String extension,
  ) async {
    final relativePath = '${checkpoint.recordingId}$extension';
    final recovered = await files.recoverPartial(relativePath);
    if (recovered != null) {
      await files.delete(recovered.relativePath);
    }
    await checkpoints.remove(checkpoint.id);
  }

  LocalRecording _recordingFor({
    required String id,
    required DeviceFile file,
    required CompletedRecordingFile completed,
  }) {
    final completedAt = _now();
    return LocalRecording.saved(
      id: id,
      title: file.name,
      relativePath: completed.relativePath,
      createdAt: completedAt,
      completedAt: completedAt,
      // EVT 0x22 does not include a duration field.
      duration: Duration.zero,
      sizeBytes: completed.sizeBytes,
    );
  }

  void _validateFile(DeviceFile file) {
    if (file.length <= 0) {
      throw const EvtDeviceFileImportException('设备文件大小无效。');
    }
    if (file.nameSlot.length != 17) {
      throw const EvtDeviceFileImportException('设备文件名槽长度无效。');
    }
    if (!EvtProtocolContract.allowsBusinessCommand(0x23)) {
      throw const EvtDeviceFileImportException('当前阶段不允许导入设备文件。');
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
    throw const EvtDeviceFileImportException('设备文件格式不支持。');
  }

  void _logInfo(
    String event, {
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  }) {
    try {
      _logger.info(
        event,
        operation: 'device_file_import',
        stage: 'import',
        result: result,
        elapsed: elapsed,
        fields: fields,
      );
    } catch (_) {
      // Diagnostics must not interrupt a transfer or checkpoint update.
    }
  }

  void _logWarning(
    String event, {
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  }) {
    try {
      _logger.warning(
        event,
        operation: 'device_file_import',
        stage: 'import',
        result: result,
        elapsed: elapsed,
        fields: fields,
      );
    } catch (_) {
      // Diagnostics must not interrupt a transfer or checkpoint update.
    }
  }
}

class EvtDeviceFileImportException implements Exception {
  const EvtDeviceFileImportException(this.message);

  final String message;

  @override
  String toString() => message;
}
