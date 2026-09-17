import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:aipin/core/persistence/app_database.dart';
import 'package:aipin/features/device_session/data/drift_device_file_download_checkpoint_repository.dart';
import 'package:aipin/features/device_session/domain/device_file_download_checkpoint.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  late AppDatabase database;
  late DriftDeviceFileDownloadCheckpointRepository repository;

  setUp(() {
    database = AppDatabase.forTesting();
    repository = DriftDeviceFileDownloadCheckpointRepository(database);
  });

  tearDown(() => database.close());

  test(
    'restores a checkpoint using its device and exact filename slot',
    () async {
      const nameSlot = [99, 97, 112, 116, 117, 114, 101, 46, 111, 103, 103, 0];
      final checkpoint = DeviceFileDownloadCheckpoint(
        id: DeviceFileDownloadCheckpoint.idFor(
          deviceId: 'device-1',
          nameSlot: nameSlot,
        ),
        deviceId: 'device-1',
        nameSlot: nameSlot,
        recordingId: 'device-recording-1',
        expectedLength: 30,
        expectedCrc32: 0xF70A2C1B,
        receivedBytes: 12,
        updatedAt: DateTime.utc(2026, 9, 1),
      );

      await repository.save(checkpoint);
      final restored = await repository.find(
        deviceId: 'device-1',
        nameSlot: nameSlot,
      );

      expect(restored?.recordingId, 'device-recording-1');
      expect(restored?.expectedCrc32, 0xF70A2C1B);
      expect(restored?.receivedBytes, 12);
      expect(
        await repository.find(deviceId: 'device-2', nameSlot: nameSlot),
        isNull,
      );
    },
  );

  test('removes every checkpoint only for the cleared device', () async {
    final one = _checkpoint(deviceId: 'device-1', nameSlot: const [1, 0]);
    final two = _checkpoint(deviceId: 'device-1', nameSlot: const [2, 0]);
    final other = _checkpoint(deviceId: 'device-2', nameSlot: const [1, 0]);
    await repository.save(one);
    await repository.save(two);
    await repository.save(other);

    await repository.removeAllForDevice('device-1');

    expect(
      await repository.find(deviceId: 'device-1', nameSlot: const [1, 0]),
      isNull,
    );
    expect(
      await repository.find(deviceId: 'device-1', nameSlot: const [2, 0]),
      isNull,
    );
    expect(
      await repository.find(deviceId: 'device-2', nameSlot: const [1, 0]),
      isNotNull,
    );
  });

  test('preserves a DVT ready-for-archive checkpoint phase', () async {
    final checkpoint = _checkpoint(
      deviceId: 'device-1',
      nameSlot: const [1, 0],
    );
    await repository.save(checkpoint);
    await (database.update(
      database.deviceFileDownloadCheckpoints,
    )..where((table) => table.id.equals(checkpoint.id))).write(
      const DeviceFileDownloadCheckpointsCompanion(
        phase: Value('readyForArchive'),
      ),
    );

    final active = await repository.allDownloading();

    expect(active.map((item) => item.id), [checkpoint.id]);
    expect(active.single.phase, DeviceFileDownloadPhase.readyForArchive);
    await repository.save(active.single);
    final normalized = await (database.select(
      database.deviceFileDownloadCheckpoints,
    )..where((table) => table.id.equals(checkpoint.id))).getSingle();
    expect(normalized.phase, 'readyForArchive');
  });

  test(
    'database version 5 gains the device download checkpoint table',
    () async {
      await database.close();
      final directory = await Directory.systemTemp.createTemp(
        'aipin-drift-v5-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}${Platform.pathSeparator}v5.sqlite');
      _seedV5Database(file);
      final migrated = AppDatabase.forTesting(executor: NativeDatabase(file));
      addTearDown(migrated.close);

      expect(
        await migrated.select(migrated.deviceFileDownloadCheckpoints).get(),
        isEmpty,
      );
    },
  );
}

DeviceFileDownloadCheckpoint _checkpoint({
  required String deviceId,
  required List<int> nameSlot,
}) => DeviceFileDownloadCheckpoint(
  id: DeviceFileDownloadCheckpoint.idFor(
    deviceId: deviceId,
    nameSlot: nameSlot,
  ),
  deviceId: deviceId,
  nameSlot: nameSlot,
  recordingId: '$deviceId-${nameSlot.first}',
  expectedLength: 30,
  expectedCrc32: 0xF70A2C1B,
  receivedBytes: 12,
  updatedAt: DateTime.utc(2026, 9, 1),
);

void _seedV5Database(File file) {
  final legacy = sqlite.sqlite3.open(file.path);
  legacy.execute('''
    CREATE TABLE local_recordings (
      id TEXT NOT NULL PRIMARY KEY,
      title TEXT NOT NULL,
      relative_path TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      completed_at INTEGER,
      duration_ms INTEGER,
      size_bytes INTEGER,
      state TEXT NOT NULL,
      failure_reason TEXT
    );
    PRAGMA user_version = 5;
  ''');
  legacy.close();
}
