import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/core/diagnostics/diagnostic_trace.dart';
import 'package:aipin/features/device_logs/application/app_log_logger.dart';
import 'package:aipin/features/device_logs/domain/app_log_entry.dart';
import 'package:aipin/features/device_logs/domain/app_log_store.dart';

void main() {
  test('debug logger writes a sanitized structured event', () {
    final messages = <String>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) {
        messages.add(message);
      }
    };
    addTearDown(() => debugPrint = previous);

    const DebugSafeAppLogger(scope: 'BLE').warning(
      'connection_update',
      trace: DiagnosticTrace.start(
        operation: 'device_connect',
        origin: 'UI',
        deviceReference: 'safe-device',
        traceId: '8fa2c1',
      ),
      stage: 'connect',
      result: 'retrying',
      elapsed: const Duration(milliseconds: 30),
      fields: const {'state': 'disconnected', 'token': 'must-not-leak'},
    );

    expect(messages, hasLength(1));
    expect(messages.single, contains(' | WARNING | BLE | 8fa2c1 | '));
    expect(messages.single, contains('connection_update'));
    expect(messages.single, contains('state=disconnected'));
    expect(messages.single, isNot(contains('must-not-leak')));
  });

  test('persistent logger forwards events to the shared log store', () {
    final store = _FakeAppLogStore();
    PersistentAppLogger(store).error(
      'connection_update',
      stage: 'connect',
      result: 'failed',
      fields: const {'state': 'connected', 'error': 'must-not-leak'},
    );
    expect(store.entries, hasLength(1));
    expect(store.entries.single.event, 'connection_update');
    expect(store.entries.single.scope, 'APP');
    expect(store.entries.single.fields['state'], 'connected');
    expect(store.entries.single.fields.containsKey('error'), isFalse);
    expect(store.entries.single.level.name, 'error');
  });
}

class _FakeAppLogStore implements AppLogStore {
  final List<AppLogEntry> _entries = [];

  @override
  List<AppLogEntry> get entries => _entries;

  @override
  Stream<AppLogEntry> get stream => const Stream.empty();

  @override
  String? get currentFilePath => null;

  @override
  bool get isPersistent => false;

  @override
  void info(
    String event, {
    String scope = 'APP',
    Map<String, Object?> fields = const {},
  }) {
    _entries.add(
      AppLogEntry(
        timestamp: DateTime.utc(2026, 9, 1),
        scope: scope,
        event: event,
        fields: fields,
      ),
    );
  }

  @override
  void record(AppLogEntry entry) {
    _entries.add(entry);
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> flush() async {}

  @override
  Future<String?> exportPath() async => null;

  @override
  void clearView() {}

  @override
  Future<void> close() async {}

  @override
  void dispose() {}

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
