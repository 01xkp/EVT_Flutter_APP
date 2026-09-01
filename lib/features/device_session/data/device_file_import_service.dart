import 'dart:async';
import 'package:aipin/features/device_session/domain/device_file.dart';
import 'package:aipin/features/device_session/domain/archive_gateway.dart';
import 'package:aipin/features/device_session/domain/device_file_download_checkpoint.dart';
import 'package:aipin/features/device_session/domain/device_file_download_checkpoint_repository.dart';
import 'package:aipin/features/device_session/domain/device_file_gateway.dart';
import 'package:aipin/features/local_recording/domain/local_recording.dart';
import 'package:aipin/features/local_recording/domain/local_recording_repository.dart';
import 'package:aipin/features/local_recording/domain/recording_file_store.dart';

class DeviceFileImportProgress {
  const DeviceFileImportProgress({required this.received, required this.total});

  final int received;
  final int total;

  double get fraction => total <= 0 ? 0 : (received / total).clamp(0, 1);
}

class DeviceFileImportService {
  DeviceFileImportService({
    required this.deviceId,
    required this.gateway,
    required this.archive,
    required this.files,
    required this.checkpoints,
    required this.recordings,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final String deviceId;
  final DeviceFileGateway gateway;
  final ArchiveGateway archive;
  final RecordingFileStore files;
  final DeviceFileDownloadCheckpointRepository checkpoints;
  final LocalRecordingRepository recordings;
  final DateTime Function() _now;

  Future<LocalRecording> import(
    DeviceFile file, {
    void Function(DeviceFileImportProgress progress)? onProgress,
  }) async {
    final metadata = await gateway.readFileMetadata(file.nameSlot);
    if (metadata.length <= 0 || metadata.length != file.length) {
      throw const FormatException('设备文件大小与元数据不一致。');
    }
    final extension = _audioExtension(metadata.name);
    var checkpoint = await checkpoints.find(
      deviceId: deviceId,
      nameSlot: metadata.nameSlot,
    );
    if (checkpoint != null &&
        !checkpoint.matches(length: metadata.length, crc32: metadata.crc32)) {
      await _discardPartial(checkpoint, extension);
      checkpoint = null;
    }
    final id =
        checkpoint?.recordingId ?? 'device-${_now().microsecondsSinceEpoch}';
    final pending = await files.createPending(id: id, extension: extension);
    var received = await files.pendingLength(pending);
    if (received > metadata.length) {
      if (checkpoint != null) {
        await _discardPartial(checkpoint, extension);
      } else {
        await files.discard(pending);
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
          recordingId: id,
          expectedLength: metadata.length,
          expectedCrc32: metadata.crc32,
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

    final checksum = _Crc32Accumulator();
    await for (final chunk in files.readPending(pending)) {
      checksum.add(chunk);
    }
    var requestOffset = received;
    var chunks = 0;

    try {
      onProgress?.call(
        DeviceFileImportProgress(received: received, total: metadata.length),
      );
      while (received < metadata.length) {
        final chunk = await gateway.readFileChunk(
          nameSlot: metadata.nameSlot,
          startOffset: requestOffset,
          chunkSize: 0,
        );
        if (chunk.isEmpty) {
          throw const FormatException('设备文件在完整接收前结束。');
        }
        await files.append(pending, chunk);
        checksum.add(chunk);
        received += chunk.length;
        if (received > metadata.length) {
          throw const FormatException('设备文件数据超出元数据长度。');
        }
        requestOffset = received;
        chunks += 1;
        activeCheckpoint = activeCheckpoint.copyWith(
          receivedBytes: received,
          updatedAt: _now(),
        );
        await checkpoints.save(activeCheckpoint);
        onProgress?.call(
          DeviceFileImportProgress(received: received, total: metadata.length),
        );
      }
      if (chunks == 0 && received == 0 || received != metadata.length) {
        throw const FormatException('设备文件数据为空。');
      }
      final imported = await files.finalize(pending);
      if (imported.sizeBytes != metadata.length ||
          checksum.value != metadata.crc32) {
        await files.delete(imported.relativePath);
        throw const FormatException('设备文件 CRC 校验失败。');
      }
      final recording = LocalRecording.saved(
        id: id,
        title: metadata.name,
        relativePath: imported.relativePath,
        createdAt: metadata.startUtc,
        completedAt: _now(),
        duration: Duration(seconds: metadata.durationSeconds),
        sizeBytes: imported.sizeBytes,
      );
      await recordings.save(recording);
      await archive.archive(
        DeviceArchiveRequest(
          deviceId: deviceId,
          metadata: metadata,
          absolutePath: imported.absolutePath,
          sizeBytes: imported.sizeBytes,
          crc32: checksum.value,
        ),
      );
      final archiveState = await gateway.confirmArchive(
        nameSlot: metadata.nameSlot,
        fileSize: imported.sizeBytes,
        crc32: checksum.value,
      );
      if (archiveState != 3 && archiveState != 4) {
        throw StateError('设备未确认文件归档。');
      }
      await checkpoints.remove(activeCheckpoint.id);
      return recording;
    } on FormatException {
      await _discardPartial(activeCheckpoint, extension);
      rethrow;
    }
  }

  Future<void> _discardPartial(
    DeviceFileDownloadCheckpoint checkpoint,
    String extension,
  ) async {
    try {
      final pending = await files.createPending(
        id: checkpoint.recordingId,
        extension: extension,
      );
      await files.discard(pending);
    } finally {
      await checkpoints.remove(checkpoint.id);
    }
  }

  String _audioExtension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 1 || dot == fileName.length - 1) {
      throw const FormatException('设备录音文件格式无效。');
    }
    final extension = fileName.substring(dot).toLowerCase();
    if (extension != '.m4a' && extension != '.ogg') {
      throw const FormatException('设备录音文件格式暂不支持。');
    }
    return extension;
  }
}

class _Crc32Accumulator {
  static const _polynomial = 0xEDB88320;
  var _crc = 0xFFFFFFFF;

  void add(Iterable<int> bytes) {
    for (final byte in bytes) {
      _crc ^= byte & 0xFF;
      for (var bit = 0; bit < 8; bit += 1) {
        _crc = (_crc & 1) == 1 ? (_crc >> 1) ^ _polynomial : _crc >> 1;
      }
    }
  }

  int get value => (_crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
