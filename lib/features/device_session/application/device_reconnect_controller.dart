import 'dart:async';

import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/features/device_discovery/domain/advertisement_filter.dart';
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
    AdvertisementFilter advertisementFilter = const AdvertisementFilter(),
    bool filterByV15Advertisement = true,
    Future<void> Function(Duration duration)? waitForRetry,
    DateTime Function()? now,
  }) {
    return DeviceReconnectController._(
      history,
      startScan,
      stopScan,
      connect,
      logger,
      advertisementFilter,
      filterByV15Advertisement,
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
    this._advertisementFilter,
    this._filterByV15Advertisement,
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
  final AdvertisementFilter _advertisementFilter;
  final bool _filterByV15Advertisement;
  final Future<void> Function(Duration duration) _waitForRetry;
  final DateTime Function() _now;

  DeviceReconnectState _state = const DeviceReconnectState();
  Future<void> _scanOperationTail = Future<void>.value();
  int _cycleId = 0;
  bool _suppressedForForeground = false;
  bool _pausedForBackground = false;
  bool _scanMayBeActive = false;
  bool _isDisposed = false;

  DeviceReconnectState get state => _state;

  /// Restore the newest remembered device and begin an automatic scan.
  Future<void> restoreAndStart() {
    _pausedForBackground = false;
    _logInfo(
      'reconnect_restore_requested',
      reason: '应用回到前台，准备读取最近一次连接记录并尝试自动回连。',
      fields: {'action': 'foreground_restore'},
    );
    return _startCycle(clearSuppression: false, trigger: 'foreground_restore');
  }

  /// A user-requested cycle clears foreground-only suppression and retry
  /// history, then waits for a matching foreground scan result.
  Future<void> startExplicitCycle() {
    _pausedForBackground = false;
    _logInfo(
      'reconnect_explicit_cycle_requested',
      reason: '用户主动请求重新连接，清除本次前台的自动回连抑制状态。',
      fields: {'action': 'user_retry'},
    );
    return _startCycle(clearSuppression: true, trigger: 'user_retry');
  }

  /// Evaluates one discovered candidate without retaining its raw identifier.
  Future<void> considerCandidate(DeviceCandidate candidate) async {
    final cycle = _cycleId;
    if (!_isActive(cycle)) {
      return;
    }
    if (_suppressedForForeground) {
      return;
    }
    if (_pausedForBackground) {
      return;
    }
    if (_state.phase != DeviceReconnectPhase.scanning) {
      return;
    }
    final remembered = _state.rememberedDevice;
    final candidateFields = _candidateLogFields(candidate);
    _logInfo(
      'reconnect_candidate_received',
      reason: '自动回连扫描收到一条蓝牙广播，开始核对历史连接记录。',
      cycle: cycle,
      result: 'pending',
      fields: candidateFields,
    );
    if (remembered == null) {
      _logInfo(
        'reconnect_candidate_ignored',
        reason: '没有可用的历史连接记录，不能自动选择扫描到的设备。',
        cycle: cycle,
        result: 'cancelled',
        fields: candidateFields,
      );
      return;
    }
    if (_filterByV15Advertisement && !_advertisementFilter.matches(candidate)) {
      _logInfo(
        'reconnect_candidate_ignored',
        reason: '扫描结果不符合 EVT 广播约定，不能用于自动回连。',
        cycle: cycle,
        result: 'cancelled',
        fields: candidateFields,
      );
      return;
    }
    if (!remembered.matches(candidate)) {
      _logInfo(
        'reconnect_candidate_ignored',
        reason: '扫描结果与最近一次连接设备不匹配，继续等待目标设备广播。',
        cycle: cycle,
        result: 'cancelled',
        fields: candidateFields,
      );
      return;
    }

    final nextAttempt = _state.attempt + 1;
    if (nextAttempt > _maximumAttempts) {
      _logWarning(
        'reconnect_candidate_ignored',
        reason: '自动回连已达到最大尝试次数，等待用户主动重新连接。',
        cycle: cycle,
        result: 'failed',
        fields: candidateFields,
      );
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
    _logInfo(
      'reconnect_candidate_matched',
      reason: '扫描结果与历史连接记录匹配，停止扫描并准备发起 GATT 连接。',
      cycle: cycle,
      result: 'accepted',
      fields: candidateFields,
    );

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
      _logInfo(
        'reconnect_connect_requested',
        reason: '扫描已停止，开始执行本次自动 GATT 连接。',
        cycle: cycle,
        result: 'pending',
        fields: candidateFields,
      );
      connected = await _connect(candidate);
    } catch (error) {
      if (_isActive(cycle)) {
        _logWarning(
          'reconnect_connect_failed',
          reason: '自动 GATT 连接调用发生异常，将按重试策略继续处理。',
          cycle: cycle,
          result: 'failed',
          fields: {'error_type': error.runtimeType.toString()},
        );
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
      _logInfo(
        'reconnect_connected',
        reason: '自动回连已建立连接，停止后续重试与扫描。',
        cycle: cycle,
        result: 'success',
        fields: candidateFields,
      );
      return;
    }

    _handleAttemptFailure(cycle, 'connect_rejected');
  }

  /// Starts a fresh automatic cycle after a session drops unexpectedly.
  Future<void> markUnexpectedDisconnect() async {
    if (_isDisposed) {
      return;
    }
    if (_suppressedForForeground || _pausedForBackground) {
      _logInfo(
        'reconnect_unexpected_disconnect_ignored',
        reason: _suppressedForForeground
            ? '用户已停止自动回连，意外断开后不再启动新的连接尝试。'
            : '应用处于后台暂停状态，意外断开后暂不启动自动回连。',
        result: 'cancelled',
      );
      return;
    }
    _logInfo(
      'reconnect_unexpected_disconnect_received',
      reason: '检测到非用户主动的设备断开，准备重新扫描最近连接的设备。',
      result: 'pending',
    );
    await _startCycle(
      clearSuppression: false,
      trigger: 'unexpected_disconnect',
    );
  }

  /// Stops automatic reconnect work until an explicit request or a new
  /// foreground session clears this suppression.
  Future<void> suppressForForeground() async {
    if (_isDisposed) {
      return;
    }
    _logInfo(
      'reconnect_suppression_requested',
      reason: '用户要求停止自动回连，本次前台将不再自动扫描或连接设备。',
      result: 'pending',
    );
    _suppressedForForeground = true;
    _cycleId += 1;
    await _stopScanSafely(cycle: _cycleId, action: 'suppress_for_foreground');
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
    _logInfo(
      'reconnect_suppressed',
      reason: '自动回连已停止，直到用户主动连接或启动新的连接会话。',
      result: 'completed',
    );
  }

  /// Cancels transient foreground work while the app is backgrounded.
  ///
  /// A user-requested disconnect remains suppressed after foreground restore;
  /// only [startExplicitCycle] or a new manual connection may clear it.
  Future<void> pauseForBackground() async {
    if (_isDisposed) {
      return;
    }
    final pausedCycle = ++_cycleId;
    _pausedForBackground = true;
    _logInfo(
      'reconnect_background_pause_requested',
      reason: '应用进入后台，暂停自动扫描和自动回连任务。',
      cycle: pausedCycle,
      result: 'pending',
    );
    await _stopScanSafely(cycle: pausedCycle, action: 'background_pause');
    if (!_isActive(pausedCycle) ||
        !_pausedForBackground ||
        _state.phase == DeviceReconnectPhase.connected) {
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
      _logInfo(
        'reconnect_paused_while_suppressed',
        reason: '应用进入后台时自动回连已被用户停止，保留该停止状态。',
        cycle: pausedCycle,
        result: 'completed',
      );
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
    _logInfo(
      'reconnect_paused',
      reason: '自动回连已暂停，应用回到前台后会重新读取历史连接记录。',
      cycle: pausedCycle,
      result: 'completed',
    );
  }

  /// Persists a record only for a valid, named candidate after the caller has
  /// confirmed session authentication readiness.
  Future<void> rememberSuccessfulConnection(DeviceCandidate candidate) async {
    if (_isDisposed) {
      return;
    }
    final record = _recordForCandidate(candidate);
    if (record == null) {
      _logWarning(
        'reconnect_history_write_skipped',
        reason: '连接记录未保存：设备广播缺少可用于回连的有效身份字段。',
        result: 'failed',
        fields: _candidateLogFields(candidate),
      );
      return;
    }
    final readyCycle = _cycleId;
    _logInfo(
      'reconnect_history_write_requested',
      reason: '设备会话已就绪，准备保存用于下次自动回连的本地连接记录。',
      cycle: readyCycle,
      result: 'pending',
      fields: _candidateLogFields(candidate),
    );

    try {
      await _history.upsert(record);
    } catch (error) {
      _logWarning(
        'reconnect_history_write_failed',
        reason: '保存本地设备连接记录失败，不会影响当前已建立的设备会话。',
        cycle: readyCycle,
        result: 'failed',
        fields: {'error_type': error.runtimeType.toString()},
      );
      return;
    }

    if (_isDisposed) {
      return;
    }
    if (!_isActive(readyCycle) || _suppressedForForeground) {
      _setState(_state.copyWith(rememberedDevice: record));
      _logInfo(
        'reconnect_history_written',
        reason: '本地设备连接记录已保存，但当前自动回连会话已结束或被用户停止。',
        cycle: readyCycle,
        result: 'completed',
      );
      return;
    }
    // A direct/manual connection can complete while this controller is idle.
    // Treat it the same as an automatic success so no stale retry UI remains.
    _setState(
      _state.copyWith(
        phase: DeviceReconnectPhase.connected,
        rememberedDevice: record,
        canRetry: false,
        clearFailureCategory: true,
      ),
    );
    _logInfo(
      'reconnect_history_written',
      reason: '本地设备连接记录已保存，可在后续扫描到同一设备时自动回连。',
      cycle: readyCycle,
      result: 'completed',
    );
  }

  /// Lets a user-selected connection take over from automatic reconnect work.
  ///
  /// It clears foreground-only suppression so a later unexpected disconnect
  /// can start a new automatic cycle after this manual connection succeeds.
  Future<void> takeOverManualConnection() async {
    if (_isDisposed) {
      return;
    }
    _suppressedForForeground = false;
    final manualCycle = ++_cycleId;
    _logInfo(
      'reconnect_manual_takeover_requested',
      reason: '用户选择手动连接设备，取消正在进行的自动回连任务。',
      cycle: manualCycle,
      result: 'pending',
    );
    await _stopScanSafely(cycle: manualCycle, action: 'manual_takeover');
    if (!_isActive(manualCycle)) {
      return;
    }
    if (_state.phase != DeviceReconnectPhase.connected) {
      _setState(
        _state.copyWith(
          phase: DeviceReconnectPhase.idle,
          attempt: 0,
          canRetry: false,
          clearFailureCategory: true,
        ),
      );
    }
    _logInfo(
      'reconnect_manual_takeover',
      reason: '手动连接流程已接管，自动回连状态已还原为空闲。',
      cycle: manualCycle,
      result: 'completed',
    );
  }

  /// Synchronizes state when another owner, such as the discovery page,
  /// stops the shared scan stream. It deliberately does not schedule a new
  /// scan: a user closing that page or a platform scan error stays recoverable
  /// through the explicit reconnect action.
  void notifyScanStopped() {
    if (_isDisposed || !_scanMayBeActive) {
      return;
    }
    _scanMayBeActive = false;
    if (_state.phase != DeviceReconnectPhase.scanning) {
      return;
    }
    _setState(
      _state.copyWith(
        phase: DeviceReconnectPhase.idle,
        canRetry: true,
        failureCategory: 'scan_stopped',
      ),
    );
    _logWarning(
      'reconnect_scan_stopped_externally',
      reason: '共享扫描流已被其他页面或系统停止，自动回连等待用户重新发起。',
      result: 'failed',
    );
  }

  /// Removes the corresponding private record after a successful clear/unbind.
  Future<void> forgetSuccessfulClear(DeviceCandidate candidate) async {
    if (_isDisposed) {
      return;
    }
    final physicalMacAddress = _physicalMacAddressFor(candidate);
    _logInfo(
      'reconnect_history_remove_requested',
      reason: '设备已完成清除或解绑，准备删除本地自动回连记录。',
      result: 'pending',
      fields: _candidateLogFields(candidate),
    );
    try {
      await _history.removeMatching(
        connectionId: candidate.connectionId,
        physicalMacAddress: physicalMacAddress,
      );
    } catch (error) {
      _logWarning(
        'reconnect_history_remove_failed',
        reason: '删除本地自动回连记录失败，后续可能仍会尝试回连该设备。',
        result: 'failed',
        fields: {'error_type': error.runtimeType.toString()},
      );
      return;
    }

    if (_isDisposed) {
      return;
    }
    final remembered = _state.rememberedDevice;
    if (remembered != null && remembered.matches(candidate)) {
      _cycleId += 1;
      await _stopScanSafely(cycle: _cycleId, action: 'forget_successful_clear');
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
    _logInfo(
      'reconnect_history_removed',
      reason: '本地自动回连记录已删除，不会再自动选择该设备。',
      result: 'completed',
    );
  }

  /// Cancels automatic work when a separate manual connection flow takes over.
  Future<void> cancelAutomaticCycle() async {
    if (_isDisposed) {
      return;
    }
    _cycleId += 1;
    _logInfo(
      'reconnect_cancellation_requested',
      reason: '收到取消自动回连请求，停止当前扫描或重试任务。',
      cycle: _cycleId,
      result: 'pending',
    );
    await _stopScanSafely(cycle: _cycleId, action: 'cancel_automatic_cycle');
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
    _logInfo(
      'reconnect_cancelled',
      reason: '自动回连任务已取消，等待新的用户操作或连接状态变化。',
      result: 'cancelled',
    );
  }

  Future<void> _startCycle({
    required bool clearSuppression,
    required String trigger,
  }) async {
    if (_isDisposed) {
      return;
    }
    if (clearSuppression) {
      _suppressedForForeground = false;
    }
    final cycle = ++_cycleId;
    _logInfo(
      'reconnect_cycle_started',
      reason: '开始新的自动回连周期，先停止旧扫描再读取本地连接记录。',
      cycle: cycle,
      result: 'pending',
      fields: {'action': trigger},
    );

    await _stopScanSafely(cycle: cycle, action: 'start_new_cycle');
    if (!_isActive(cycle)) {
      _logInfo(
        'reconnect_cycle_cancelled',
        reason: '新的自动回连周期在准备过程中被后续操作替换。',
        cycle: cycle,
        result: 'cancelled',
        fields: {'action': trigger},
      );
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
      _logInfo(
        'reconnect_cycle_suppressed',
        reason: '本次前台已停止自动回连，不读取历史记录或启动扫描。',
        cycle: cycle,
        result: 'cancelled',
        fields: {'action': trigger},
      );
      return;
    }

    List<RememberedDevice> records;
    try {
      _logInfo(
        'reconnect_history_load_requested',
        reason: '正在读取本地保存的设备连接记录，确定自动回连目标。',
        cycle: cycle,
        result: 'pending',
        fields: {'action': trigger},
      );
      records = await _history.load();
    } catch (error) {
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
        _logWarning(
          'reconnect_history_load_failed',
          reason: '读取本地设备连接记录失败，用户可以手动重新连接。',
          cycle: cycle,
          result: 'failed',
          fields: {'error_type': error.runtimeType.toString()},
        );
      }
      return;
    }
    if (!_isActive(cycle)) {
      _logInfo(
        'reconnect_history_load_cancelled',
        reason: '本地连接记录读取完成后，回连周期已被新的操作替换。',
        cycle: cycle,
        result: 'cancelled',
      );
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
      _logInfo(
        'reconnect_history_empty',
        reason: '没有可用于自动回连的历史设备记录，本次不启动扫描。',
        cycle: cycle,
        result: 'completed',
        fields: {'length': 0},
      );
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
    _logInfo(
      'reconnect_history_loaded',
      reason: '已读取本地连接记录，将扫描附近广播以寻找最近连接的设备。',
      cycle: cycle,
      result: 'completed',
      fields: {'length': records.length},
    );
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
    if (!_isActive(cycle)) {
      _logInfo(
        'reconnect_scan_start_ignored',
        reason: '回连扫描请求已过期，不启动新的系统扫描。',
        cycle: cycle,
        result: 'cancelled',
      );
      return;
    }
    if (_suppressedForForeground || _pausedForBackground) {
      _logInfo(
        'reconnect_scan_start_ignored',
        reason: _suppressedForForeground
            ? '用户已停止自动回连，不启动新的系统扫描。'
            : '应用处于后台暂停状态，不启动新的系统扫描。',
        cycle: cycle,
        result: 'cancelled',
      );
      return;
    }
    _setState(
      _state.copyWith(
        phase: DeviceReconnectPhase.scanning,
        canRetry: false,
        clearFailureCategory: true,
      ),
    );
    _logInfo(
      'reconnect_scan_start_requested',
      reason: '已找到历史设备记录，开始系统扫描以等待匹配的 EVT 广播。',
      cycle: cycle,
      result: 'pending',
    );

    String? errorType;
    final started = await _queueScanOperation(() async {
      if (!_isActive(cycle) ||
          _suppressedForForeground ||
          _pausedForBackground) {
        return false;
      }
      _scanMayBeActive = true;
      try {
        await _startScan();
        return true;
      } catch (error) {
        _scanMayBeActive = false;
        errorType = error.runtimeType.toString();
        return false;
      }
    });
    if (!_isActive(cycle)) {
      return;
    }
    if (started) {
      _logInfo(
        'reconnect_scan_started',
        reason: '自动回连系统扫描已启动，等待匹配设备的实时广播。',
        cycle: cycle,
        result: 'success',
      );
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
      reason: '自动回连无法启动系统扫描，用户可以稍后重新连接。',
      cycle: cycle,
      result: 'failed',
      fields: {'error_type': ?errorType},
    );
  }

  Future<bool> _stopScanForCycle(int cycle) async {
    final stopped = await _stopScanSafely(
      cycle: cycle,
      action: 'candidate_matched',
    );
    return stopped && _isActive(cycle);
  }

  Future<bool> _stopScanSafely({int? cycle, required String action}) {
    if (!_scanMayBeActive) {
      _logInfo(
        'reconnect_scan_stop_skipped',
        reason: '自动回连扫描当前未运行，无需向系统发送停止请求。',
        cycle: cycle,
        result: 'completed',
        fields: {'action': action},
      );
      return Future<bool>.value(true);
    }
    _scanMayBeActive = false;
    _logInfo(
      'reconnect_scan_stop_requested',
      reason: '准备停止自动回连使用的系统扫描，避免与连接流程并发。',
      cycle: cycle,
      result: 'pending',
      fields: {'action': action},
    );
    return _queueScanOperation(() async {
      try {
        await _stopScan();
        _logInfo(
          'reconnect_scan_stopped',
          reason: '自动回连使用的系统扫描已停止。',
          cycle: cycle,
          result: 'completed',
          fields: {'action': action},
        );
        return true;
      } catch (error) {
        _logWarning(
          'reconnect_scan_stop_failed',
          reason: '停止自动回连系统扫描失败，连接流程将按失败策略处理。',
          cycle: cycle,
          result: 'failed',
          fields: {
            'action': action,
            'error_type': error.runtimeType.toString(),
          },
        );
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
    _logWarning(
      'reconnect_attempt_failed',
      reason: _failureReason(failureCategory),
      cycle: cycle,
      result: 'failed',
      failureCategory: failureCategory,
      fields: {'connection_attempt': attempt, 'max_retries': _maximumAttempts},
    );
    if (attempt >= _maximumAttempts) {
      _setState(
        _state.copyWith(
          phase: DeviceReconnectPhase.exhausted,
          canRetry: true,
          failureCategory: failureCategory,
        ),
      );
      _logWarning(
        'reconnect_exhausted',
        reason: '自动回连已达到最大尝试次数，停止继续连接并等待用户操作。',
        cycle: cycle,
        result: 'failed',
        failureCategory: failureCategory,
        fields: {
          'connection_attempt': attempt,
          'max_retries': _maximumAttempts,
        },
      );
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
    _logInfo(
      'reconnect_retry_scheduled',
      reason: '自动回连失败，已安排下一次扫描和连接尝试。',
      cycle: cycle,
      result: 'retrying',
      failureCategory: failureCategory,
      fields: {
        'connection_attempt': attempt,
        'duration_ms': delay.inMilliseconds,
        'max_retries': _maximumAttempts,
      },
    );
    unawaited(_waitThenScan(cycle, delay));
  }

  Future<void> _waitThenScan(int cycle, Duration delay) async {
    try {
      _logInfo(
        'reconnect_retry_wait_started',
        reason: '自动回连正在等待重试间隔结束，期间不重复发起连接。',
        cycle: cycle,
        result: 'pending',
        fields: {'duration_ms': delay.inMilliseconds},
      );
      await _waitForRetry(delay);
    } catch (error) {
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
          reason: '自动回连重试等待器发生异常，用户可以主动重新连接。',
          cycle: cycle,
          result: 'failed',
          failureCategory: 'retry_wait_failed',
          fields: {'error_type': error.runtimeType.toString()},
        );
      }
      return;
    }
    if (!_isActive(cycle) || _suppressedForForeground || _pausedForBackground) {
      _logInfo(
        'reconnect_retry_cancelled',
        reason: !_isActive(cycle)
            ? '重试等待结束后回连周期已过期，不再启动新的扫描。'
            : _suppressedForForeground
            ? '用户已停止自动回连，取消等待中的重试任务。'
            : '应用处于后台暂停状态，取消等待中的重试任务。',
        cycle: cycle,
        result: 'cancelled',
      );
      return;
    }
    _logInfo(
      'reconnect_retry_wait_completed',
      reason: '自动回连重试等待已结束，准备再次启动系统扫描。',
      cycle: cycle,
      result: 'completed',
      fields: {'duration_ms': delay.inMilliseconds},
    );
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
    final previous = _state;
    _state = next;
    notifyListeners();
    _logInfo(
      'reconnect_state_changed',
      reason: '自动回连状态已更新，界面将按最新状态显示。',
      stage: _stageFor(next.phase),
      fields: {
        'phase_from': _phaseName(previous.phase),
        'phase_to': _phaseName(next.phase),
      },
    );
  }

  String _failureReason(String failureCategory) => switch (failureCategory) {
    'scan_stop_failed' => '停止自动回连扫描失败，无法安全进入连接流程。',
    'connect_error' => '自动 GATT 连接调用异常，准备按重试策略继续处理。',
    'connect_rejected' => '设备未接受本次自动连接，准备按重试策略继续处理。',
    _ => '自动回连发生可恢复失败，准备按重试策略继续处理。',
  };

  String _phaseName(DeviceReconnectPhase phase) => switch (phase) {
    DeviceReconnectPhase.idle => 'idle',
    DeviceReconnectPhase.scanning => 'scanning',
    DeviceReconnectPhase.connecting => 'connecting',
    DeviceReconnectPhase.waitingToRetry => 'waiting_to_retry',
    DeviceReconnectPhase.connected => 'connected',
    DeviceReconnectPhase.exhausted => 'exhausted',
    DeviceReconnectPhase.suppressed => 'suppressed',
  };

  String _stageFor(DeviceReconnectPhase phase) => _phaseName(phase);

  Map<String, Object?> _candidateLogFields(DeviceCandidate candidate) {
    return {
      'rssi': candidate.rssi,
      'has_name': candidate.name.trim().isNotEmpty,
      'service_count': candidate.serviceUuids.length,
      'device_suffix': _deviceSuffix(candidate),
    };
  }

  String? _deviceSuffix(DeviceCandidate candidate) {
    final physicalDeviceId = candidate.physicalDeviceId;
    if (physicalDeviceId == null) {
      return null;
    }
    final compact = physicalDeviceId.replaceAll(':', '');
    if (!RegExp(r'^[A-F0-9]{12}$').hasMatch(compact)) {
      return null;
    }
    return '...${compact.substring(compact.length - 4)}';
  }

  void _logInfo(
    String event, {
    required String reason,
    int? cycle,
    String? stage,
    String? result,
    String? failureCategory,
    Map<String, Object?> fields = const {},
  }) {
    _log(
      event,
      level: _ReconnectLogLevel.info,
      reason: reason,
      cycle: cycle,
      stage: stage,
      result: result,
      failureCategory: failureCategory,
      fields: fields,
    );
  }

  void _logWarning(
    String event, {
    required String reason,
    int? cycle,
    String? stage,
    String? result,
    String? failureCategory,
    Map<String, Object?> fields = const {},
  }) {
    _log(
      event,
      level: _ReconnectLogLevel.warning,
      reason: reason,
      cycle: cycle,
      stage: stage,
      result: result,
      failureCategory: failureCategory,
      fields: fields,
    );
  }

  void _log(
    String event, {
    required _ReconnectLogLevel level,
    required String reason,
    int? cycle,
    String? stage,
    String? result,
    String? failureCategory,
    Map<String, Object?> fields = const {},
  }) {
    final logFields = <String, Object?>{
      'attempt': _state.attempt,
      'phase': _phaseName(_state.phase),
      'failure_category': ?failureCategory,
      'cycle': ?cycle,
      'reason': reason,
      ...fields,
    };
    try {
      switch (level) {
        case _ReconnectLogLevel.info:
          _logger.info(
            event,
            operation: 'device_reconnect',
            stage: stage ?? _stageFor(_state.phase),
            result: result,
            fields: logFields,
          );
        case _ReconnectLogLevel.warning:
          _logger.warning(
            event,
            operation: 'device_reconnect',
            stage: stage ?? _stageFor(_state.phase),
            result: result,
            fields: logFields,
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
    _logInfo(
      'reconnect_controller_disposed',
      reason: '自动回连控制器已释放，取消剩余扫描和重试任务。',
      result: 'completed',
    );
    _isDisposed = true;
    _cycleId += 1;
    unawaited(_stopScanSafely(cycle: _cycleId, action: 'controller_dispose'));
    super.dispose();
  }
}

enum _ReconnectLogLevel { info, warning }
