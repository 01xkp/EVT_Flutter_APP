import 'dart:io';

import 'package:aipin/features/device_logs/data/file_app_log_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('aipin-log-test-');
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('keeps a bounded live view and writes a sanitized debug file', () async {
    final store = FileAppLogStore(
      supportDirectoryProvider: () async => root,
      enabled: true,
      maxEntries: 2,
      clock: () => DateTime.utc(2026, 9, 1, 12),
    );
    await store.initialize();
    store.info(
      'connected',
      scope: 'BLE',
      fields: {
        'device': 'AA:BB:CC:DD',
        'ticket': 'secret',
        'audioData': [1, 2, 3],
      },
    );
    store.info('second');
    store.info('third');
    await store.flush();

    expect(store.entries, hasLength(2));
    final path = await store.exportPath();
    expect(path, endsWith('logs${Platform.pathSeparator}aipin-2026-09-01.log'));
    final content = await File(path!).readAsString();
    expect(content, contains('device=...C:DD'));
    expect(content, contains('ticket=[redacted]'));
    expect(content, contains('audioData=bytes=3'));
    await store.close();
    store.dispose();
  });

  test('rotates when the current file exceeds the configured size', () async {
    final store = FileAppLogStore(
      supportDirectoryProvider: () async => root,
      enabled: true,
      maxFileBytes: 30,
      clock: () => DateTime.utc(2026, 9, 1),
    );
    await store.initialize();
    store.info('a-long-event-with-content');
    await store.flush();
    store.info('second-event');
    await store.flush();

    final files = await Directory(
      '${root.path}${Platform.pathSeparator}logs',
    ).list().where((entry) => entry is File).toList();
    expect(files.any((file) => file.path.endsWith('.1')), isTrue);
    await store.close();
    store.dispose();
  });

  test(
    'persists an event recorded before asynchronous initialization completes',
    () async {
      final store = FileAppLogStore(
        supportDirectoryProvider: () async => root,
        enabled: true,
        clock: () => DateTime.utc(2026, 9, 1),
      );
      store.info('early_event');
      await store.flush();

      final path = await store.exportPath();
      expect(await File(path!).readAsString(), contains('early_event'));
      await store.close();
      store.dispose();
    },
  );
}
