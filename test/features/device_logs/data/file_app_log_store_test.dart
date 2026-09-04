import 'dart:io';

import 'package:aipin/features/device_logs/data/file_app_log_store.dart';
import 'package:aipin/features/device_logs/domain/public_diagnostic_log_sink.dart';
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
    expect(content, contains(' | INFO | BLE | - | - | - | connected | - | -'));
    expect(content, isNot(contains('AA:BB:CC:DD')));
    expect(content, isNot(contains('secret')));
    expect(content, isNot(contains('[1, 2, 3]')));
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

  test(
    'does not persist when a non-debug build forces logging enabled',
    () async {
      final store = FileAppLogStore(
        supportDirectoryProvider: () async => root,
        enabled: true,
        isDebugBuild: () => false,
      );

      store.info('connected');
      await store.initialize();
      await store.flush();

      expect(store.entries, isEmpty);
      expect(store.isPersistent, isFalse);
      expect(
        Directory('${root.path}${Platform.pathSeparator}logs').exists(),
        completion(isFalse),
      );
      await store.close();
      store.dispose();
    },
  );

  test(
    'mirrors the completed canonical daily file once for rapid log events',
    () async {
      final sink = _FakePublicDiagnosticLogSink();
      final store = FileAppLogStore(
        supportDirectoryProvider: () async => root,
        enabled: true,
        publicDiagnosticLogSink: sink,
        clock: () => DateTime.utc(2026, 9, 1, 12),
      );

      store.info('first');
      store.info('second');
      await store.flush();

      expect(sink.calls, hasLength(1));
      expect(sink.calls.single.filename, 'aipin-2026-09-01.log');
      expect(
        await File(sink.calls.single.sourcePath).readAsString(),
        contains('second'),
      );
      expect(
        store.publicMirrorStatus?.relativePath,
        'Download/AIPIN/logs/aipin-2026-09-01.log',
      );
      await store.close();
      store.dispose();
    },
  );

  test('flush forces a pending public mirror', () async {
    final sink = _FakePublicDiagnosticLogSink();
    final store = FileAppLogStore(
      supportDirectoryProvider: () async => root,
      enabled: true,
      publicDiagnosticLogSink: sink,
      mirrorDebounce: Duration.zero,
      clock: () => DateTime.utc(2026, 9, 1, 12),
    );

    store.info('first');
    await store.flush();
    store.info('second');
    await store.flush();

    expect(sink.calls, hasLength(2));
    await store.close();
    store.dispose();
  });

  test(
    'retains private logs and reports a bounded storage event on mirror failure',
    () async {
      final sink = _FakePublicDiagnosticLogSink(shouldFail: true);
      final store = FileAppLogStore(
        supportDirectoryProvider: () async => root,
        enabled: true,
        publicDiagnosticLogSink: sink,
        clock: () => DateTime.utc(2026, 9, 1, 12),
      );

      store.info('product_operation_completed');
      await store.flush();

      final path = await store.exportPath();
      expect(
        await File(path!).readAsString(),
        contains('product_operation_completed'),
      );
      expect(store.publicMirrorStatus?.failureCode, 'storage_error');
      expect(
        store.entries.where((entry) => entry.scope == 'STORAGE'),
        isNotEmpty,
      );
      await store.close();
      store.dispose();
    },
  );
}

class _FakePublicDiagnosticLogSink implements PublicDiagnosticLogSink {
  _FakePublicDiagnosticLogSink({this.shouldFail = false});

  final bool shouldFail;
  final List<_MirrorCall> calls = <_MirrorCall>[];

  @override
  Future<PublicDiagnosticLogMirrorStatus> mirrorCanonicalFile({
    required String sourcePath,
    required String filename,
  }) async {
    calls.add(_MirrorCall(sourcePath: sourcePath, filename: filename));
    if (shouldFail) {
      return PublicDiagnosticLogMirrorStatus.failure('storage_error');
    }
    return PublicDiagnosticLogMirrorStatus.success(
      relativePath: 'Download/AIPIN/logs/$filename',
      lastUpdatedAt: DateTime.utc(2026, 9, 1, 12),
    );
  }
}

class _MirrorCall {
  const _MirrorCall({required this.sourcePath, required this.filename});

  final String sourcePath;
  final String filename;
}
