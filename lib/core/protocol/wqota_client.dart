import 'dart:async';
import 'dart:typed_data';

import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/ble/ble_transport.dart';
import 'package:aipin/core/diagnostics/safe_app_logger.dart';

import 'wqota_codec.dart';

/// Standard BLE expansion of the V1.6 WQOTA 16-bit service and
/// characteristics. These values remain separate from the business GATT
/// profile so callers cannot accidentally submit WQOTA frames to FAxx/FFxx.
abstract final class WqotaGatt {
  static const serviceUuid = '00007033-0000-1000-8000-00805F9B34FB';
  static const writeCharacteristicUuid = '00002001-0000-1000-8000-00805F9B34FB';
  static const notifyCharacteristicUuid =
      '00002002-0000-1000-8000-00805F9B34FB';

  static BleCharacteristic writeCharacteristic(String deviceId) =>
      BleCharacteristic(
        deviceId: deviceId,
        serviceUuid: serviceUuid,
        characteristicUuid: writeCharacteristicUuid,
      );

  static BleCharacteristic notifyCharacteristic(String deviceId) =>
      BleCharacteristic(
        deviceId: deviceId,
        serviceUuid: serviceUuid,
        characteristicUuid: notifyCharacteristicUuid,
      );
}

/// Raised when no valid WQOTA frame has arrived during the V1.6 12-second
/// transport activity window.
class WqotaIdleTimeoutException implements Exception {
  const WqotaIdleTimeoutException({required this.opcode, required this.serial});

  final WqotaOpcode opcode;
  final int serial;

  @override
  String toString() =>
      'WqotaIdleTimeoutException(opcode=0x${opcode.value.toRadixString(16)}, serial=$serial)';
}

typedef WqotaWriteAdmission = void Function();

/// A single, cancellable WQOTA response wait.
///
/// E5 registers its window-response wait before issuing Write Without
/// Response blocks. If a native write fails before the final block reaches the
/// peripheral, the caller must cancel this handle so the abandoned wait cannot
/// later emit an unrelated idle-timeout error.
class WqotaNotificationWait {
  WqotaNotificationWait._({required this.future, required this._onCancel});

  final Future<WqotaFrame> future;
  final void Function({Object? error, StackTrace? stackTrace}) _onCancel;

  /// Stops this wait. Repeated cancellation is safe.
  void cancel({Object? error, StackTrace? stackTrace}) =>
      _onCancel(error: error, stackTrace: stackTrace);
}

/// Owns the standalone WQOTA 0x7033/0x2001/0x2002 transport.
///
/// The caller is responsible for verifying that the current BLE connection
/// completed V1.6 Action=00 authentication before calling [open]. The firmware
/// must independently enforce the same rule; this client is intentionally not
/// a substitute for that device-side gate.
class WqotaClient {
  WqotaClient({
    required this._transport,
    required this._writeCharacteristic,
    required Stream<Uint8List> notifications,
    required this._codec,
    this.idleTimeout = const Duration(seconds: 12),
    this._beforeWrite,
    SafeAppLogger? logger,
  }) : _logger = logger ?? const DebugSafeAppLogger(scope: 'CMD') {
    if (idleTimeout <= Duration.zero) {
      throw ArgumentError.value(
        idleTimeout,
        'idleTimeout',
        'Must be positive.',
      );
    }
    _subscription = notifications.listen(
      _onBytes,
      onError: _onError,
      onDone: _onDone,
    );
  }

  /// Starts the Notify subscription and waits for the platform to finish
  /// enabling the 0x2002 CCC before exposing the client for writes.
  static Future<WqotaClient> open({
    required BleTransport transport,
    required BleCharacteristic writeCharacteristic,
    required BleCharacteristic notifyCharacteristic,
    required WqotaCodec codec,
    Duration idleTimeout = const Duration(seconds: 12),
    Duration cccTimeout = const Duration(seconds: 8),
    WqotaWriteAdmission? beforeWrite,
    SafeAppLogger? logger,
  }) async {
    if (cccTimeout <= Duration.zero) {
      throw ArgumentError.value(cccTimeout, 'cccTimeout', 'Must be positive.');
    }
    final client = WqotaClient(
      transport: transport,
      writeCharacteristic: writeCharacteristic,
      notifications: transport.subscribe(notifyCharacteristic),
      codec: codec,
      idleTimeout: idleTimeout,
      beforeWrite: beforeWrite,
      logger: logger,
    );
    try {
      client._logInfo(
        'wqota_ccc_wait_started',
        stage: 'connected',
        result: 'pending',
        fields: <String, Object?>{
          'reason': '【DVT OTA】【通知订阅】等待 0x2002 Notify 的 CCC 就绪',
          'timeout_ms': cccTimeout.inMilliseconds,
          'state': 'ccc_waiting',
        },
      );
      await transport
          .awaitSubscriptionReady(notifyCharacteristic)
          .timeout(cccTimeout);
      client._ensureOpen();
      client._logInfo(
        'wqota_ccc_ready',
        stage: 'connected',
        result: 'success',
        fields: const <String, Object?>{
          'reason': '【DVT OTA】【通知订阅】0x2002 CCC 已就绪，可以发送 WQOTA',
          'state': 'listening',
        },
      );
      return client;
    } on TimeoutException {
      client._logWarning(
        'wqota_ccc_timeout',
        stage: 'connected',
        result: 'failed',
        fields: <String, Object?>{
          'reason': '【DVT OTA】【通知订阅】等待 0x2002 CCC 超时，禁止发送升级包',
          'timeout_ms': cccTimeout.inMilliseconds,
          'state': 'ccc_timeout',
        },
      );
      await client.close();
      rethrow;
    } catch (_) {
      client._logWarning(
        'wqota_ccc_failed',
        stage: 'connected',
        result: 'failed',
        fields: const <String, Object?>{
          'reason': '【DVT OTA】【通知订阅】0x2002 CCC 未能就绪，禁止发送升级包',
          'state': 'ccc_failed',
        },
      );
      await client.close();
      rethrow;
    }
  }

  final BleTransport _transport;
  final BleCharacteristic _writeCharacteristic;
  final WqotaCodec _codec;
  final WqotaWriteAdmission? _beforeWrite;
  final SafeAppLogger _logger;
  final Duration idleTimeout;
  final StreamController<WqotaFrame> _events =
      StreamController<WqotaFrame>.broadcast();
  StreamSubscription<Uint8List>? _subscription;
  _PendingWqota? _pending;
  final List<_PendingWqota> _notificationWaiters = <_PendingWqota>[];
  Future<void> _queue = Future<void>.value();
  bool _closed = false;
  Object? _terminalError;
  StackTrace? _terminalStackTrace;

  Stream<WqotaFrame> get events => _events.stream;

  /// Writes one complete WQOTA logical frame to 0x2001. It is intentionally
  /// not split: V1.6 firmware does not reassemble a frame across BLE writes.
  Future<void> sendWithoutResponse({
    required WqotaOpcode opcode,
    required List<int> data,
  }) async {
    _ensureOpen();
    await _write(opcode: opcode, data: data);
  }

  /// Waits for the WQOTA response that echoes [serialNumber]. The idle timer
  /// resets on every valid WQOTA frame, matching the V1.6 activity rule.
  WqotaNotificationWait waitForNotification({
    required WqotaOpcode opcode,
    required int serialNumber,
  }) {
    _ensureOpen();
    _validateSerial(serialNumber);
    final pending = _PendingWqota(
      opcode: opcode,
      serialNumber: serialNumber,
      idleTimeout: idleTimeout,
      onTimeout: _logWaitTimeout,
    );
    _notificationWaiters.add(pending);
    pending.start();
    _logInfo(
      'wqota_wait_registered',
      stage: 'response',
      result: 'pending',
      fields: <String, Object?>{
        'reason': '【DVT OTA】【回包监听】已登记 WQOTA 回包等待',
        'command': _opcodeHex(opcode),
        'timeout_ms': idleTimeout.inMilliseconds,
        'state': 'waiting',
      },
    );
    final response = pending.future.whenComplete(() {
      _notificationWaiters.remove(pending);
      pending.dispose();
    });
    _observeResponse(response);
    return WqotaNotificationWait._(
      future: response,
      onCancel: ({Object? error, StackTrace? stackTrace}) {
        if (pending.isCompleted) {
          return;
        }
        _logInfo(
          'wqota_wait_cancelled',
          stage: 'response',
          result: 'cancelled',
          fields: <String, Object?>{
            'reason': '【DVT OTA】【回包监听】发送未完成，已取消无效的 WQOTA 回包等待',
            'command': _opcodeHex(opcode),
            'state': 'cancelled',
          },
        );
        pending.completeError(
          error ?? StateError('WQOTA response wait was cancelled.'),
          stackTrace ?? StackTrace.current,
        );
      },
    );
  }

  /// Executes commands that require an immediate matching response. Calls are
  /// serialized so a response cannot be associated with the wrong command.
  Future<WqotaFrame> execute({
    required WqotaOpcode opcode,
    required List<int> data,
    required int serialNumber,
  }) {
    _ensureOpen();
    _validateSerial(serialNumber);
    final result = _queue.then((_) => _run(opcode, data, serialNumber));
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<WqotaFrame> _run(
    WqotaOpcode opcode,
    List<int> data,
    int serialNumber,
  ) async {
    _ensureOpen();
    final pending = _PendingWqota(
      opcode: opcode,
      serialNumber: serialNumber,
      idleTimeout: idleTimeout,
      onTimeout: _logWaitTimeout,
    );
    _pending = pending;
    pending.start();
    _observeResponse(pending.future);
    try {
      await _write(opcode: opcode, data: data);
      return await pending.future;
    } finally {
      if (identical(_pending, pending)) {
        _pending = null;
      }
      pending.dispose();
    }
  }

  void _onBytes(Uint8List bytes) {
    if (_closed || _terminalError != null) {
      return;
    }
    _logInfo(
      'wqota_rx_raw',
      stage: 'response',
      result: 'pending',
      fields: <String, Object?>{
        'reason': '【DVT OTA】【接收原始数据】收到 0x2002 Notify 原始字节',
        'raw_packet_hex': _hex(bytes),
        'bytes': bytes.length,
        'state': 'received',
      },
    );
    WqotaFrame frame;
    try {
      frame = _codec.decode(bytes);
    } on FormatException {
      _logWarning(
        'wqota_rx_rejected',
        stage: 'response',
        result: 'failed',
        fields: <String, Object?>{
          'reason': '【DVT OTA】【接收校验】帧前缀、长度、后缀或 opcode 不符合 WQOTA',
          'raw_packet_hex': _hex(bytes),
          'bytes': bytes.length,
          'state': 'rejected',
        },
      );
      return;
    }

    // Any complete, correctly delimited WQOTA frame shows that the selected
    // transport is active. It restarts all in-flight WQOTA idle timers.
    _pending?.resetIdleTimeout();
    for (final waiter in List<_PendingWqota>.of(_notificationWaiters)) {
      waiter.resetIdleTimeout();
    }
    _logInfo(
      'wqota_rx_valid',
      stage: 'response',
      result: 'pending',
      fields: <String, Object?>{
        'reason': '【DVT OTA】【回包监听】收到有效 WQOTA 帧，12 秒活动计时已重置',
        'command': _opcodeHex(frame.opcode),
        'bytes': bytes.length,
        'state': 'activity_reset',
      },
    );

    final pending = _pending;
    if (pending != null && pending.matches(frame)) {
      pending.complete(frame);
      _logMatched(frame);
      return;
    }
    for (final waiter in List<_PendingWqota>.of(_notificationWaiters)) {
      if (waiter.matches(frame)) {
        waiter.complete(frame);
        _logMatched(frame);
        return;
      }
    }
    _logInfo(
      'wqota_rx_unmatched',
      stage: 'response',
      result: 'pending',
      fields: <String, Object?>{
        'reason': '【DVT OTA】【回包监听】收到有效帧，但没有匹配当前 opcode/SN 等待项',
        'command': _opcodeHex(frame.opcode),
        'state': 'unmatched',
      },
    );
    if (!_events.isClosed) {
      _events.add(frame);
    }
  }

  void _onError(Object error, StackTrace stackTrace) {
    _terminateFromNotificationStream(
      error,
      stackTrace,
      event: 'wqota_rx_stream_failed',
      reason: '【DVT OTA】【回包监听】0x2002 Notify 流异常，升级等待已中断',
      state: 'stream_failed',
    );
  }

  void _onDone() {
    if (_closed) {
      return;
    }
    _terminateFromNotificationStream(
      StateError('WQOTA notification stream closed unexpectedly.'),
      StackTrace.current,
      event: 'wqota_rx_stream_closed',
      reason: '【DVT OTA】【回包监听】0x2002 Notify 流意外结束，禁止继续发送升级数据',
      state: 'stream_closed',
    );
  }

  void _terminateFromNotificationStream(
    Object error,
    StackTrace stackTrace, {
    required String event,
    required String reason,
    required String state,
  }) {
    if (_closed || _terminalError != null) {
      return;
    }
    _terminalError = error;
    _terminalStackTrace = stackTrace;
    _logWarning(
      event,
      stage: 'response',
      result: 'failed',
      fields: <String, Object?>{'reason': reason, 'state': state},
    );
    _pending?.completeError(error, stackTrace);
    for (final waiter in List<_PendingWqota>.of(_notificationWaiters)) {
      waiter.completeError(error, stackTrace);
    }
    final subscription = _subscription;
    if (subscription != null) {
      unawaited(
        subscription.cancel().then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        ),
      );
    }
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _logInfo(
      'wqota_client_closed',
      stage: 'idle',
      result: 'cancelled',
      fields: const <String, Object?>{
        'reason': '【DVT OTA】WQOTA 客户端已关闭，所有回包等待已取消',
        'state': 'closed',
      },
    );
    final closeError = StateError('WQOTA client has closed.');
    _pending?.completeError(closeError);
    for (final waiter in List<_PendingWqota>.of(_notificationWaiters)) {
      waiter.completeError(closeError);
    }
    _notificationWaiters.clear();
    await _subscription?.cancel();
    await _events.close();
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('WQOTA client has closed.');
    }
    final terminalError = _terminalError;
    if (terminalError == null) {
      return;
    }
    final terminalStackTrace = _terminalStackTrace;
    if (terminalStackTrace != null) {
      Error.throwWithStackTrace(terminalError, terminalStackTrace);
    }
    throw terminalError;
  }

  static void _validateSerial(int serialNumber) {
    if (serialNumber < 0 || serialNumber > 0xFF) {
      throw RangeError.range(serialNumber, 0, 0xFF, 'serialNumber');
    }
  }

  Future<void> _write({
    required WqotaOpcode opcode,
    required List<int> data,
  }) async {
    final bytes = _codec.encode(opcode: opcode, data: data);
    _logInfo(
      'wqota_tx_prepared',
      stage: 'write',
      result: 'pending',
      fields: <String, Object?>{
        'reason': '【DVT OTA】【发送原始数据】已组装单次 0x2001 Write Without Response 帧',
        'command': _opcodeHex(opcode),
        'raw_packet_hex': _hex(bytes),
        'bytes': bytes.length,
        'state': 'prepared',
      },
    );
    try {
      // This remains immediately adjacent to the native write: the Session
      // callback rechecks the exact connection and Action=00 state each time.
      _beforeWrite?.call();
    } catch (_) {
      _logWarning(
        'wqota_tx_blocked',
        stage: 'write',
        result: 'failed',
        fields: <String, Object?>{
          'reason': '【DVT OTA】【发送前检查】连接或认证状态不再满足，阻止本次写入',
          'command': _opcodeHex(opcode),
          'raw_packet_hex': _hex(bytes),
          'state': 'admission_blocked',
        },
      );
      rethrow;
    }
    await _transport.writeWithoutResponse(_writeCharacteristic, bytes);
    _logInfo(
      'wqota_tx_submitted',
      stage: 'write',
      result: 'success',
      fields: <String, Object?>{
        'reason': '【DVT OTA】【发送完成】原生层已接受本次单帧写入，继续等待设备回包',
        'command': _opcodeHex(opcode),
        'raw_packet_hex': _hex(bytes),
        'bytes': bytes.length,
        'state': 'submitted',
      },
    );
    _ensureOpen();
  }

  /// A pending completer can fail while a platform write is still pending.
  /// Attach a no-op error observer now; the original future is still awaited
  /// below and therefore continues to propagate its error to the caller.
  static void _observeResponse(Future<WqotaFrame> response) {
    unawaited(
      response.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }

  void _logMatched(WqotaFrame frame) {
    _logInfo(
      'wqota_response_matched',
      stage: 'response',
      result: 'success',
      fields: <String, Object?>{
        'reason': '【DVT OTA】【回包匹配】opcode 与 SN 匹配，结束对应等待',
        'command': _opcodeHex(frame.opcode),
        'bytes': frame.data.length,
        'state': 'matched',
      },
    );
  }

  void _logWaitTimeout(WqotaOpcode opcode, int serial) {
    _logWarning(
      'wqota_wait_timeout',
      stage: 'response',
      result: 'failed',
      fields: <String, Object?>{
        'reason': '【DVT OTA】【回包超时】12 秒内未收到有效 WQOTA 帧，保留断点等待恢复',
        'command': _opcodeHex(opcode),
        'timeout_ms': idleTimeout.inMilliseconds,
        'state': 'timeout',
      },
    );
  }

  void _logInfo(
    String event, {
    String? stage,
    String? result,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    try {
      _logger.info(event, stage: stage, result: result, fields: fields);
    } on Object {
      // Diagnostics are best effort and must not change BLE behavior.
    }
  }

  void _logWarning(
    String event, {
    String? stage,
    String? result,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    try {
      _logger.warning(event, stage: stage, result: result, fields: fields);
    } on Object {
      // Diagnostics are best effort and must not change BLE behavior.
    }
  }

  static String _opcodeHex(WqotaOpcode opcode) =>
      '0x${opcode.value.toRadixString(16).padLeft(2, '0').toUpperCase()}';

  static String _hex(List<int> bytes) => bytes.isEmpty
      ? 'empty'
      : bytes
            .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
            .join(' ');
}

class _PendingWqota {
  _PendingWqota({
    required this.opcode,
    required this.serialNumber,
    required this.idleTimeout,
    required this.onTimeout,
  });

  final WqotaOpcode opcode;
  final int serialNumber;
  final Duration idleTimeout;
  final void Function(WqotaOpcode opcode, int serial) onTimeout;
  final Completer<WqotaFrame> _completer = Completer<WqotaFrame>();
  Timer? _idleTimer;

  Future<WqotaFrame> get future => _completer.future;

  bool get isCompleted => _completer.isCompleted;

  bool matches(WqotaFrame frame) =>
      frame.opcode == opcode &&
      frame.data.length >= 2 &&
      frame.data[1] == serialNumber;

  void start() => resetIdleTimeout();

  void resetIdleTimeout() {
    if (_completer.isCompleted) {
      return;
    }
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, () {
      onTimeout(opcode, serialNumber);
      completeError(
        WqotaIdleTimeoutException(opcode: opcode, serial: serialNumber),
      );
    });
  }

  void complete(WqotaFrame frame) {
    if (!_completer.isCompleted) {
      _completer.complete(frame);
    }
  }

  void completeError(Object error, [StackTrace? stackTrace]) {
    if (!_completer.isCompleted) {
      _completer.completeError(error, stackTrace);
    }
  }

  void dispose() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }
}
