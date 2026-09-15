import 'dart:async';

import 'package:aipin/core/ble/ble_transport.dart';
import 'package:aipin/core/diagnostics/evt_failure.dart';
import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/features/device_discovery/application/discovery_state.dart';
import 'package:aipin/features/device_discovery/domain/advertisement_filter.dart';
import 'package:aipin/features/device_discovery/domain/device_candidate.dart';
import 'package:flutter/foundation.dart';

class DiscoveryController extends ChangeNotifier {
  DiscoveryController(
    this._transport,
    this._filter, {
    SafeAppLogger? logger,
    // EVT bench builds intentionally accept any named advertisement. The
    // protocol/GATT contract remains the authoritative gate after connect;
    // callers can opt into the stricter identity filter for qualification.
    bool? filterByV16Advertisement,
    // Kept for source compatibility with pre-V1.6 callers.
    @Deprecated('Use filterByV16Advertisement') bool? filterByV15Advertisement,
    this.staleDeviceTimeout = _defaultStaleDeviceTimeout,
    this.expiryCheckInterval = _defaultExpiryCheckInterval,
  }) : _logger = logger ?? const DebugSafeAppLogger(scope: 'BLE'),
       filterByV16Advertisement =
           filterByV16Advertisement ?? filterByV15Advertisement ?? false;

  static const _defaultStaleDeviceTimeout = Duration(seconds: 5);
  static const _defaultExpiryCheckInterval = Duration(seconds: 1);
  static const _repeatedAdvertisementLogInterval = 25;

  final BleTransport _transport;
  final AdvertisementFilter _filter;
  final SafeAppLogger _logger;
  final bool filterByV16Advertisement;

  /// @deprecated Use [filterByV16Advertisement].
  @Deprecated('Use filterByV16Advertisement')
  bool get filterByV15Advertisement => filterByV16Advertisement;
  final Duration staleDeviceTimeout;
  final Duration expiryCheckInterval;
  StreamSubscription<DeviceCandidate>? _scanSubscription;
  Timer? _expiryTimer;
  int _scanGeneration = 0;
  var _isDisposed = false;
  Set<String> _excludedDeviceIds = const {};
  final Map<String, _AdvertisementFragment> _advertisementFragments = {};
  final Map<String, int> _advertisementDiagnosticCounts = {};
  DiscoveryState _state = const DiscoveryState();

  DiscoveryState get state => _state;

  void start() {
    if (_isDisposed) {
      _logWarning(
        'scan_start_ignored',
        reason: '扫描请求已忽略：发现控制器已经释放。',
        stage: 'idle',
        result: 'cancelled',
      );
      return;
    }
    if (_state.isScanning) {
      _logInfo(
        'scan_start_ignored',
        reason: '扫描请求已忽略：当前扫描任务仍在运行。',
        stage: 'scanning',
        result: 'pending',
        fields: {
          'action': 'already_scanning',
          'length': _state.candidates.length,
        },
      );
      return;
    }
    final generation = ++_scanGeneration;
    _logInfo(
      'scan_start_requested',
      reason: '收到设备扫描请求，准备清空旧结果并订阅系统蓝牙扫描流。',
      stage: 'scanning',
      result: 'pending',
      fields: {'action': 'start', 'length': _state.candidates.length},
    );
    _state = _state.copyWith(
      isScanning: true,
      candidates: const [],
      selected: null,
      failure: null,
      isBluetoothOff: false,
    );
    _advertisementFragments.clear();
    _advertisementDiagnosticCounts.clear();
    notifyListeners();
    _startExpiryTimer(generation);
    late final StreamSubscription<DeviceCandidate> subscription;
    try {
      subscription = _transport.scan().listen(
        (candidate) => _onCandidate(candidate, generation),
        onError: (Object error, StackTrace stackTrace) =>
            _onScanError(error, stackTrace, generation),
        onDone: () => _onScanDone(generation),
      );
    } catch (error, stackTrace) {
      _onScanError(error, stackTrace, generation);
      return;
    }
    // A synchronous platform stream can report an error while listen() is
    // being installed. Do not retain that stale subscription as the active
    // scanner after its callback has already invalidated this generation.
    if (_isCurrentScan(generation)) {
      _scanSubscription = subscription;
      _logInfo(
        'scan_stream_subscribed',
        reason: '系统蓝牙扫描流已订阅，等待附近设备广播。',
        stage: 'scanning',
        result: 'pending',
      );
    } else {
      _logInfo(
        'scan_stream_subscription_cancelled',
        reason: '扫描流建立后已失效，取消保留的订阅。',
        stage: 'idle',
        result: 'cancelled',
      );
      unawaited(subscription.cancel());
    }
  }

  void select(DeviceCandidate candidate) {
    if (!_state.candidates.any(
      (item) => item.connectionId == candidate.connectionId,
    )) {
      _logInfo(
        'scan_candidate_selection_ignored',
        reason: '选择设备请求已忽略：该设备不在当前实时扫描列表中。',
        stage: _scanStage,
        result: 'cancelled',
        fields: _candidateLogFields(candidate),
      );
      return;
    }
    _state = _state.copyWith(selected: candidate);
    notifyListeners();
    _logInfo(
      'scan_candidate_selected',
      reason: '用户已从实时扫描列表选择设备，允许进入连接流程。',
      stage: _scanStage,
      result: 'accepted',
      fields: _candidateLogFields(candidate),
    );
  }

  void setExcludedDeviceIds(Iterable<String> deviceIds) {
    final excludedDeviceIds = Set<String>.unmodifiable(
      deviceIds.where((id) => id.isNotEmpty),
    );
    if (setEquals(_excludedDeviceIds, excludedDeviceIds)) {
      _logInfo(
        'scan_exclusion_unchanged',
        reason: '已连接设备排除列表没有变化，保留当前扫描结果。',
        stage: _scanStage,
        result: 'completed',
        fields: {'length': _excludedDeviceIds.length},
      );
      return;
    }
    _excludedDeviceIds = excludedDeviceIds;
    final candidates = _state.candidates
        .where(
          (candidate) => !_excludedDeviceIds.contains(candidate.connectionId),
        )
        .toList(growable: false);
    final selected = _state.selected;
    _state = _state.copyWith(
      candidates: List.unmodifiable(candidates),
      selected:
          selected != null && _excludedDeviceIds.contains(selected.connectionId)
          ? null
          : selected,
    );
    notifyListeners();
    _logInfo(
      'scan_exclusion_updated',
      reason: '已更新已连接设备排除列表，避免在扫描列表中重复显示。',
      stage: _scanStage,
      result: 'completed',
      fields: {
        'length': _excludedDeviceIds.length,
        'previous_state': selected == null ? 'unselected' : 'selected',
      },
    );
  }

  Future<void> stop() async {
    _logInfo(
      'scan_stop_requested',
      reason: '收到停止扫描请求，取消系统扫描订阅并停止设备过期检查。',
      stage: _scanStage,
      result: 'pending',
      fields: {'length': _state.candidates.length},
    );
    ++_scanGeneration;
    _stopExpiryTimer();
    final subscription = _scanSubscription;
    _scanSubscription = null;
    if (_state.isScanning) {
      _state = _state.copyWith(isScanning: false);
      notifyListeners();
    }
    try {
      await subscription?.cancel();
      _logInfo(
        'scan_stopped',
        reason: '设备扫描已停止，当前扫描会话已结束。',
        stage: 'idle',
        result: 'completed',
      );
    } catch (error) {
      _logWarning(
        'scan_stop_failed',
        reason: '停止设备扫描时系统返回异常，需要等待下一次扫描请求恢复。',
        stage: 'idle',
        result: 'failed',
        fields: {'error_type': error.runtimeType.toString()},
      );
      rethrow;
    }
  }

  void _onCandidate(DeviceCandidate candidate, int generation) {
    if (!_isCurrentScan(generation)) {
      _logInfo(
        'scan_result_ignored',
        reason: '忽略已结束或已替换扫描会话返回的设备广播。',
        stage: 'idle',
        result: 'cancelled',
        fields: _candidateLogFields(candidate),
      );
      return;
    }
    if (_excludedDeviceIds.contains(candidate.connectionId)) {
      _logCandidateDiagnostic(
        candidate,
        category: 'excluded',
        event: 'scan_result_ignored',
        aggregateEvent: 'scan_result_ignored_aggregate',
        reason: '忽略已连接设备的广播，避免设备列表重复展示。',
        aggregateReason: '已汇总忽略已连接设备的重复广播，避免扫描日志覆盖连接与认证证据。',
        result: 'cancelled',
      );
      return;
    }
    _logCandidateDiagnostic(
      candidate,
      category: 'received',
      event: 'scan_result_received',
      aggregateEvent: 'scan_result_received_aggregate',
      reason: '收到一条蓝牙广播，开始合并广告与扫描响应字段。',
      aggregateReason: '已汇总同一设备的重复蓝牙广播，详细字段以首次记录和扫描列表当前值为准。',
      result: 'pending',
    );
    final now = DateTime.now();
    final previous = _advertisementFragments[candidate.connectionId];
    final fragment =
        previous == null ||
            now.difference(previous.updatedAt) >= staleDeviceTimeout
        ? _AdvertisementFragment.fromCandidate(candidate, now)
        : previous.merge(candidate, now);
    _advertisementFragments[candidate.connectionId] = fragment;
    final freshCandidate = fragment.toCandidate(candidate.connectionId);
    if (freshCandidate.name.trim().isEmpty) {
      _logCandidateDiagnostic(
        freshCandidate,
        category: 'unnamed',
        event: 'scan_result_ignored',
        aggregateEvent: 'scan_result_ignored_aggregate',
        reason: '忽略没有设备名称的蓝牙广播，无法向用户安全展示。',
        aggregateReason: '已汇总无名称设备的重复广播，不写入逐条日志以保留认证链路空间。',
        result: 'cancelled',
      );
      return;
    }
    if (filterByV16Advertisement && !_filter.matches(freshCandidate)) {
      _logCandidateDiagnostic(
        freshCandidate,
        category: 'filtered',
        event: 'scan_result_ignored',
        aggregateEvent: 'scan_result_ignored_aggregate',
        reason: '忽略不符合 EVT 广播约定的设备，保留当前扫描列表。',
        aggregateReason: '已汇总不符合 EVT 广播约定的重复设备，保留首次字段用于联调。',
        result: 'cancelled',
      );
      return;
    }
    final wasKnown = _state.candidates.any(
      (item) => item.connectionId == freshCandidate.connectionId,
    );
    final candidates = [
      for (final existing in _state.candidates)
        if (existing.connectionId != freshCandidate.connectionId) existing,
      freshCandidate,
    ]..sort((left, right) => right.rssi.compareTo(left.rssi));
    final selected =
        _state.selected?.connectionId == freshCandidate.connectionId
        ? freshCandidate
        : _state.selected;
    _state = _state.copyWith(
      candidates: List.unmodifiable(candidates),
      selected: selected,
    );
    notifyListeners();
    _logCandidateDiagnostic(
      freshCandidate,
      category: 'accepted',
      event: 'scan_result_accepted',
      aggregateEvent: 'scan_result_accepted_aggregate',
      reason: wasKnown ? '已刷新扫描列表中的设备信号与广告字段。' : '已将符合条件的设备加入实时扫描列表。',
      aggregateReason: '已汇总扫描列表中同一设备的重复信号刷新，当前列表保留最新值。',
      result: 'accepted',
      fields: {
        'action': wasKnown ? 'update' : 'add',
        'length': candidates.length,
      },
    );
  }

  /// Repeated Android advertisements can arrive dozens of times per second.
  /// Keep the first one and periodic samples, while the scan state still
  /// processes every callback in real time. This keeps later FA19 write and
  /// response evidence visible in the Debug log.
  void _logCandidateDiagnostic(
    DeviceCandidate candidate, {
    required String category,
    required String event,
    required String aggregateEvent,
    required String reason,
    required String aggregateReason,
    required String result,
    Map<String, Object?> fields = const {},
  }) {
    final key =
        '$category:${candidate.connectionId}:${candidate.name.trim().isEmpty ? 'unnamed' : 'named'}';
    final count = (_advertisementDiagnosticCounts[key] ?? 0) + 1;
    _advertisementDiagnosticCounts[key] = count;
    if (count != 1 && count % _repeatedAdvertisementLogInterval != 0) {
      return;
    }
    final isAggregate = count > 1;
    _logInfo(
      isAggregate ? aggregateEvent : event,
      reason: isAggregate ? aggregateReason : reason,
      stage: 'scanning',
      result: result,
      fields: {
        ..._candidateLogFields(candidate),
        ...fields,
        'subscription_count': count,
      },
    );
  }

  void _onScanError(Object error, StackTrace stackTrace, int generation) {
    if (!_isCurrentScan(generation)) {
      _logInfo(
        'scan_error_ignored',
        reason: '忽略已结束扫描会话的系统错误回调。',
        stage: 'idle',
        result: 'cancelled',
        fields: {'error_type': error.runtimeType.toString()},
      );
      return;
    }
    ++_scanGeneration;
    final failure = error is BleTransportException
        ? error.failure
        : EvtFailure.environment(message: '扫描已中断。', detail: '$error');
    _state = _state.copyWith(
      isScanning: false,
      selected: null,
      failure: failure,
      isBluetoothOff:
          error is BleTransportException &&
          error.issue == BleTransportIssue.bluetoothOff,
    );
    _stopExpiryTimer();
    final subscription = _scanSubscription;
    _scanSubscription = null;
    unawaited(subscription?.cancel());
    notifyListeners();
    final bluetoothOff =
        error is BleTransportException &&
        error.issue == BleTransportIssue.bluetoothOff;
    _logWarning(
      bluetoothOff ? 'scan_bluetooth_off' : 'scan_stream_failed',
      reason: bluetoothOff
          ? '系统蓝牙未开启，已停止扫描并等待用户开启蓝牙后重试。'
          : '扫描流发生异常，已停止扫描并等待用户手动重试。',
      stage: 'idle',
      result: 'failed',
      fields: {
        'error_type': error.runtimeType.toString(),
        'failure_kind': failure.kind.name,
      },
    );
  }

  void _onScanDone(int generation) {
    if (!_isCurrentScan(generation)) {
      _logInfo(
        'scan_stream_completion_ignored',
        reason: '忽略已替换扫描会话的结束回调。',
        stage: 'idle',
        result: 'cancelled',
      );
      return;
    }
    _stopExpiryTimer();
    if (_state.isScanning) {
      _state = _state.copyWith(isScanning: false);
      notifyListeners();
    }
    _logInfo(
      'scan_stream_completed',
      reason: '系统蓝牙扫描流已自然结束，设备扫描已停止。',
      stage: 'idle',
      result: 'completed',
    );
  }

  void _startExpiryTimer(int generation) {
    _stopExpiryTimer();
    _expiryTimer = Timer.periodic(expiryCheckInterval, (_) {
      if (_isCurrentScan(generation)) {
        _removeStaleCandidates();
      }
    });
  }

  void _stopExpiryTimer() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
  }

  void _removeStaleCandidates() {
    if (!_state.isScanning) {
      return;
    }
    final now = DateTime.now();
    final candidateCountBefore = _state.candidates.length;
    _advertisementFragments.removeWhere(
      (_, fragment) => now.difference(fragment.updatedAt) >= staleDeviceTimeout,
    );
    final candidates = _state.candidates
        .where(
          (candidate) =>
              now.difference(candidate.discoveredAt) < staleDeviceTimeout,
        )
        .toList(growable: false);
    if (candidates.length == _state.candidates.length) {
      return;
    }
    final selected = _state.selected;
    _state = _state.copyWith(
      candidates: List.unmodifiable(candidates),
      selected:
          selected != null &&
              !candidates.any(
                (candidate) => candidate.connectionId == selected.connectionId,
              )
          ? null
          : selected,
    );
    notifyListeners();
    _logInfo(
      'scan_stale_results_removed',
      reason: '超过实时广播有效期的设备已从扫描列表移除。',
      stage: 'scanning',
      result: 'completed',
      fields: {
        'action': 'expire',
        'length': candidates.length,
        'previous_state': candidateCountBefore == 0
            ? 'candidates_empty'
            : 'candidates_present',
      },
    );
  }

  bool _isCurrentScan(int generation) =>
      !_isDisposed && _state.isScanning && generation == _scanGeneration;

  String get _scanStage => _state.isScanning ? 'scanning' : 'idle';

  Map<String, Object?> _candidateLogFields(DeviceCandidate candidate) {
    final evaluation = _filter.evaluate(candidate);
    final expectedManufacturerPrefix = _filter.manufacturerPrefix;
    return {
      'rssi': candidate.rssi,
      'has_name': candidate.name.trim().isNotEmpty,
      'manufacturer_data_length': candidate.manufacturerData.length,
      'manufacturer_prefix':
          expectedManufacturerPrefix.length == 2 &&
          candidate.manufacturerData.length >= 2 &&
          candidate.manufacturerData[0] == expectedManufacturerPrefix.first &&
          candidate.manufacturerData[1] == expectedManufacturerPrefix.last,
      'service_count': candidate.serviceUuids.length,
      'service_uuid_present': !evaluation.reasons.contains('service_uuid'),
      'name_format_valid': !evaluation.reasons.contains('name_format'),
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
    required String stage,
    required String result,
    Map<String, Object?> fields = const {},
  }) {
    _log(
      event,
      level: _DiscoveryLogLevel.info,
      reason: reason,
      stage: stage,
      result: result,
      fields: fields,
    );
  }

  void _logWarning(
    String event, {
    required String reason,
    required String stage,
    required String result,
    Map<String, Object?> fields = const {},
  }) {
    _log(
      event,
      level: _DiscoveryLogLevel.warning,
      reason: reason,
      stage: stage,
      result: result,
      fields: fields,
    );
  }

  void _log(
    String event, {
    required _DiscoveryLogLevel level,
    required String reason,
    required String stage,
    required String result,
    required Map<String, Object?> fields,
  }) {
    final safeFields = <String, Object?>{'reason': reason, ...fields};
    try {
      switch (level) {
        case _DiscoveryLogLevel.info:
          _logger.info(
            event,
            operation: 'device_scan',
            stage: stage,
            result: result,
            fields: safeFields,
          );
        case _DiscoveryLogLevel.warning:
          _logger.warning(
            event,
            operation: 'device_scan',
            stage: stage,
            result: result,
            fields: safeFields,
          );
      }
    } catch (_) {
      // Diagnostics must never interrupt the platform scan stream.
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    ++_scanGeneration;
    _stopExpiryTimer();
    _advertisementFragments.clear();
    _advertisementDiagnosticCounts.clear();
    unawaited(_scanSubscription?.cancel());
    _logInfo(
      'scan_controller_disposed',
      reason: '设备发现控制器已释放，已取消剩余扫描订阅。',
      stage: 'idle',
      result: 'completed',
    );
    super.dispose();
  }
}

enum _DiscoveryLogLevel { info, warning }

/// Android can expose the V1.6 primary advertisement and scan response as
/// separate scan callbacks. The protocol distributes manufacturer data in the
/// former and service UUID plus local name in the latter, so preserve recent
/// fields for the same advertiser before applying the strict EVT filter.
class _AdvertisementFragment {
  const _AdvertisementFragment({
    required this.name,
    required this.manufacturerData,
    required this.serviceUuids,
    required this.rssi,
    required this.updatedAt,
  });

  factory _AdvertisementFragment.fromCandidate(
    DeviceCandidate candidate,
    DateTime updatedAt,
  ) => _AdvertisementFragment(
    name: candidate.name,
    manufacturerData: candidate.manufacturerData,
    serviceUuids: candidate.serviceUuids,
    rssi: candidate.rssi,
    updatedAt: updatedAt,
  );

  final String name;
  final List<int> manufacturerData;
  final List<String> serviceUuids;
  final int rssi;
  final DateTime updatedAt;

  _AdvertisementFragment merge(DeviceCandidate candidate, DateTime now) =>
      _AdvertisementFragment(
        name: candidate.name.trim().isEmpty ? name : candidate.name,
        manufacturerData: candidate.manufacturerData.isEmpty
            ? manufacturerData
            : candidate.manufacturerData,
        serviceUuids: candidate.serviceUuids.isEmpty
            ? serviceUuids
            : candidate.serviceUuids,
        rssi: candidate.rssi,
        updatedAt: now,
      );

  DeviceCandidate toCandidate(String connectionId) => DeviceCandidate(
    connectionId: connectionId,
    name: name,
    manufacturerData: manufacturerData,
    serviceUuids: serviceUuids,
    rssi: rssi,
    discoveredAt: updatedAt,
  );
}
