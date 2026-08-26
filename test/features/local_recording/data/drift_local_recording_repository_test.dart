import 'dart:io';

import 'package:drift/native.dart';
import 'package:aipin/core/persistence/app_database.dart';
import 'package:aipin/features/local_recording/data/drift_local_recording_repository.dart';
import 'package:aipin/features/local_recording/domain/local_recording.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  late AppDatabase database;
  late DriftLocalRecordingRepository repository;

  setUp(() {
    database = AppDatabase.forTesting();
    repository = DriftLocalRecordingRepository(database);
  });

  tearDown(() => database.close());

  test(
    'stores local records without device identity and returns newest first',
    () async {
      await repository.save(
        savedRecording(id: 'older', createdAt: DateTime(2026, 8, 20)),
      );
      await repository.save(
        savedRecording(id: 'newer', createdAt: DateTime(2026, 8, 21)),
      );

      expect((await repository.all()).map((item) => item.id), [
        'newer',
        'older',
      ]);
    },
  );

  test(
    'database version 2 creates local recordings without altering evidence rows',
    () async {
      await database.close();
      final directory = await Directory.systemTemp.createTemp('evt-drift-v1-');
      addTearDown(() => directory.delete(recursive: true));
      final v1File = File(
        '${directory.path}${Platform.pathSeparator}v1.sqlite',
      );
      seedV1EvidenceDatabase(v1File);
      final migrated = AppDatabase.forTesting(executor: NativeDatabase(v1File));
      addTearDown(migrated.close);

      expect(await migrated.select(migrated.evidenceBundles).get(), isNotEmpty);
      expect(await migrated.select(migrated.localRecordings).get(), isEmpty);
    },
  );
}

LocalRecording savedRecording({
  required String id,
  required DateTime createdAt,
}) {
  return LocalRecording.saved(
    id: id,
    title: '录音 $id',
    relativePath: '$id.m4a',
    createdAt: createdAt,
    completedAt: createdAt.add(const Duration(seconds: 8)),
    duration: const Duration(seconds: 8),
    sizeBytes: 32000,
  );
}

void seedV1EvidenceDatabase(File file) {
  final legacy = sqlite.sqlite3.open(file.path);
  legacy.execute('''
    CREATE TABLE evidence_bundles (
      id TEXT NOT NULL PRIMARY KEY, session_id TEXT NOT NULL,
      device_id TEXT NOT NULL, device_name TEXT NOT NULL,
      firmware_version TEXT, verdict TEXT NOT NULL, reason TEXT NOT NULL,
      manual_note TEXT, diagnostic_json TEXT NOT NULL, created_at INTEGER NOT NULL
    );
    CREATE TABLE session_events (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, bundle_id TEXT NOT NULL,
      sequence INTEGER NOT NULL, record_kind TEXT NOT NULL, source TEXT NOT NULL,
      occurred_at INTEGER NOT NULL, payload_json TEXT NOT NULL
    );
    INSERT INTO evidence_bundles VALUES (
      'evidence-1', 'session-1', 'device-1', 'AIPIN_8423', NULL,
      'passed', '已获得所需设备证据。', NULL, '{}', 1787302800000
    );
    PRAGMA user_version = 1;
  ''');
  legacy.close();
}
