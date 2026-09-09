import 'dart:async';
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

  test(
    'flushes every buffered debug entry without waiting for the write debounce',
    () async {
      final store = FileAppLogStore(
        supportDirectoryProvider: () async => root,
        enabled: true,
        writeDebounce: const Duration(hours: 1),
        clock: () => DateTime.utc(2026, 9, 1, 12),
      );
      addTearDown(store.dispose);

      for (var index = 0; index < 200; index += 1) {
        store.info('packet_$index', scope: 'BLE');
      }
      await store.flush();

      final path = await store.exportPath();
      final content = await File(path!).readAsString();
      expect(RegExp(r'packet_\d+').allMatches(content), hasLength(200));
    },
  );

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
    'retains ordered rotated logs and mirrors each completed segment',
    () async {
      final sink = _FakePublicDiagnosticLogSink();
      final store = FileAppLogStore(
        supportDirectoryProvider: () async => root,
        enabled: true,
        maxFileBytes: 1,
        keepFiles: 3,
        publicDiagnosticLogSink: sink,
        clock: () => DateTime.utc(2026, 9, 1),
      );

      store.info('first_segment');
      await store.flush();
      store.info('second_segment');
      await store.flush();
      store.info('third_segment');
      await store.flush();

      final directory = Directory('${root.path}${Platform.pathSeparator}logs');
      final current = File(
        '${directory.path}${Platform.pathSeparator}aipin-2026-09-01.log',
      );
      final previous = File('${current.path}.1');
      final oldest = File('${current.path}.2');
      expect(await current.readAsString(), contains('third_segment'));
      expect(await previous.readAsString(), contains('second_segment'));
      expect(await oldest.readAsString(), contains('first_segment'));
      expect(
        sink.calls.map((call) => call.filename),
        contains('aipin-2026-09-01.log.1'),
      );

      await store.close();
      store.dispose();
    },
  );

  test(
    'switches to a new daily file when a running session crosses midnight',
    () async {
      var now = DateTime.utc(2026, 9, 1, 23, 59, 59);
      final store = FileAppLogStore(
        supportDirectoryProvider: () async => root,
        enabled: true,
        clock: () => now,
      );

      store.info('before_midnight');
      await store.flush();
      now = DateTime.utc(2026, 9, 2);
      store.info('after_midnight');
      await store.flush();

      final directory = Directory('${root.path}${Platform.pathSeparator}logs');
      final firstDay = File(
        '${directory.path}${Platform.pathSeparator}aipin-2026-09-01.log',
      );
      final secondDay = File(
        '${directory.path}${Platform.pathSeparator}aipin-2026-09-02.log',
      );
      expect(await firstDay.readAsString(), contains('before_midnight'));
      expect(await firstDay.readAsString(), isNot(contains('after_midnight')));
      expect(await secondDay.readAsString(), contains('after_midnight'));
      expect(await store.exportPath(), secondDay.path);

      await store.close();
      store.dispose();
    },
  );

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
    'drains an accepted entry when disposal starts before initialization completes',
    () async {
      final supportDirectory = Completer<Directory>();
      final store = FileAppLogStore(
        supportDirectoryProvider: () => supportDirectory.future,
        enabled: true,
        clock: () => DateTime.utc(2026, 9, 1),
      );

      store.info('entry_before_dispose');
      store.dispose();
      supportDirectory.complete(root);
      await store.close();

      final file = File(
        '${root.path}${Platform.pathSeparator}logs'
        '${Platform.pathSeparator}aipin-2026-09-01.log',
      );
      expect(await file.readAsString(), contains('entry_before_dispose'));
    },
  );

  test(
    'close completes when an external log-stream listener is paused',
    () async {
      final store = FileAppLogStore(enabled: false);
      final subscription = store.stream.listen((_) {});
      subscription.pause();
      addTearDown(subscription.cancel);

      await store.close().timeout(const Duration(seconds: 1));

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

  test(
    'flush forces a pending public mirror inside the debounce window',
    () async {
      final sink = _FakePublicDiagnosticLogSink();
      final store = FileAppLogStore(
        supportDirectoryProvider: () async => root,
        enabled: true,
        publicDiagnosticLogSink: sink,
        clock: () => DateTime.utc(2026, 9, 1, 12),
      );

      store.info('first');
      await store.flush();
      store.info('second');
      await store.flush();

      expect(sink.calls, hasLength(2));
      await store.close();
      store.dispose();
    },
  );

  test(
    'allows a delayed public mirror to finish after disposal without notifying',
    () async {
      final sink = _DelayedPublicDiagnosticLogSink();
      final store = FileAppLogStore(
        supportDirectoryProvider: () async => root,
        enabled: true,
        publicDiagnosticLogSink: sink,
        clock: () => DateTime.utc(2026, 9, 1, 12),
      );

      store.info('mirror_before_dispose');
      final flush = store.flush();
      await sink.started.future;
      store.dispose();
      sink.complete(
        PublicDiagnosticLogMirrorStatus.success(
          relativePath: 'Download/AIPIN/logs/aipin-2026-09-01.log',
          lastUpdatedAt: DateTime.utc(2026, 9, 1, 12),
        ),
      );

      await flush;
      await store.close();
      expect(sink.calls, hasLength(1));
    },
  );

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
      final content = await File(path!).readAsString();
      expect(content, contains('product_operation_completed'));
      expect(content, contains('public_mirror_failed'));
      expect(content, contains('error_code=storage_error'));
      expect(store.publicMirrorStatus?.failureCode, 'storage_error');
      expect(
        store.entries.where((entry) => entry.scope == 'STORAGE'),
        isNotEmpty,
      );
      await store.close();
      store.dispose();
    },
  );

  test(
    'suppresses repeated public mirror failures and records recovery once',
    () async {
      var now = DateTime.utc(2026, 9, 1, 12);
      final sink = _FakePublicDiagnosticLogSink(shouldFail: true);
      final store = FileAppLogStore(
        supportDirectoryProvider: () async => root,
        enabled: true,
        publicDiagnosticLogSink: sink,
        clock: () => now,
      );

      store.info('first_operation');
      await store.flush();
      now = now.add(const Duration(minutes: 1));
      store.info('second_operation');
      await store.flush();

      sink.shouldFail = false;
      now = now.add(const Duration(minutes: 1));
      store.info('third_operation');
      await store.flush();

      final path = await store.exportPath();
      final content = await File(path!).readAsString();
      expect(RegExp('public_mirror_failed').allMatches(content), hasLength(1));
      expect(
        RegExp('public_mirror_recovered').allMatches(content),
        hasLength(1),
      );
      expect(sink.calls, hasLength(3));
      await store.close();
      store.dispose();
    },
  );
}

class _FakePublicDiagnosticLogSink implements PublicDiagnosticLogSink {
  _FakePublicDiagnosticLogSink({this.shouldFail = false});

  bool shouldFail;
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

class _DelayedPublicDiagnosticLogSink implements PublicDiagnosticLogSink {
  final started = Completer<void>();
  final _result = Completer<PublicDiagnosticLogMirrorStatus>();
  final List<_MirrorCall> calls = <_MirrorCall>[];

  @override
  Future<PublicDiagnosticLogMirrorStatus> mirrorCanonicalFile({
    required String sourcePath,
    required String filename,
  }) {
    calls.add(_MirrorCall(sourcePath: sourcePath, filename: filename));
    if (!started.isCompleted) {
      started.complete();
    }
    return _result.future;
  }

  void complete(PublicDiagnosticLogMirrorStatus status) {
    if (!_result.isCompleted) {
      _result.complete(status);
    }
  }
}

class _MirrorCall {
  const _MirrorCall({required this.sourcePath, required this.filename});

  final String sourcePath;
  final String filename;
}
