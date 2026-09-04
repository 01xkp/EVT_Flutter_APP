import 'dart:async';

import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/features/device_discovery/domain/device_candidate.dart';
import 'package:aipin/features/device_session/application/device_reconnect_state.dart';
import 'package:aipin/features/device_session/domain/device_connection_history_repository.dart';
import 'package:aipin/features/device_session/domain/remembered_device.dart';
import 'package:flutter/foundation.dart';

/// Coordinates bounded reconnection after a foreground scan finds a private
/// remembered-device record. The existing session owner remains responsible
/// for GATT setup and reports success through the [connect] callback.
class DeviceReconnectController extends ChangeNotifier {
  factory DeviceReconnectController({
    required DeviceConnectionHistoryRepository history,
    required Future<void> Function() startScan,
    required Future<void> Function() stopScan,
    required Future<bool> Function(DeviceCandidate candidate) connect,
    required SafeAppLogger logger,
    Future<void> Function(Duration duration)? waitForRetry,
    DateTime Function()? now,
  }) {
    return DeviceReconnectController._(
      history,
      startScan,
      stopScan,
      connect,
      logger,
      waitForRetry ?? Future<void>.delayed,
      now ?? DateTime.now,
    );
  }

  DeviceReconnectController._(
    this._history,
    this._startScan,
    this._stopScan,
    this._connect,
    this._logger,
    this._waitForRetry,
    this._now,
  );

  static const _maximumAttempts = 3;
  static const _firstRetryDelay = Duration(seconds: 1);
  static const _secondRetryDelay = Duration(seconds: 2);

  final DeviceConnectionHistoryRepository _history;
  final Future<void> Function() _startScan;
  final Future<void> Function() _stopScan;
  final Future<bool> Function(DeviceCandidate candidate) _connect;
  final SafeAppLogger _logger;
  final Future<void> Function(Duration duration) _waitForRetry;
  final DateTime Function() _now;

  DeviceReconnectState _state = const DeviceReconnectState();
  Future<void> _scanOperationTail = Future<void>.value();
  int _cycleId = 0;
  bool _suppressedForForeground = false;
  bool _scanMayBeActive = false;
  bool _isDisposed = false;

  DeviceReconnectState get state => _state;

  /// Restore the newest remembered device and begin an automatic scan.
  Future<void> restoreAndStart() => _startCycle(clearSuppression: false);

  /// A user-requested cycle clears foreground-only suppression and retry
  /// history, then waits for a matching foreground scan result.
  Future<void> startExplicitCycle() => _startCycle(clearSuppression: true);

  /// Evaluates one discovered candidate without retaining its raw identifier.
  Future<void> considerCandidate(DeviceCandidate candidate) async {
    final cycle = _cycleId;
    final remembered = _state.rememberedDevice;
    if (!_isActive(cycle) ||
        _suppressedForForeground ||
        _state.phase != DeviceReconnectPhase.scanning ||
        remembered == null ||
        !remembered.matches(candidate)) {
      return;
    }

    final nextAttempt = _state.attempt + 1;
    if (nextAttempt > _maximumAttempts) {
      return;
    }

    _setState(
      _state.copyWith(
        phase: DeviceReconnectPhase.connecting,
        attempt: nextAttempt,
        canRetry: false,
        clearFailureCategory: true,
      ),
    );
    _logInfo('reconnect_candidate_matched', cycle: cycle);

    if (!await _stopScanForCycle(cycle)) {
      if (_isActive(cycle)) {
        _handleAttemptFailure(cycle, 'scan_stop_failed');
      }
      return;
    }
    if (!_isActive(cycle)) {
      return;
    }

    bool connected;
    try {
      connected = await _connect(candidate);
    } catch (_) {
      if (_isActive(cycle)) {
        _handleAttemptFailure(cycle, 'connect_error');
      }
      return;
    }

    if (!_isActive(cycle)) {
      return;
    }
    if (connected) {
      _setState(
        _state.copyWith(
          phase: DeviceReconnectPhase.connected,
          canRetry: false,
          clearFailureCategory: true,
        ),
      );
      _logInfo('reconnect_connected', cycle: cycle);
      return;
    }

    _handleAttemptFailure(cycle, 'connect_rejected');
  }

  /// Starts a fresh automatic cycle after a session drops unexpectedly.
  Future<void> markUnexpectedDisconnect() async {
    if (_isDisposed || _suppressedForForeground) {
      return;
    }
    await _startCycle(clearSuppression: false);
  }

  /// Stops automatic reconnect work until an explicit request or a new
  /// foreground session clears this suppression.
  Future<void> suppressForForeground() async {
    if (_isDisposed) {
      return;
    }
    _suppressedForForeground = true;
    _cycleId += 1;
    await _stopScanSafely();
    if (_isDisposed) {
      return;
    }
    _setState(
      _state.copyWith(
        phase: DeviceReconnectPhase.suppressed,
        canRetry: false,
        clearFailureCategory: true,
      ),
    );
    _logInfo('reconnect_suppressed');
  }

  /// Cancels transient foreground work while the app is backgrounded.
  ///
  /// A subsequent [restoreAndStart] is allowed to reconnect again.
  Future<void> pauseForBackground() async {
    if (_isDisposed) {
      return;
    }
    _cycleId += 1;
    _suppressedForForeground = false;
    await _stopScanSafely();
    if (_isDisposed || _state.phase == DeviceReconnectPhase.connected) {
      return;
    }
    _setState(
      _state.copyWith(
        phase: DeviceReconnectPhase.idle,
        attempt: 0,
        canRetry: false,
        clearFailureCategory: true,
      ),
    );
    _logInfo('reconnect_paused');
  }

  /// Persists a record only for a valid, named candidate after the caller has
  /// confirmed session authentication readiness.
  Future<void> rememberSuccessfulConnection(DeviceCandidate candidate) async {
    if (_isDisposed) {
      return;
    }
    final record = _recordForCandidate(candidate);
    if (record == null) {
      _logWarning('reconnect_history_write_skipped', 'invalid_candidate');
      return;
    }

    try {
      await _history.upsert(record);
    } catch (_) {
      _logWarning('reconnect_history_write_failed', 'history_write_failed');
      return;
    }

    if (_isDisposed) {
      return;
    }
    _setState(_state.copyWith(rememberedDevice: record));
    _logInfo('reconnect_history_written');
  }

  /// Removes the corresponding private record after a successful clear/unbind.
  Future<void> forgetSuccessfulClear(DeviceCandidate candidate) async {
    if (_isDisposed) {
      return;
    }
    final physicalMacAddress = _physicalMacAddressFor(candidate);
    try {
      await _history.removeMatching(
        connectionId: candidate.connectionId,
        physicalMacAddress: physicalMacAddress,
      );
    } catch (_) {
      _logWarning('reconnect_history_remove_failed', 'history_remove_failed');
      return;
    }

    if (_isDisposed) {
      return;
    }
    final remembered = _state.rememberedDevice;
    if (remembered != null && remembered.matches(candidate)) {
      _cycleId += 1;
      await _stopScanSafely();
      if (_isDisposed) {
        return;
      }
      _setState(
        _state.copyWith(
          phase: DeviceReconnectPhase.idle,
          attempt: 0,
          clearRememberedDevice: true,
          canRetry: false,
          clearFailureCategory: true,
        ),
      );
    }
    _logInfo('reconnect_history_removed');
  }

  /// Cancels automatic work when a separate manual connection flow takes over.
  Future<void> cancelAutomaticCycle() async {
    if (_isDisposed) {
      return;
    }
    _cycleId += 1;
    await _stopScanSafely();
    if (_isDisposed || _state.phase == DeviceReconnectPhase.connected) {
      return;
    }
    _setState(
      _state.copyWith(
        phase: DeviceReconnectPhase.idle,
        attempt: 0,
        canRetry: false,
        clearFailureCategory: true,
      ),
    );
    _logInfo('reconnect_cancelled');
  }

  Future<void> _startCycle({required bool clearSuppression}) async {
    if (_isDisposed) {
      return;
    }
    if (clearSuppression) {
      _suppressedForForeground = false;
    }
    final cycle = ++_cycleId;

    await _stopScanSafely();
    if (!_isActive(cycle)) {
      return;
    }
    if (_suppressedForForeground) {
      _setState(
        _state.copyWith(
          phase: DeviceReconnectPhase.suppressed,
          canRetry: false,
          clearFailureCategory: true,
        ),
      );
      return;
    }

    List<RememberedDevice> records;
    try {
      records = await _history.load();
    } catch (_) {
      if (_isActive(cycle)) {
        _setState(
          _state.copyWith(
            phase: DeviceReconnectPhase.idle,
            attempt: 0,
            clearRememberedDevice: true,
            canRetry: true,
            failureCategory: 'history_load_failed',
          ),
        );
        _logWarning('reconnect_history_load_failed', 'history_load_failed');
      }
      return;
    }
    if (!_isActive(cycle)) {
      return;
    }

    final remembered = _mostRecent(records);
    if (remembered == null) {
      _setState(
        _state.copyWith(
          phase: DeviceReconnectPhase.idle,
          attempt: 0,
          clearRememberedDevice: true,
          canRetry: false,
          clearFailureCategory: true,
        ),
      );
      _logInfo('reconnect_history_empty', cycle: cycle);
      return;
    }

    _setState(
      _state.copyWith(
        phase: DeviceReconnectPhase.idle,
        attempt: 0,
        rememberedDevice: remembered,
        canRetry: false,
        clearFailureCategory: true,
      ),
    );
    _logInfo('reconnect_history_loaded', cycle: cycle);
    await _startScanForCycle(cycle);
  }

  RememberedDevice? _mostRecent(List<RememberedDevice> records) {
    if (records.isEmpty) {
      return null;
    }
    return records.reduce(
      (latest, record) => record.lastConnectedAt.isAfter(latest.lastConnectedAt)
          ? record
          : latest,
    );
  }

  Future<void> _startScanForCycle(int cycle) async {
    if (!_isActive(cycle) || _suppressedForForeground) {
      return;
    }
    _setState(
      _state.copyWith(
        phase: DeviceReconnectPhase.scanning,
        canRetry: false,
        clearFailureCategory: true,
      ),
    );

    final started = await _queueScanOperation(() async {
      if (!_isActive(cycle) || _suppressedForForeground) {
        return false;
      }
      _scanMayBeActive = true;
      try {
        await _startScan();
        return true;
      } catch (_) {
        _scanMayBeActive = false;
        return false;
      }
    });
    if (!_isActive(cycle)) {
      return;
    }
    if (started) {
      _logInfo('reconnect_scan_started', cycle: cycle);
      return;
    }
    _setState(
      _state.copyWith(
        phase: DeviceReconnectPhase.idle,
        canRetry: true,
        failureCategory: 'scan_start_failed',
      ),
    );
    _logWarning(
      'reconnect_scan_start_failed',
      'scan_start_failed',
      cycle: cycle,
    );
  }

  Future<bool> _stopScanForCycle(int cycle) async {
    final stopped = await _stopScanSafely();
    return stopped && _isActive(cycle);
  }

  Future<bool> _stopScanSafely() {
    if (!_scanMayBeActive) {
      return Future<bool>.value(true);
    }
    _scanMayBeActive = false;
    return _queueScanOperation(() async {
      try {
        await _stopScan();
        return true;
      } catch (_) {
        _logWarning('reconnect_scan_stop_failed', 'scan_stop_failed');
        return false;
      }
    });
  }

  Future<T> _queueScanOperation<T>(Future<T> Function() operation) {
    final queued = _scanOperationTail.then<T>((_) => operation());
    _scanOperationTail = queued.then<void>((_) {}).catchError((_) {});
    return queued;
  }

  void _handleAttemptFailure(int cycle, String failureCategory) {
    if (!_isActive(cycle)) {
      return;
    }
    final attempt = _state.attempt;
    _logWarning('reconnect_attempt_failed', failureCategory, cycle: cycle);
    if (attempt >= _maximumAttempts) {
      _setState(
        _state.copyWith(
          phase: DeviceReconnectPhase.exhausted,
          canRetry: true,
          failureCategory: failureCategory,
        ),
      );
      _logWarning('reconnect_exhausted', failureCategory, cycle: cycle);
      return;
    }

    final delay = attempt == 1 ? _firstRetryDelay : _secondRetryDelay;
    _setState(
      _state.copyWith(
        phase: DeviceReconnectPhase.waitingToRetry,
        canRetry: false,
        failureCategory: failureCategory,
      ),
    );
    unawaited(_waitThenScan(cycle, delay));
  }

  Future<void> _waitThenScan(int cycle, Duration delay) async {
    try {
      await _waitForRetry(delay);
    } catch (_) {
      if (_isActive(cycle)) {
        _setState(
          _state.copyWith(
            phase: DeviceReconnectPhase.idle,
            canRetry: true,
            failureCategory: 'retry_wait_failed',
          ),
        );
        _logWarning(
          'reconnect_retry_wait_failed',
          'retry_wait_failed',
          cycle: cycle,
        );
      }
      return;
    }
    if (!_isActive(cycle) || _suppressedForForeground) {
      return;
    }
    await _startScanForCycle(cycle);
  }

  RememberedDevice? _recordForCandidate(DeviceCandidate candidate) {
    try {
      return RememberedDevice(
        connectionId: candidate.connectionId,
        physicalMacAddress: _physicalMacAddressFor(candidate),
        displayName: candidate.name,
        lastConnectedAt: _now(),
      );
    } on FormatException {
      return null;
    }
  }

  String? _physicalMacAddressFor(DeviceCandidate candidate) {
    final data = candidate.manufacturerData;
    if (data.length != 8 || data[0] != 0xA3 || data[1] != 0x89) {
      return null;
    }
    return candidate.physicalDeviceId;
  }

  bool _isActive(int cycle) => !_isDisposed && cycle == _cycleId;

  void _setState(DeviceReconnectState next) {
    if (_isDisposed || next == _state) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  void _logInfo(String event, {int? cycle}) {
    _log(event, level: _ReconnectLogLevel.info, cycle: cycle);
  }

  void _logWarning(String event, String failureCategory, {int? cycle}) {
    _log(
      event,
      level: _ReconnectLogLevel.warning,
      cycle: cycle,
      failureCategory: failureCategory,
    );
  }

  void _log(
    String event, {
    required _ReconnectLogLevel level,
    int? cycle,
    String? failureCategory,
  }) {
    final fields = <String, Object?>{
      'attempt': _state.attempt,
      'phase': _state.phase.name,
      'failure_category': ?failureCategory,
      'cycle': ?cycle,
    };
    try {
      switch (level) {
        case _ReconnectLogLevel.info:
          _logger.info(
            event,
            operation: 'device_reconnect',
            stage: _state.phase.name,
            fields: fields,
          );
        case _ReconnectLogLevel.warning:
          _logger.warning(
            event,
            operation: 'device_reconnect',
            stage: _state.phase.name,
            fields: fields,
          );
      }
    } catch (_) {
      // Diagnostics must not affect the BLE reconnect flow.
    }
  }

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _cycleId += 1;
    unawaited(_stopScanSafely());
    super.dispose();
  }
}

enum _ReconnectLogLevel { info, warning }
