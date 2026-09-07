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
      phase: DeviceFileDownloadPhase.values.byName(row.phase),
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
      phase: Value(checkpoint.phase.name),
      updatedAt: checkpoint.updatedAt,
    );
  }
}
