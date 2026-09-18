import 'package:flutter/foundation.dart' hide DiagnosticLevel;
import 'package:flutter_test/flutter_test.dart';

import 'package:aipin/core/diagnostics/diagnostic_event.dart';
import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/core/diagnostics/diagnostic_trace.dart';
import 'package:aipin/features/device_logs/application/app_log_logger.dart';
import 'package:aipin/features/device_logs/domain/app_log_entry.dart';
import 'package:aipin/features/device_logs/domain/app_log_store.dart';
import 'package:aipin/features/device_logs/domain/public_diagnostic_log_sink.dart';

void main() {
  test(
    'response wait details keep Chinese markers and reach persistent logs',
    () {
      final store = _FakeAppLogStore();
      PersistentAppLogger(store, scope: 'CMD').info(
        'evt_response_waiting',
        stage: 'response',
        result: 'pending',
        fields: const {
          'wait_id': 8,
          'elapsed_ms': 1020,
          'idle_ms': 1000,
          'remaining_ms': 1000,
          'response_count': 0,
          'expected_command': '0x89',
          'reason': '【回包监听】【等待中】继续监听',
        },
      );
      expect(store.entries.single.fields['wait_id'], 8);
      expect(store.entries.single.fields['remaining_ms'], 1000);
      expect(store.entries.single.fields['idle_ms'], 1000);
      expect(store.entries.single.fields['response_count'], 0);
      expect(store.entries.single.event, 'evt_response_waiting');
      final formatted = DiagnosticEvent(
        timestamp: DateTime.now(),
        level: DiagnosticLevel.info,
        scope: 'CMD',
        event: 'evt_response_waiting',
      ).formatLine();
      expect(formatted, contains('【回包监听：等待设备响应】'));
    },
  );

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
    expect(messages.single, startsWith('【AIPIN联调】【蓝牙】【警告】【阶段：蓝牙连接】【动作：连接更新】 '));
    expect(messages.single, contains(' | WARNING | BLE | 8fa2c1 | '));
    expect(messages.single, contains('connection_update'));
    expect(messages.single, contains('state=disconnected'));
    expect(messages.single, isNot(contains('must-not-leak')));
  });

  test('Chinese log prefix uses normalized scope and level labels', () {
    final diagnostic = DiagnosticEvent(
      timestamp: DateTime.utc(2026, 9, 8),
      level: DiagnosticLevel.error,
      scope: 'untrusted-scope',
      event: 'write_failure',
      fields: const {'token': 'must-not-leak', 'status': 'failed'},
    );

    final line = diagnostic.formatLine();

    expect(line, startsWith('【AIPIN联调】【应用】【错误】【阶段：未分阶段】【动作：写入失败】 '));
    expect(
      line,
      contains(' | ERROR | APP | - | - | - | write_failure | - | -'),
    );
    expect(line, contains('status=failed'));
    expect(line, isNot(contains('must-not-leak')));
  });

  test('background BLE keep-alive logs retain a clear lifecycle marker', () {
    final diagnostic = DiagnosticEvent(
      timestamp: DateTime.utc(2026, 9, 18),
      level: DiagnosticLevel.info,
      scope: 'APP_LIFECYCLE',
      operation: 'background_ble_monitoring',
      stage: 'background_monitoring',
      event: 'background_ble_monitoring_started',
      result: 'success',
    );

    expect(diagnostic.scope, 'APP_LIFECYCLE');
    expect(diagnostic.operation, 'background_ble_monitoring');
    expect(diagnostic.stage, 'background_monitoring');
    expect(diagnostic.chineseLogPrefix, contains('【阶段：后台蓝牙保活】'));
  });

  test('persistent Debug BLE logs retain complete packet hex', () {
    final store = _FakeAppLogStore();

    PersistentAppLogger(store, scope: 'BLE').info(
      'notification_received',
      stage: 'connected',
      result: 'success',
      fields: const {'raw_packet_hex': 'ED 04 00 89 01 2E AC', 'bytes': 7},
    );

    expect(store.entries, hasLength(1));
    expect(
      store.entries.single.fields['raw_packet_hex'],
      'ED 04 00 89 01 2E AC',
    );
  });

  test(
    'Chinese log prefix includes scope, level, stage, and action markers',
    () {
      final lifecycle = DiagnosticEvent(
        timestamp: DateTime.utc(2026, 9, 8),
        level: DiagnosticLevel.info,
        scope: 'APP_LIFECYCLE',
        event: 'app_lifecycle_changed',
      );
      final sessionFlow = DiagnosticEvent(
        timestamp: DateTime.utc(2026, 9, 8),
        level: DiagnosticLevel.info,
        scope: 'SESSION_FLOW',
        event: 'session_open_requested',
      );

      expect(
        lifecycle.formatLine(),
        startsWith('【AIPIN联调】【应用生命周期】【信息】【阶段：未分阶段】【动作：应用生命周期变更】 '),
      );
      expect(lifecycle.formatLine(), contains(' | INFO | APP_LIFECYCLE | '));
      expect(
        sessionFlow.formatLine(),
        startsWith('【AIPIN联调】【会话流程】【信息】【阶段：未分阶段】【动作：会话打开请求】 '),
      );
      expect(sessionFlow.formatLine(), contains(' | INFO | SESSION_FLOW | '));
    },
  );

  test('EVT command logs show the packet direction in Chinese', () {
    final transmit = DiagnosticEvent(
      timestamp: DateTime.utc(2026, 9, 8),
      level: DiagnosticLevel.info,
      scope: 'CMD',
      stage: 'write',
      event: 'evt_command_transmit_completed',
    );
    final receive = DiagnosticEvent(
      timestamp: DateTime.utc(2026, 9, 8),
      level: DiagnosticLevel.info,
      scope: 'CMD',
      stage: 'response',
      event: 'evt_command_response_matched',
    );
    final timeout = DiagnosticEvent(
      timestamp: DateTime.utc(2026, 9, 8),
      level: DiagnosticLevel.warning,
      scope: 'CMD',
      stage: 'response',
      event: 'evt_command_timeout',
    );

    expect(transmit.formatLine(), startsWith('【AIPIN联调】【协议】【发送：App到设备】'));
    expect(receive.formatLine(), startsWith('【AIPIN联调】【协议】【接收：设备到App】'));
    expect(timeout.formatLine(), startsWith('【AIPIN联调】【协议】【等待：设备响应】'));
  });

  test('physical BLE packet logs show the packet direction in Chinese', () {
    final write = DiagnosticEvent(
      timestamp: DateTime.utc(2026, 9, 8),
      level: DiagnosticLevel.info,
      scope: 'BLE',
      stage: 'write',
      event: 'write_requested',
    );
    final notification = DiagnosticEvent(
      timestamp: DateTime.utc(2026, 9, 8),
      level: DiagnosticLevel.info,
      scope: 'BLE',
      stage: 'connected',
      event: 'notification_received',
    );

    expect(write.formatLine(), startsWith('【AIPIN联调】【蓝牙】【发送：App到设备】'));
    expect(notification.formatLine(), startsWith('【AIPIN联调】【蓝牙】【接收：设备到App】'));
  });

  test(
    'persistent logger forwards its console line and event to the shared log store',
    () {
      final store = _FakeAppLogStore();
      final messages = <String>[];
      final previous = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message != null) {
          messages.add(message);
        }
      };
      addTearDown(() => debugPrint = previous);

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
      expect(messages, hasLength(1));
      expect(
        messages.single,
        startsWith('【AIPIN联调】【应用】【错误】【阶段：蓝牙连接】【动作：连接更新】 '),
      );
      expect(messages.single, contains('connection_update'));
      expect(messages.single, isNot(contains('must-not-leak')));
    },
  );
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
  PublicDiagnosticLogMirrorStatus? get publicMirrorStatus => null;

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
  Future<String?> createUploadSnapshot() async => null;

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
