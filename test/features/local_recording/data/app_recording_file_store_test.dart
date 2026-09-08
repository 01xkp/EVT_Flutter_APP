import 'dart:io';

import 'package:aipin/features/local_recording/data/app_recording_file_store.dart';
import 'package:aipin/features/local_recording/domain/recording_file_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late AppRecordingFileStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('evt-recordings-');
    store = AppRecordingFileStore.forTesting(root: directory);
  });

  tearDown(() => directory.delete(recursive: true));

  test(
    'promotes a completed temporary capture to the stable M4A path',
    () async {
      final pending = await store.createPending(id: 'recording-1');
      await File(pending.temporaryPath).writeAsBytes([1, 2, 3]);

      final completed = await store.finalize(pending);

      expect(completed.relativePath, 'recording-1.m4a');
      expect(completed.sizeBytes, 3);
      expect(File(completed.absolutePath).exists(), completion(isTrue));
      expect(File(pending.temporaryPath).exists(), completion(isFalse));
    },
  );

  test(
    'recovers a readable partial file and reports a missing file as absent',
    () async {
      final pending = await store.createPending(id: 'recording-2');
      await File(pending.temporaryPath).writeAsBytes([4, 5]);

      final recovered = await store.recoverPartial(pending.relativePath);

      expect(recovered!.sizeBytes, 2);
      expect(File(recovered.absolutePath).exists(), completion(isTrue));
      expect(await store.recoverPartial('missing.m4a'), isNull);
    },
  );

  test(
    'discards a temporary capture without creating a completed recording',
    () async {
      final pending = await store.createPending(id: 'recording-3');
      await File(pending.temporaryPath).writeAsBytes([4, 5]);

      await store.discard(pending);

      expect(File(pending.temporaryPath).exists(), completion(isFalse));
      expect(
        File(await store.absolutePathFor(pending.relativePath)).exists(),
        completion(isFalse),
      );
    },
  );

  test(
    'cleans orphaned temporary files without deleting completed captures',
    () async {
      final orphan = await store.createPending(id: 'orphan-recording');
      await File(orphan.temporaryPath).writeAsBytes([4, 5]);

      final pendingFinal = await store.createPending(id: 'completed-recording');
      await File(pendingFinal.temporaryPath).writeAsBytes([6, 7, 8]);
      final completed = await store.finalize(pendingFinal);

      await store.cleanupOrphanedTemporaryFiles();

      expect(File(orphan.temporaryPath).exists(), completion(isFalse));
      expect(File(completed.absolutePath).exists(), completion(isTrue));
    },
  );

  test(
    'keeps checkpoint-owned device temporary files while cleaning other orphans',
    () async {
      final orphan = await store.createPending(id: 'orphan-recording');
      await File(orphan.temporaryPath).writeAsBytes([4, 5]);
      final protected = await store.createPending(
        id: 'device-checkpoint',
        extension: '.ogg',
      );
      await File(protected.temporaryPath).writeAsBytes([6, 7, 8]);

      await store.cleanupOrphanedTemporaryFiles(
        protectedRecordingIds: [protected.id],
      );

      expect(File(orphan.temporaryPath).exists(), completion(isFalse));
      expect(File(protected.temporaryPath).exists(), completion(isTrue));
    },
  );

  test('rejects empty captures and unsafe relative paths', () async {
    final pending = await store.createPending(id: 'recording-4');
    await File(pending.temporaryPath).create(recursive: true);

    await expectLater(
      store.finalize(pending),
      throwsA(isA<RecordingFileException>()),
    );
    await expectLater(
      store.absolutePathFor('../outside.m4a'),
      throwsA(isA<RecordingFileException>()),
    );
  });

  test('imports a device OGG file without changing its extension', () async {
    final imported = await store.importBytes(
      id: 'device-1',
      extension: '.ogg',
      chunks: Stream<List<int>>.fromIterable(const [
        [1, 2],
        [3],
      ]),
    );

    expect(imported.relativePath, 'device-1.ogg');
    expect(imported.sizeBytes, 3);
    expect(await File(imported.absolutePath).readAsBytes(), [1, 2, 3]);
  });

  test(
    'keeps a device download temporary file available for a later resume',
    () async {
      final pending = await store.createPending(
        id: 'device-2',
        extension: '.ogg',
      );

      await store.append(pending, const [1, 2]);

      expect(await store.pendingLength(pending), 2);
      expect(
        await store.readPending(pending).expand((bytes) => bytes).toList(),
        [1, 2],
      );
      expect(File(pending.temporaryPath).exists(), completion(isTrue));
    },
  );
}
