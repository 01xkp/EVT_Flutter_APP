import 'dart:io';

import 'package:evt_ble_app/features/local_recording/data/app_recording_file_store.dart';
import 'package:evt_ble_app/features/local_recording/domain/recording_file_store.dart';
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

  test('rejects empty captures and unsafe relative paths', () async {
    final pending = await store.createPending(id: 'recording-3');
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
}
