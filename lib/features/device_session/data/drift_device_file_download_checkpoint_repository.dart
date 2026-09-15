import 'dart:convert';

import 'package:aipin/core/persistence/app_database.dart';
import 'package:aipin/features/device_session/domain/device_file_download_checkpoint.dart';
import 'package:aipin/features/device_session/domain/device_file_download_checkpoint_repository.dart';
import 'package:drift/drift.dart' show Value;

class DriftDeviceFileDownloadCheckpointRepository
    implements DeviceFileDownloadCheckpointRepository {
  DriftDeviceFileDownloadCheckpointRepository(this._database);

  final AppDatabase _database;

  @override
  Future<List<DeviceFileDownloadCheckpoint>> allDownloading() async {
    // `phase` is a historical database column from an earlier archive
    // prototype. The V1.6 EVT path has only an interruptible download, so any
    // stored value is treated as resumable.
    final rows = await _database
        .select(_database.deviceFileDownloadCheckpoints)
        .get();
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<DeviceFileDownloadCheckpoint?> find({
    required String deviceId,
    required List<int> nameSlot,
  }) async {
    final id = DeviceFileDownloadCheckpoint.idFor(
      deviceId: deviceId,
      nameSlot: nameSlot,
    );
    final row = await (_database.select(
      _database.deviceFileDownloadCheckpoints,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  @override
  Future<void> save(DeviceFileDownloadCheckpoint checkpoint) {
    return _database
        .into(_database.deviceFileDownloadCheckpoints)
        .insertOnConflictUpdate(_toCompanion(checkpoint));
  }

  @override
  Future<void> remove(String id) {
    return (_database.delete(
      _database.deviceFileDownloadCheckpoints,
    )..where((table) => table.id.equals(id))).go();
  }

  @override
  Future<void> removeAllForDevice(String deviceId) {
    return (_database.delete(
      _database.deviceFileDownloadCheckpoints,
    )..where((table) => table.deviceId.equals(deviceId))).go();
  }

  DeviceFileDownloadCheckpoint _fromRow(DeviceFileDownloadCheckpointRow row) {
    return DeviceFileDownloadCheckpoint(
      id: row.id,
      deviceId: row.deviceId,
      nameSlot: List<int>.unmodifiable(base64Url.decode(row.nameSlotBase64)),
      recordingId: row.recordingId,
      expectedLength: int.parse(row.expectedLength),
      expectedCrc32: int.parse(row.expectedCrc32),
      receivedBytes: row.receivedBytes,
      updatedAt: row.updatedAt,
    );
  }

  DeviceFileDownloadCheckpointsCompanion _toCompanion(
    DeviceFileDownloadCheckpoint checkpoint,
  ) {
    return DeviceFileDownloadCheckpointsCompanion.insert(
      id: checkpoint.id,
      deviceId: checkpoint.deviceId,
      nameSlotBase64: base64Url.encode(checkpoint.nameSlot),
      recordingId: checkpoint.recordingId,
      expectedLength: checkpoint.expectedLength.toString(),
      expectedCrc32: checkpoint.expectedCrc32.toString(),
      receivedBytes: checkpoint.receivedBytes,
      // Normalize the historical phase column when this checkpoint is next
      // saved; V1.6 EVT always resumes through the download path.
      phase: const Value('downloading'),
      updatedAt: checkpoint.updatedAt,
    );
  }
}
