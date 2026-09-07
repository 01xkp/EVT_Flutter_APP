import 'dart:typed_data';

import 'package:aipin/features/device_session/data/device_file_import_service.dart';
import 'package:aipin/features/device_session/domain/device_file_download_checkpoint.dart';
import 'package:aipin/features/device_session/domain/device_file_download_checkpoint_repository.dart';
import 'package:aipin/features/device_session/domain/device_file.dart';
import 'package:aipin/features/device_session/domain/device_file_gateway.dart';
import 'package:aipin/features/device_session/domain/archive_gateway.dart';
import 'package:aipin/features/local_recording/domain/local_recording.dart';
import 'package:aipin/features/local_recording/domain/local_recording_repository.dart';
import 'package:aipin/features/local_recording/domain/recording_file_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'downloads contiguous chunks, validates CRC, and saves a local record',
    () async {
      final gateway = _FakeGateway(<int>[1, 2, 3, 4, 5]);
      final files = _ImportFiles();
      final records = _Records();
      final progress = <DeviceFileImportProgress>[];
      final service = DeviceFileImportService(
        deviceId: 'device-1',
        gateway: gateway,
        archive: _ArchiveGateway(),
        files: files,
        checkpoints: _Checkpoints(),
        recordings: records,
        now: () => DateTime.utc(2026, 1, 1),
      );

      final result = await service.import(
        const DeviceFile(name: 'capture.ogg', nameSlot: [1], length: 5),
        onProgress: progress.add,
      );

      expect(result.title, 'capture.ogg');
      expect(result.relativePath, 'device-1767225600000000.ogg');
      expect(records.items.single.sizeBytes, 5);
      expect(gateway.offsets, [0]);
      expect(progress.last.received, 5);
      expect(files.bytes, [1, 2, 3, 4, 5]);
      expect(gateway.confirmationRequests, hasLength(1));
    },
  );

  test('deletes the imported file when CRC does not match', () async {
    final gateway = _FakeGateway(<int>[1, 2, 3, 4, 5], crc32: 0);
    final files = _ImportFiles();
    final service = DeviceFileImportService(
      deviceId: 'device-1',
      gateway: gateway,
      archive: _ArchiveGateway(),
      files: files,
      checkpoints: _Checkpoints(),
      recordings: _Records(),
      now: () => DateTime.utc(2026, 1, 1),
    );

    await expectLater(
      service.import(
        const DeviceFile(name: 'capture.ogg', nameSlot: [1], length: 5),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(files.deleted, ['device-1767225600000000.ogg']);
  });

  test(
    'resumes a device file from its saved offset after a transport interruption',
    () async {
      final gateway = _FakeGateway(<int>[1, 2, 3, 4, 5], failAtOffset: 2);
      final files = _ResumableImportFiles();
      final checkpoints = _Checkpoints();
      final records = _Records();
      final service = DeviceFileImportService(
        deviceId: 'device-1',
        gateway: gateway,
        archive: _ArchiveGateway(),
        files: files,
        checkpoints: checkpoints,
        recordings: records,
        now: () => DateTime.utc(2026, 1, 1),
      );
      const file = DeviceFile(name: 'capture.ogg', nameSlot: [1], length: 5);

      await expectLater(service.import(file), throwsStateError);
      expect(checkpoints.items.single.receivedBytes, 2);
      expect(files.pendingBytes('device-1767225600000000.ogg'), [1, 2]);

      gateway.failAtOffset = null;
      final imported = await service.import(file);

      expect(imported.relativePath, 'device-1767225600000000.ogg');
      expect(gateway.offsets, [0, 2]);
      expect(files.completedBytes, [1, 2, 3, 4, 5]);
      expect(checkpoints.items, isEmpty);
      expect(records.items, hasLength(1));
    },
  );

  test(
    'retains a verified local file and never confirms device archive when durable archive fails',
    () async {
      final gateway = _FakeGateway(<int>[1, 2, 3, 4, 5]);
      final files = _ImportFiles();
      final records = _Records();
      final service = DeviceFileImportService(
        deviceId: 'device-1',
        gateway: gateway,
        archive: _ArchiveGateway(fail: true),
        files: files,
        checkpoints: _Checkpoints(),
        recordings: records,
        now: () => DateTime.utc(2026, 1, 1),
      );

      await expectLater(
        service.import(
          const DeviceFile(name: 'capture.ogg', nameSlot: [1], length: 5),
        ),
        throwsStateError,
      );

      expect(gateway.confirmationRequests, isEmpty);
      expect(files.deleted, isEmpty);
      expect(records.items, hasLength(1));
    },
  );

  test(
    'retries archive from a verified local file without downloading or saving twice',
    () async {
      final gateway = _FakeGateway(<int>[1, 2, 3, 4, 5]);
      final files = _ImportFiles();
      final records = _Records();
      final archive = _ArchiveGateway(fail: true);
      final checkpoints = _Checkpoints();
      final service = DeviceFileImportService(
        deviceId: 'device-1',
        gateway: gateway,
        archive: archive,
        files: files,
        checkpoints: checkpoints,
        recordings: records,
        now: () => DateTime.utc(2026, 1, 1),
      );
      const file = DeviceFile(name: 'capture.ogg', nameSlot: [1], length: 5);

      await expectLater(service.import(file), throwsStateError);
      archive.fail = false;

      await service.import(file);

      expect(gateway.offsets, [0]);
      expect(records.items, hasLength(1));
      expect(gateway.confirmationRequests, hasLength(1));
      expect(checkpoints.items, isEmpty);
    },
  );
}

class _FakeGateway implements DeviceFileGateway {
  _FakeGateway(this.bytes, {int? crc32, this.failAtOffset})
    : _crc32 = crc32 ?? 0x470B99F4;

  final List<int> bytes;
  final int _crc32;
  final offsets = <int>[];
  final confirmationRequests = <({List<int> nameSlot, int size, int crc32})>[];
  int? failAtOffset;

  @override
  Future<DeviceFileMetadata> readFileMetadata(List<int> nameSlot) async {
    return DeviceFileMetadata(
      name: 'capture.ogg',
      nameSlot: nameSlot,
      startUtc: DateTime.utc(2026, 1, 1),
      durationSeconds: 5,
      recordingSessionId: 1,
      segmentIndex: 0,
      clockQuality: 1,
      utcCorrectionMilliseconds: 0,
      length: bytes.length,
      crc32: _crc32,
      state: 1,
    );
  }

  @override
  Stream<Uint8List> downloadFile({
    required List<int> nameSlot,
    int startOffset = 0,
    int chunkSize = 0,
  }) async* {
    offsets.add(startOffset);
    for (var offset = startOffset; offset < bytes.length; offset += 2) {
      if (offset == failAtOffset) {
        throw StateError('connection interrupted');
      }
      yield Uint8List.fromList(
        bytes.sublist(offset, (offset + 2).clamp(0, bytes.length)),
      );
    }
  }

  @override
  Future<Uint8List> readFileChunk({
    required List<int> nameSlot,
    int startOffset = 0,
    int chunkSize = 0,
  }) async {
    offsets.add(startOffset);
    if (startOffset == failAtOffset) {
      throw StateError('connection interrupted');
    }
    if (startOffset >= bytes.length) return Uint8List(0);
    return Uint8List.fromList(
      bytes.sublist(startOffset, (startOffset + 2).clamp(0, bytes.length)),
    );
  }

  @override
  Future<int> confirmArchive({
    required List<int> nameSlot,
    required int fileSize,
    required int crc32,
  }) async {
    confirmationRequests.add((
      nameSlot: nameSlot,
      size: fileSize,
      crc32: crc32,
    ));
    return 4;
  }
}

class _ArchiveGateway implements ArchiveGateway {
  _ArchiveGateway({this.fail = false});

  bool fail;

  @override
  Future<void> archive(DeviceArchiveRequest request) async {
    if (fail) {
      throw StateError('archive unavailable');
    }
  }
}

class _ImportFiles implements RecordingFileStore {
  List<int> bytes = [];
  final deleted = <String>[];
  final _pending = <String, List<int>>{};
  String? _finalizedPath;

  @override
  Future<PendingRecordingFile> createPending({
    required String id,
    String extension = '.m4a',
  }) async {
    return PendingRecordingFile(
      id: id,
      temporaryPath: '/$id.part$extension',
      relativePath: '$id$extension',
    );
  }

  @override
  Future<void> append(PendingRecordingFile pending, List<int> chunk) async {
    _pending.putIfAbsent(pending.relativePath, () => <int>[]).addAll(chunk);
  }

  @override
  Future<int> pendingLength(PendingRecordingFile pending) async =>
      _pending[pending.relativePath]?.length ?? 0;

  @override
  Stream<List<int>> readPending(PendingRecordingFile pending) async* {
    final pendingBytes = _pending[pending.relativePath] ?? const <int>[];
    if (pendingBytes.isNotEmpty) yield List<int>.from(pendingBytes);
  }

  @override
  Future<CompletedRecordingFile> importBytes({
    required String id,
    String extension = '.m4a',
    required Stream<List<int>> chunks,
  }) async {
    final output = <int>[];
    await for (final chunk in chunks) {
      output.addAll(chunk);
    }
    bytes = output;
    return CompletedRecordingFile(
      relativePath: '$id$extension',
      absolutePath: '/$id$extension',
      sizeBytes: output.length,
    );
  }

  @override
  Future<CompletedRecordingFile> finalize(PendingRecordingFile pending) async {
    bytes = List<int>.from(_pending[pending.relativePath] ?? const <int>[]);
    _pending.remove(pending.relativePath);
    _finalizedPath = pending.relativePath;
    return CompletedRecordingFile(
      relativePath: pending.relativePath,
      absolutePath: '/${pending.relativePath}',
      sizeBytes: bytes.length,
    );
  }

  @override
  Future<String> absolutePathFor(String relativePath) async => '/$relativePath';
  @override
  Future<void> discard(PendingRecordingFile pending) async {
    if (_pending.remove(pending.relativePath) != null) {
      deleted.add(pending.relativePath);
    }
  }

  @override
  Future<CompletedRecordingFile?> recoverPartial(String relativePath) async {
    if (_finalizedPath != relativePath || bytes.isEmpty) {
      return null;
    }
    return CompletedRecordingFile(
      relativePath: relativePath,
      absolutePath: '/$relativePath',
      sizeBytes: bytes.length,
    );
  }

  @override
  Future<bool> exists(String relativePath) => throw UnimplementedError();
  @override
  Future<void> delete(String relativePath) async => deleted.add(relativePath);
  @override
  Future<void> cleanupOrphanedTemporaryFiles() async {}
}

class _Records implements LocalRecordingRepository {
  final items = <LocalRecording>[];
  @override
  Future<List<LocalRecording>> all() async => items;
  @override
  Future<void> save(LocalRecording recording) async => items.add(recording);
  @override
  Future<void> update(LocalRecording recording) async {}
  @override
  Future<void> delete(String id) async {}
}

class _ResumableImportFiles implements RecordingFileStore {
  final _pending = <String, List<int>>{};
  List<int> completedBytes = [];

  @override
  Future<PendingRecordingFile> createPending({
    required String id,
    String extension = '.m4a',
  }) async {
    return PendingRecordingFile(
      id: id,
      temporaryPath: '/$id.part$extension',
      relativePath: '$id$extension',
    );
  }

  @override
  Future<int> pendingLength(PendingRecordingFile pending) async =>
      _pending[pending.relativePath]?.length ?? 0;

  @override
  Stream<List<int>> readPending(PendingRecordingFile pending) async* {
    final bytes = _pending[pending.relativePath] ?? const <int>[];
    if (bytes.isNotEmpty) yield List<int>.from(bytes);
  }

  @override
  Future<void> append(PendingRecordingFile pending, List<int> bytes) async {
    _pending.putIfAbsent(pending.relativePath, () => <int>[]).addAll(bytes);
  }

  List<int> pendingBytes(String relativePath) =>
      List<int>.from(_pending[relativePath] ?? const <int>[]);

  @override
  Future<CompletedRecordingFile> finalize(PendingRecordingFile pending) async {
    completedBytes = pendingBytes(pending.relativePath);
    _pending.remove(pending.relativePath);
    return CompletedRecordingFile(
      relativePath: pending.relativePath,
      absolutePath: '/${pending.relativePath}',
      sizeBytes: completedBytes.length,
    );
  }

  @override
  Future<void> discard(PendingRecordingFile pending) async {
    _pending.remove(pending.relativePath);
  }

  @override
  Future<CompletedRecordingFile> importBytes({
    required String id,
    String extension = '.m4a',
    required Stream<List<int>> chunks,
  }) => throw UnimplementedError();
  @override
  Future<String> absolutePathFor(String relativePath) async => '/$relativePath';
  @override
  Future<CompletedRecordingFile?> recoverPartial(String relativePath) =>
      throw UnimplementedError();
  @override
  Future<bool> exists(String relativePath) => throw UnimplementedError();
  @override
  Future<void> delete(String relativePath) async {}
  @override
  Future<void> cleanupOrphanedTemporaryFiles() async {}
}

class _Checkpoints implements DeviceFileDownloadCheckpointRepository {
  final items = <DeviceFileDownloadCheckpoint>[];

  @override
  Future<DeviceFileDownloadCheckpoint?> find({
    required String deviceId,
    required List<int> nameSlot,
  }) async {
    for (final item in items) {
      if (item.deviceId == deviceId && _sameBytes(item.nameSlot, nameSlot)) {
        return item;
      }
    }
    return null;
  }

  @override
  Future<void> remove(String id) async {
    items.removeWhere((item) => item.id == id);
  }

  @override
  Future<void> removeAllForDevice(String deviceId) async {
    items.removeWhere((item) => item.deviceId == deviceId);
  }

  @override
  Future<void> save(DeviceFileDownloadCheckpoint checkpoint) async {
    await remove(checkpoint.id);
    items.add(checkpoint);
  }

  bool _sameBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
