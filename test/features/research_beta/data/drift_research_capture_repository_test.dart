import 'dart:io';

import 'package:drift/native.dart';
import 'package:aipin/core/persistence/app_database.dart';
import 'package:aipin/features/research_beta/data/drift_research_capture_repository.dart';
import 'package:aipin/features/research_beta/domain/research_capture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  late AppDatabase database;
  late DriftResearchCaptureRepository repository;

  setUp(() {
    database = AppDatabase.forTesting();
    repository = DriftResearchCaptureRepository(database);
  });

  tearDown(() => database.close());

  test(
    'persists ordered independent ASR segment job IDs for background recovery',
    () async {
      final capture = _directCapture('capture-1')
          .withAsrSegments(const <ResearchAsrSegment>[
            ResearchAsrSegment(
              index: 0,
              relativePath: 'capture-1.segment-0000.m4a',
              jobId: 'job-first',
            ),
            ResearchAsrSegment(
              index: 1,
              relativePath: 'capture-1.segment-0001.m4a',
              jobId: 'job-second',
            ),
          ]);

      await repository.save(capture);

      expect(
        (await repository.findById('capture-1'))!.asrSegments,
        const <ResearchAsrSegment>[
          ResearchAsrSegment(
            index: 0,
            relativePath: 'capture-1.segment-0000.m4a',
            jobId: 'job-first',
          ),
          ResearchAsrSegment(
            index: 1,
            relativePath: 'capture-1.segment-0001.m4a',
            jobId: 'job-second',
          ),
        ],
      );
    },
  );

  test(
    'research captures are persisted without creating local recording rows',
    () async {
      await repository.save(_directCapture('capture-1'));

      expect(await database.select(database.localRecordings).get(), isEmpty);
      expect(
        (await repository.findById('capture-1'))!.relativePath,
        'research_captures/capture-1.m4a',
      );
    },
  );

  test(
    'one original local recording can have only one research copy',
    () async {
      await repository.save(_localUpload('capture-1', 'local-1'));

      await expectLater(
        repository.save(_localUpload('capture-2', 'local-1')),
        throwsA(isA<StateError>()),
      );
      expect(
        (await repository.findByOriginalLocalRecordingId('local-1'))!.id,
        'capture-1',
      );
    },
  );

  test('database version 2 migrates to research capture tables', () async {
    await database.close();
    final directory = await Directory.systemTemp.createTemp('aipin-drift-v2-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}v2.sqlite');
    _seedV2Database(file);
    final migrated = AppDatabase.forTesting(executor: NativeDatabase(file));
    addTearDown(migrated.close);

    expect(await migrated.select(migrated.researchCaptures).get(), isEmpty);
    expect(await migrated.select(migrated.localRecordings).get(), isEmpty);
  });
}

ResearchCapture _directCapture(String id) => ResearchCapture.fromDirectAiVoice(
  id: id,
  participantId: 'participant-1',
  relativePath: 'research_captures/$id.m4a',
  duration: const Duration(seconds: 12),
  createdAt: DateTime(2026, 8, 24),
);

ResearchCapture _localUpload(String id, String localId) =>
    ResearchCapture.fromLocalRecording(
      id: id,
      participantId: 'participant-1',
      originalLocalRecordingId: localId,
      relativePath: 'research_captures/$id.m4a',
      duration: const Duration(seconds: 12),
      createdAt: DateTime(2026, 8, 24),
    );

void _seedV2Database(File file) {
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
    PRAGMA user_version = 2;
  ''');
  legacy.close();
}
