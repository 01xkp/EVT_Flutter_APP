import 'dart:async';

import 'package:aipin/core/ble/ble_transport.dart';
import 'package:aipin/core/diagnostics/evt_failure.dart';
import 'package:aipin/features/device_discovery/application/discovery_state.dart';
import 'package:aipin/features/device_discovery/domain/advertisement_filter.dart';
import 'package:aipin/features/device_discovery/domain/device_candidate.dart';
import 'package:flutter/foundation.dart';

class DiscoveryController extends ChangeNotifier {
  DiscoveryController(
    this._transport,
    this._filter, {
    this.staleDeviceTimeout = _defaultStaleDeviceTimeout,
    this.expiryCheckInterval = _defaultExpiryCheckInterval,
  });

  static const _defaultStaleDeviceTimeout = Duration(seconds: 5);
  static const _defaultExpiryCheckInterval = Duration(seconds: 1);

  final BleTransport _transport;
  final AdvertisementFilter _filter;
  final Duration staleDeviceTimeout;
  final Duration expiryCheckInterval;
  StreamSubscription<DeviceCandidate>? _scanSubscription;
  Timer? _expiryTimer;
  Set<String> _excludedDeviceIds = const {};
  DiscoveryState _state = const DiscoveryState();

  DiscoveryState get state => _state;

  void start() {
    if (_state.isScanning) {
      return;
    }
    _state = _state.copyWith(
      isScanning: true,
      candidates: const [],
      selected: null,
      failure: null,
      isBluetoothOff: false,
    );
    notifyListeners();
    _startExpiryTimer();
    _scanSubscription = _transport.scan().listen(
      _onCandidate,
      onError: _onScanError,
      onDone: () {
        _stopExpiryTimer();
        if (_state.isScanning) {
          _state = _state.copyWith(isScanning: false);
          notifyListeners();
        }
      },
    );
  }

  void select(DeviceCandidate candidate) {
    if (!_state.candidates.any((item) => item.id == candidate.id)) {
      return;
    }
    _state = _state.copyWith(selected: candidate);
    notifyListeners();
  }

  void setExcludedDeviceIds(Iterable<String> deviceIds) {
    final excludedDeviceIds = Set<String>.unmodifiable(
      deviceIds.where((id) => id.isNotEmpty),
    );
    if (setEquals(_excludedDeviceIds, excludedDeviceIds)) {
      return;
    }
    _excludedDeviceIds = excludedDeviceIds;
    final candidates = _state.candidates
        .where((candidate) => !_excludedDeviceIds.contains(candidate.id))
        .toList(growable: false);
    final selected = _state.selected;
    _state = _state.copyWith(
      candidates: List.unmodifiable(candidates),
      selected: selected != null && _excludedDeviceIds.contains(selected.id)
          ? null
          : selected,
    );
    notifyListeners();
  }

  Future<void> stop() async {
    _stopExpiryTimer();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    if (_state.isScanning) {
      _state = _state.copyWith(isScanning: false);
      notifyListeners();
    }
  }

  void _onCandidate(DeviceCandidate candidate) {
    if (candidate.name.trim().isEmpty ||
        _excludedDeviceIds.contains(candidate.id) ||
        !_filter.matches(candidate)) {
      return;
    }
    final freshCandidate = candidate.copyWith(discoveredAt: DateTime.now());
    final candidates = [
      for (final existing in _state.candidates)
        if (existing.id != freshCandidate.id) existing,
      freshCandidate,
    ]..sort((left, right) => right.rssi.compareTo(left.rssi));
    final selected = _state.selected?.id == freshCandidate.id
        ? freshCandidate
        : _state.selected;
    _state = _state.copyWith(
      candidates: List.unmodifiable(candidates),
      selected: selected,
    );
    notifyListeners();
  }

  void _onScanError(Object error, StackTrace stackTrace) {
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
    unawaited(_scanSubscription?.cancel());
    _scanSubscription = null;
    notifyListeners();
  }

  void _startExpiryTimer() {
    _stopExpiryTimer();
    _expiryTimer = Timer.periodic(
      expiryCheckInterval,
      (_) => _removeStaleCandidates(),
    );
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
              !candidates.any((candidate) => candidate.id == selected.id)
          ? null
          : selected,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _stopExpiryTimer();
    unawaited(_scanSubscription?.cancel());
    super.dispose();
  }
}
