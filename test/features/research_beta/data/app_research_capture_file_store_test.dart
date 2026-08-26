import 'dart:io';

import 'package:aipin/features/research_beta/data/app_research_capture_file_store.dart';
import 'package:aipin/features/research_beta/domain/research_capture_file_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late AppResearchCaptureFileStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('aipin-research-audio-');
    store = AppResearchCaptureFileStore.forTesting(root: directory);
  });

  tearDown(() => directory.delete(recursive: true));

  test('copies a local recording into independent research storage', () async {
    final source = File('${directory.path}${Platform.pathSeparator}local.m4a');
    await source.writeAsBytes(<int>[1, 2, 3]);

    final copy = await store.copyFromLocal(
      id: 'capture-1',
      sourcePath: source.path,
    );
    await source.delete();

    expect(copy.relativePath, 'capture-1.m4a');
    expect(await File(copy.absolutePath).readAsBytes(), <int>[1, 2, 3]);
  });

  test(
    'rejects unsafe paths instead of touching local recording storage',
    () async {
      await expectLater(
        store.absolutePathFor('../recordings/local.m4a'),
        throwsA(isA<ResearchCaptureFileException>()),
      );
      await expectLater(
        store.delete('recordings/local.m4a'),
        throwsA(isA<ResearchCaptureFileException>()),
      );
    },
  );
}
