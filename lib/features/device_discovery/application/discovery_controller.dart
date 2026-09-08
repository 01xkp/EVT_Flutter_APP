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
    this.filterByV15Advertisement = true,
    this.staleDeviceTimeout = _defaultStaleDeviceTimeout,
    this.expiryCheckInterval = _defaultExpiryCheckInterval,
  });

  static const _defaultStaleDeviceTimeout = Duration(seconds: 5);
  static const _defaultExpiryCheckInterval = Duration(seconds: 1);

  final BleTransport _transport;
  final AdvertisementFilter _filter;
  final bool filterByV15Advertisement;
  final Duration staleDeviceTimeout;
  final Duration expiryCheckInterval;
  StreamSubscription<DeviceCandidate>? _scanSubscription;
  Timer? _expiryTimer;
  int _scanGeneration = 0;
  var _isDisposed = false;
  Set<String> _excludedDeviceIds = const {};
  final Map<String, _AdvertisementFragment> _advertisementFragments = {};
  DiscoveryState _state = const DiscoveryState();

  DiscoveryState get state => _state;

  void start() {
    if (_isDisposed || _state.isScanning) {
      return;
    }
    final generation = ++_scanGeneration;
    _state = _state.copyWith(
      isScanning: true,
      candidates: const [],
      selected: null,
      failure: null,
      isBluetoothOff: false,
    );
    _advertisementFragments.clear();
    notifyListeners();
    _startExpiryTimer(generation);
    final subscription = _transport.scan().listen(
      (candidate) => _onCandidate(candidate, generation),
      onError: (Object error, StackTrace stackTrace) =>
          _onScanError(error, stackTrace, generation),
      onDone: () {
        if (!_isCurrentScan(generation)) {
          return;
        }
        _stopExpiryTimer();
        if (_state.isScanning) {
          _state = _state.copyWith(isScanning: false);
          notifyListeners();
        }
      },
    );
    // A synchronous platform stream can report an error while listen() is
    // being installed. Do not retain that stale subscription as the active
    // scanner after its callback has already invalidated this generation.
    if (_isCurrentScan(generation)) {
      _scanSubscription = subscription;
    } else {
      unawaited(subscription.cancel());
    }
  }

  void select(DeviceCandidate candidate) {
    if (!_state.candidates.any(
      (item) => item.connectionId == candidate.connectionId,
    )) {
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
  }

  Future<void> stop() async {
    ++_scanGeneration;
    _stopExpiryTimer();
    final subscription = _scanSubscription;
    _scanSubscription = null;
    if (_state.isScanning) {
      _state = _state.copyWith(isScanning: false);
      notifyListeners();
    }
    await subscription?.cancel();
  }

  void _onCandidate(DeviceCandidate candidate, int generation) {
    if (!_isCurrentScan(generation) ||
        _excludedDeviceIds.contains(candidate.connectionId)) {
      return;
    }
    final now = DateTime.now();
    final previous = _advertisementFragments[candidate.connectionId];
    final fragment =
        previous == null ||
            now.difference(previous.updatedAt) >= staleDeviceTimeout
        ? _AdvertisementFragment.fromCandidate(candidate, now)
        : previous.merge(candidate, now);
    _advertisementFragments[candidate.connectionId] = fragment;
    final freshCandidate = fragment.toCandidate(candidate.connectionId);
    if (freshCandidate.name.trim().isEmpty ||
        (filterByV15Advertisement && !_filter.matches(freshCandidate))) {
      return;
    }
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
  }

  void _onScanError(Object error, StackTrace stackTrace, int generation) {
    if (!_isCurrentScan(generation)) {
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
  }

  bool _isCurrentScan(int generation) =>
      !_isDisposed && _state.isScanning && generation == _scanGeneration;

  @override
  void dispose() {
    _isDisposed = true;
    ++_scanGeneration;
    _stopExpiryTimer();
    _advertisementFragments.clear();
    unawaited(_scanSubscription?.cancel());
    super.dispose();
  }
}

/// Android can expose the V1.5 primary advertisement and scan response as
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
