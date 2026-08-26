import 'package:drift/drift.dart';
import 'package:aipin/core/persistence/app_database.dart';
import 'package:aipin/features/local_recording/domain/local_recording.dart';
import 'package:aipin/features/local_recording/domain/local_recording_repository.dart';

class DriftLocalRecordingRepository implements LocalRecordingRepository {
  DriftLocalRecordingRepository(this._database);

  final AppDatabase _database;

  @override
  Future<List<LocalRecording>> all() async {
    final rows = await (_database.select(
      _database.localRecordings,
    )..orderBy([(row) => OrderingTerm.desc(row.createdAt)])).get();
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<void> delete(String id) async {
    await (_database.delete(
      _database.localRecordings,
    )..where((row) => row.id.equals(id))).go();
  }

  @override
  Future<void> save(LocalRecording recording) async {
    await _database
        .into(_database.localRecordings)
        .insert(_toCompanion(recording));
  }

  @override
  Future<void> update(LocalRecording recording) async {
    await _database
        .update(_database.localRecordings)
        .replace(_toRow(recording));
  }

  LocalRecording _fromRow(LocalRecordingRow row) {
    return LocalRecording(
      id: row.id,
      title: row.title,
      relativePath: row.relativePath,
      createdAt: row.createdAt,
      status: LocalRecordingStatus.values.byName(row.state),
      completedAt: row.completedAt,
      duration: row.durationMs == null
          ? null
          : Duration(milliseconds: row.durationMs!),
      sizeBytes: row.sizeBytes,
      failureReason: row.failureReason,
    );
  }

  LocalRecordingRow _toRow(LocalRecording value) {
    return LocalRecordingRow(
      id: value.id,
      title: value.title,
      relativePath: value.relativePath,
      createdAt: value.createdAt,
      completedAt: value.completedAt,
      durationMs: value.duration?.inMilliseconds,
      sizeBytes: value.sizeBytes,
      state: value.status.name,
      failureReason: value.failureReason,
    );
  }

  LocalRecordingsCompanion _toCompanion(LocalRecording value) {
    return LocalRecordingsCompanion.insert(
      id: value.id,
      title: value.title,
      relativePath: value.relativePath,
      createdAt: value.createdAt,
      completedAt: Value(value.completedAt),
      durationMs: Value(value.duration?.inMilliseconds),
      sizeBytes: Value(value.sizeBytes),
      state: value.status.name,
      failureReason: Value(value.failureReason),
    );
  }
}
