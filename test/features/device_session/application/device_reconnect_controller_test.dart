import 'dart:async';

import 'package:aipin/core/diagnostics/diagnostic_trace.dart';
import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/features/device_discovery/domain/device_candidate.dart';
import 'package:aipin/features/device_session/application/device_reconnect_controller.dart';
import 'package:aipin/features/device_session/application/device_reconnect_state.dart';
import 'package:aipin/features/device_session/domain/device_connection_history_repository.dart';
import 'package:aipin/features/device_session/domain/remembered_device.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final connectedAt = DateTime.utc(2026, 9, 4, 10);

  DeviceCandidate candidateFor({
    String connectionId = 'android-transport-id',
    String name = 'AIPIN',
    List<int> manufacturerData = const <int>[
      0xA3,
      0x89,
      0xAA,
      0xBB,
      0xCC,
      0xDD,
      0xEE,
      0xFF,
    ],
  }) {
    return DeviceCandidate(
      connectionId: connectionId,
      name: name,
      manufacturerData: manufacturerData,
      serviceUuids: const <String>[],
      rssi: -55,
      discoveredAt: connectedAt,
    );
  }

  RememberedDevice rememberedFor({
    String connectionId = 'android-transport-id',
    String? physicalMacAddress = 'AA:BB:CC:DD:EE:FF',
  }) {
    return RememberedDevice(
      connectionId: connectionId,
      physicalMacAddress: physicalMacAddress,
      displayName: 'AIPIN',
      lastConnectedAt: connectedAt,
    );
  }

  test('matches a remembered MAC record with one candidate only', () async {
    final history = _InMemoryHistory(<RememberedDevice>[rememberedFor()]);
    final logger = _CapturingLogger();
    final connected = <DeviceCandidate>[];
    var startScanCalls = 0;
    var stopScanCalls = 0;
    final controller = DeviceReconnectController(
      history: history,
      startScan: () async {
        startScanCalls += 1;
      },
      stopScan: () async {
        stopScanCalls += 1;
      },
      connect: (candidate) async {
        connected.add(candidate);
        return true;
      },
      logger: logger,
      waitForRetry: (_) async {},
      now: () => connectedAt,
    );
    addTearDown(controller.dispose);

    await controller.restoreAndStart();
    await controller.considerCandidate(
      candidateFor(
        connectionId: 'different-platform-id',
        manufacturerData: const <int>[
          0xA3,
          0x89,
          0x00,
          0x11,
          0x22,
          0x33,
          0x44,
          0x55,
        ],
      ),
    );
    await controller.considerCandidate(
      candidateFor(connectionId: 'different-platform-id'),
    );

    expect(startScanCalls, 1);
    expect(stopScanCalls, 1);
    expect(connected, hasLength(1));
    expect(controller.state.phase, DeviceReconnectPhase.connected);
  });

  test(
    'does not duplicate an in-flight connection for the same candidate',
    () async {
      final connectorGate = Completer<bool>();
      var connectCalls = 0;
      var stopScanCalls = 0;
      final controller = DeviceReconnectController(
        history: _InMemoryHistory(<RememberedDevice>[rememberedFor()]),
        startScan: () async {},
        stopScan: () async {
          stopScanCalls += 1;
        },
        connect: (_) {
          connectCalls += 1;
          return connectorGate.future;
        },
        logger: _CapturingLogger(),
        waitForRetry: (_) async {},
      );
      addTearDown(controller.dispose);

      await controller.restoreAndStart();
      final first = controller.considerCandidate(candidateFor());
      final duplicate = controller.considerCandidate(candidateFor());
      await _drainMicrotasks();

      expect(connectCalls, 1);
      expect(stopScanCalls, 1);
      connectorGate.complete(true);
      await Future.wait<void>(<Future<void>>[first, duplicate]);
      expect(controller.state.phase, DeviceReconnectPhase.connected);
    },
  );

  test(
    'retries at one and two seconds then exhausts after attempt three',
    () async {
      final delays = _DelayGate();
      final results = <bool>[false, false, false];
      var connectCalls = 0;
      final controller = DeviceReconnectController(
        history: _InMemoryHistory(<RememberedDevice>[rememberedFor()]),
        startScan: () async {},
        stopScan: () async {},
        connect: (_) async {
          connectCalls += 1;
          return results.removeAt(0);
        },
        logger: _CapturingLogger(),
        waitForRetry: delays.wait,
      );
      addTearDown(controller.dispose);

      await controller.startExplicitCycle();
      await controller.considerCandidate(candidateFor());
      expect(controller.state.phase, DeviceReconnectPhase.waitingToRetry);
      expect(controller.state.attempt, 1);
      expect(delays.durations, <Duration>[const Duration(seconds: 1)]);

      delays.releaseNext();
      await _drainMicrotasks();
      expect(controller.state.phase, DeviceReconnectPhase.scanning);
      await controller.considerCandidate(candidateFor());
      expect(controller.state.phase, DeviceReconnectPhase.waitingToRetry);
      expect(controller.state.attempt, 2);
      expect(delays.durations, <Duration>[
        const Duration(seconds: 1),
        const Duration(seconds: 2),
      ]);

      delays.releaseNext();
      await _drainMicrotasks();
      await controller.considerCandidate(candidateFor());

      expect(connectCalls, 3);
      expect(controller.state.phase, DeviceReconnectPhase.exhausted);
      expect(controller.state.attempt, 3);
      expect(controller.state.canRetry, isTrue);
    },
  );

  test(
    'suppression prevents an outstanding retry from starting a scan',
    () async {
      final delays = _DelayGate();
      var scanCalls = 0;
      final controller = DeviceReconnectController(
        history: _InMemoryHistory(<RememberedDevice>[rememberedFor()]),
        startScan: () async {
          scanCalls += 1;
        },
        stopScan: () async {},
        connect: (_) async => false,
        logger: _CapturingLogger(),
        waitForRetry: delays.wait,
      );
      addTearDown(controller.dispose);

      await controller.restoreAndStart();
      await controller.considerCandidate(candidateFor());
      expect(controller.state.phase, DeviceReconnectPhase.waitingToRetry);
      await controller.suppressForForeground();
      delays.releaseNext();
      await _drainMicrotasks();

      expect(scanCalls, 1);
      expect(controller.state.phase, DeviceReconnectPhase.suppressed);
    },
  );

  test(
    'an explicit cycle clears foreground suppression and resets attempts',
    () async {
      var scanCalls = 0;
      final controller = DeviceReconnectController(
        history: _InMemoryHistory(<RememberedDevice>[rememberedFor()]),
        startScan: () async {
          scanCalls += 1;
        },
        stopScan: () async {},
        connect: (_) async => true,
        logger: _CapturingLogger(),
        waitForRetry: (_) async {},
      );
      addTearDown(controller.dispose);

      await controller.restoreAndStart();
      await controller.suppressForForeground();
      expect(controller.state.phase, DeviceReconnectPhase.suppressed);

      await controller.startExplicitCycle();

      expect(scanCalls, 2);
      expect(controller.state.phase, DeviceReconnectPhase.scanning);
      expect(controller.state.attempt, 0);
    },
  );

  test(
    'a background pause stops scanning and a foreground restore can scan',
    () async {
      var scanCalls = 0;
      var stopScanCalls = 0;
      final controller = DeviceReconnectController(
        history: _InMemoryHistory(<RememberedDevice>[rememberedFor()]),
        startScan: () async {
          scanCalls += 1;
        },
        stopScan: () async {
          stopScanCalls += 1;
        },
        connect: (_) async => true,
        logger: _CapturingLogger(),
        waitForRetry: (_) async {},
      );
      addTearDown(controller.dispose);

      await controller.restoreAndStart();
      await controller.pauseForBackground();

      expect(stopScanCalls, 1);
      expect(controller.state.phase, DeviceReconnectPhase.idle);

      await controller.restoreAndStart();

      expect(scanCalls, 2);
      expect(controller.state.phase, DeviceReconnectPhase.scanning);
    },
  );

  test(
    'persists a successful connection then removes it after a clear',
    () async {
      final history = _InMemoryHistory();
      final controller = DeviceReconnectController(
        history: history,
        startScan: () async {},
        stopScan: () async {},
        connect: (_) async => true,
        logger: _CapturingLogger(),
        waitForRetry: (_) async {},
        now: () => connectedAt,
      );
      addTearDown(controller.dispose);

      final candidate = candidateFor();
      await controller.rememberSuccessfulConnection(candidate);
      final stored = await history.load();
      expect(stored, hasLength(1));
      expect(stored.single.connectionId, 'android-transport-id');
      expect(stored.single.physicalMacAddress, 'AA:BB:CC:DD:EE:FF');

      await controller.forgetSuccessfulClear(candidate);
      expect(await history.load(), isEmpty);
      expect(controller.state.rememberedDevice, isNull);
    },
  );

  test('a stale retry completion cannot restart a newer cycle', () async {
    final delays = _DelayGate();
    var scanCalls = 0;
    final controller = DeviceReconnectController(
      history: _InMemoryHistory(<RememberedDevice>[rememberedFor()]),
      startScan: () async {
        scanCalls += 1;
      },
      stopScan: () async {},
      connect: (_) async => false,
      logger: _CapturingLogger(),
      waitForRetry: delays.wait,
    );
    addTearDown(controller.dispose);

    await controller.restoreAndStart();
    await controller.considerCandidate(candidateFor());
    expect(controller.state.phase, DeviceReconnectPhase.waitingToRetry);
    await controller.startExplicitCycle();
    expect(scanCalls, 2);

    delays.releaseNext();
    await _drainMicrotasks();

    expect(scanCalls, 2);
    expect(controller.state.phase, DeviceReconnectPhase.scanning);
    expect(controller.state.attempt, 0);
  });

  test('reconnect diagnostics omit raw candidate identities', () async {
    const rawConnectionId = 'android-raw-connection-id';
    const rawName = 'AIPIN sensitive display name';
    const rawMacAddress = 'AA:BB:CC:DD:EE:FF';
    const rawExceptionText =
        'transport packet failed for android-raw-connection-id';
    final logger = _CapturingLogger();
    final controller = DeviceReconnectController(
      history: _InMemoryHistory(<RememberedDevice>[
        rememberedFor(connectionId: rawConnectionId),
      ]),
      startScan: () async {},
      stopScan: () async {},
      connect: (_) async => throw StateError(rawExceptionText),
      logger: logger,
      waitForRetry: (_) async {},
    );
    addTearDown(controller.dispose);

    await controller.restoreAndStart();
    await controller.considerCandidate(
      candidateFor(connectionId: rawConnectionId, name: rawName),
    );

    final diagnosticText = logger.calls
        .map(
          (call) => <Object?>[
            call.event,
            call.operation,
            call.stage,
            call.result,
            call.fields,
          ].join('|'),
        )
        .join('\n');
    expect(diagnosticText, isNot(contains(rawConnectionId)));
    expect(diagnosticText, isNot(contains(rawName)));
    expect(diagnosticText, isNot(contains(rawMacAddress)));
    expect(diagnosticText, isNot(contains(rawExceptionText)));
  });
}

Future<void> _drainMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _DelayGate {
  final List<Duration> durations = <Duration>[];
  final List<Completer<void>> _waiters = <Completer<void>>[];

  Future<void> wait(Duration duration) {
    durations.add(duration);
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void releaseNext() {
    final next = _waiters.firstWhere((item) => !item.isCompleted);
    next.complete();
  }
}

class _InMemoryHistory implements DeviceConnectionHistoryRepository {
  _InMemoryHistory([
    Iterable<RememberedDevice> values = const <RememberedDevice>[],
  ]) : _values = List<RememberedDevice>.of(values);

  final List<RememberedDevice> _values;

  @override
  Future<List<RememberedDevice>> load() async =>
      List<RememberedDevice>.unmodifiable(_values);

  @override
  Future<void> removeMatching({
    required String connectionId,
    String? physicalMacAddress,
  }) async {
    _values.removeWhere((record) {
      if (record.physicalMacAddress != null && physicalMacAddress != null) {
        return record.physicalMacAddress == physicalMacAddress;
      }
      return record.connectionId == connectionId;
    });
  }

  @override
  Future<void> upsert(RememberedDevice record) async {
    await removeMatching(
      connectionId: record.connectionId,
      physicalMacAddress: record.physicalMacAddress,
    );
    _values.add(record);
  }
}

class _DiagnosticCall {
  const _DiagnosticCall({
    required this.event,
    required this.operation,
    required this.stage,
    required this.result,
    required this.fields,
  });

  final String event;
  final String? operation;
  final String? stage;
  final String? result;
  final Map<String, Object?> fields;
}

class _CapturingLogger implements SafeAppLogger {
  final List<_DiagnosticCall> calls = <_DiagnosticCall>[];

  @override
  void error(
    String event, {
    DiagnosticTrace? trace,
    String? operation,
    String? stage,
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    _record(event, operation, stage, result, fields);
  }

  @override
  void info(
    String event, {
    DiagnosticTrace? trace,
    String? operation,
    String? stage,
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    _record(event, operation, stage, result, fields);
  }

  @override
  void warning(
    String event, {
    DiagnosticTrace? trace,
    String? operation,
    String? stage,
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    _record(event, operation, stage, result, fields);
  }

  void _record(
    String event,
    String? operation,
    String? stage,
    String? result,
    Map<String, Object?> fields,
  ) {
    calls.add(
      _DiagnosticCall(
        event: event,
        operation: operation,
        stage: stage,
        result: result,
        fields: Map<String, Object?>.unmodifiable(fields),
      ),
    );
  }
}
