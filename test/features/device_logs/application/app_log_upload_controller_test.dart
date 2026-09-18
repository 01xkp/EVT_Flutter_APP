import 'dart:async';
import 'dart:io';

import 'package:aipin/core/diagnostics/diagnostic_trace.dart';
import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/features/device_logs/application/app_log_upload_controller.dart';
import 'package:aipin/features/device_logs/domain/app_log_entry.dart';
import 'package:aipin/features/device_logs/domain/app_log_store.dart';
import 'package:aipin/features/device_logs/domain/app_log_upload_port.dart';
import 'package:aipin/features/device_logs/domain/public_diagnostic_log_sink.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'creates a private snapshot then uploads it with safe diagnostics',
    () async {
      final snapshot = await File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}evt-upload-success-${DateTime.now().microsecondsSinceEpoch}.log',
      ).create();
      final store = _FakeLogStore(snapshotPath: snapshot.path);
      final uploader = _FakeUploader();
      final logger = _CapturingLogger();
      final controller = AppLogUploadController(
        store: store,
        uploader: uploader,
        logger: logger,
      );

      final receipt = await controller.uploadLatest();

      expect(store.snapshotRequests, 1);
      expect(uploader.paths, [snapshot.path]);
      expect(await snapshot.exists(), isFalse);
      expect(receipt.bytes, 42);
      expect(logger.events, contains('app_log_upload_requested'));
      expect(logger.events, contains('app_log_upload_succeeded'));
      expect(
        logger.fields.expand(
          (fields) => fields.values.map((value) => '$value'),
        ),
        isNot(contains(snapshot.path)),
      );
    },
  );

  test('removes a private snapshot when the upload fails', () async {
    final snapshot = await File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}evt-upload-failure-${DateTime.now().microsecondsSinceEpoch}.log',
    ).create();
    final controller = AppLogUploadController(
      store: _FakeLogStore(snapshotPath: snapshot.path),
      uploader: _FakeUploader(
        failure: const AppLogUploadFailure(AppLogUploadFailureCode.connection),
      ),
      logger: _CapturingLogger(),
    );

    await expectLater(
      controller.uploadLatest(),
      throwsA(isA<AppLogUploadFailure>()),
    );

    expect(await snapshot.exists(), isFalse);
  });

  test('does not create a snapshot when uploading is not configured', () async {
    final store = _FakeLogStore(
      snapshotPath: '/private/aipin-2026-09-16-10-00-00.log',
    );
    final logger = _CapturingLogger();
    final controller = AppLogUploadController(
      store: store,
      uploader: _FakeUploader(configured: false),
      logger: logger,
    );

    await expectLater(
      controller.uploadLatest(),
      throwsA(
        isA<AppLogUploadFailure>().having(
          (failure) => failure.code,
          'code',
          AppLogUploadFailureCode.unconfigured,
        ),
      ),
    );

    expect(store.snapshotRequests, 0);
    expect(logger.events, contains('app_log_upload_unconfigured'));
  });

  test(
    'coalesces duplicate upload requests and permits a later retry',
    () async {
      final store = _FakeLogStore(
        snapshotPath: '/private/aipin-2026-09-16-10-00-00.log',
      );
      final uploader = _FakeUploader(blockFirstUpload: true);
      final controller = AppLogUploadController(
        store: store,
        uploader: uploader,
        logger: _CapturingLogger(),
      );

      final first = controller.uploadLatest();
      final second = controller.uploadLatest();
      await uploader.started.future;
      expect(store.snapshotRequests, 1);
      expect(uploader.paths, hasLength(1));

      uploader.completeFirstUpload();
      await Future.wait([first, second]);

      await controller.uploadLatest();
      expect(store.snapshotRequests, 2);
      expect(uploader.paths, hasLength(2));
    },
  );

  test('logs a stable error code when uploading fails', () async {
    final logger = _CapturingLogger();
    final controller = AppLogUploadController(
      store: _FakeLogStore(
        snapshotPath: '/private/aipin-2026-09-16-10-00-00.log',
      ),
      uploader: _FakeUploader(
        failure: const AppLogUploadFailure(AppLogUploadFailureCode.connection),
      ),
      logger: logger,
    );

    await expectLater(
      controller.uploadLatest(),
      throwsA(isA<AppLogUploadFailure>()),
    );

    final failureFields =
        logger.fields[logger.events.indexOf('app_log_upload_failed')];
    expect(failureFields['error_code'], 'connection');
    expect(failureFields.containsKey('path'), isFalse);
  });

  test('maps a snapshot creation error to a safe retryable failure', () async {
    final logger = _CapturingLogger();
    final uploader = _FakeUploader();
    final controller = AppLogUploadController(
      store: _FakeLogStore(snapshotPath: null, snapshotError: true),
      uploader: uploader,
      logger: logger,
    );

    await expectLater(
      controller.uploadLatest(),
      throwsA(
        isA<AppLogUploadFailure>().having(
          (failure) => failure.code,
          'code',
          AppLogUploadFailureCode.noSnapshot,
        ),
      ),
    );

    expect(uploader.paths, isEmpty);
    final failureFields =
        logger.fields[logger.events.indexOf('app_log_upload_failed')];
    expect(failureFields['error_code'], 'noSnapshot');
  });
}

class _FakeLogStore implements AppLogStore {
  _FakeLogStore({required this.snapshotPath, this.snapshotError = false});

  final String? snapshotPath;
  final bool snapshotError;
  var snapshotRequests = 0;

  @override
  List<AppLogEntry> get entries => const [];

  @override
  Stream<AppLogEntry> get stream => const Stream.empty();

  @override
  String? get currentFilePath => null;

  @override
  bool get isPersistent => true;

  @override
  PublicDiagnosticLogMirrorStatus? get publicMirrorStatus => null;

  @override
  Future<String?> createUploadSnapshot() async {
    snapshotRequests += 1;
    if (snapshotError) {
      throw StateError('private log unavailable');
    }
    return snapshotPath;
  }

  @override
  void clearView() {}

  @override
  Future<void> close() async {}

  @override
  void dispose() {}

  @override
  Future<String?> exportPath() async => null;

  @override
  Future<void> flush() async {}

  @override
  void info(
    String event, {
    String scope = 'APP',
    Map<String, Object?> fields = const {},
  }) {}

  @override
  Future<void> initialize() async {}

  @override
  void record(AppLogEntry entry) {}

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

class _FakeUploader implements AppLogUploadPort {
  _FakeUploader({
    this.configured = true,
    this.failure,
    this.blockFirstUpload = false,
  });

  final bool configured;
  final AppLogUploadFailure? failure;
  final bool blockFirstUpload;
  final paths = <String>[];
  final started = Completer<void>();
  final _firstUpload = Completer<void>();

  @override
  bool get isConfigured => configured;

  @override
  Future<AppLogUploadReceipt> upload({required String snapshotPath}) async {
    paths.add(snapshotPath);
    if (!started.isCompleted) started.complete();
    if (blockFirstUpload && paths.length == 1) {
      await _firstUpload.future;
    }
    if (failure case final failure?) throw failure;
    return const AppLogUploadReceipt(bytes: 42);
  }

  void completeFirstUpload() {
    if (!_firstUpload.isCompleted) _firstUpload.complete();
  }
}

class _CapturingLogger implements SafeAppLogger {
  final events = <String>[];
  final fields = <Map<String, Object?>>[];

  @override
  void error(
    String event, {
    DiagnosticTrace? trace,
    String? operation,
    String? stage,
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  }) => _record(event, fields);

  @override
  void info(
    String event, {
    DiagnosticTrace? trace,
    String? operation,
    String? stage,
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  }) => _record(event, fields);

  @override
  void warning(
    String event, {
    DiagnosticTrace? trace,
    String? operation,
    String? stage,
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  }) => _record(event, fields);

  void _record(String event, Map<String, Object?> values) {
    events.add(event);
    fields.add(values);
  }
}
