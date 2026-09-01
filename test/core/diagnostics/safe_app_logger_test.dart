import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/features/device_logs/application/app_log_logger.dart';
import 'package:aipin/features/device_logs/domain/app_log_entry.dart';
import 'package:aipin/features/device_logs/domain/app_log_store.dart';

void main() {
  test('debug logger writes a scoped timestamped event', () {
    final messages = <String>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) {
        messages.add(message);
      }
    };
    addTearDown(() => debugPrint = previous);

    const DebugSafeAppLogger(
      scope: 'BLE',
    ).info('connection_update', fields: {'state': 'disconnected'});

    expect(messages, hasLength(1));
    expect(messages.single, startsWith('[AIPIN][BLE] '));
    expect(messages.single, contains(' connection_update state=disconnected'));
  });

  test('persistent logger forwards events to the shared log store', () {
    final store = _FakeAppLogStore();
    PersistentAppLogger(
      store,
    ).info('connection_update', fields: {'state': 'connected'});
    expect(store.entries, hasLength(1));
    expect(store.entries.single.event, 'connection_update');
    expect(store.entries.single.scope, 'APP');
    expect(store.entries.single.fields['state'], 'connected');
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
