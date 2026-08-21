import 'dart:async';

import 'package:evt_ble_app/core/ble/ble_transport.dart';
import 'package:evt_ble_app/core/diagnostics/evt_failure.dart';
import 'package:evt_ble_app/features/device_discovery/application/discovery_state.dart';
import 'package:evt_ble_app/features/device_discovery/domain/advertisement_filter.dart';
import 'package:evt_ble_app/features/device_discovery/domain/device_candidate.dart';
import 'package:flutter/foundation.dart';

class DiscoveryController extends ChangeNotifier {
  DiscoveryController(this._transport, this._filter);

  final BleTransport _transport;
  final AdvertisementFilter _filter;
  StreamSubscription<DeviceCandidate>? _scanSubscription;
  DiscoveryState _state = const DiscoveryState();

  DiscoveryState get state => _state;

  void start() {
    if (_state.isScanning) {
      return;
    }
    _state = _state.copyWith(isScanning: true, failure: null);
    notifyListeners();
    _scanSubscription = _transport.scan().listen(
      _onCandidate,
      onError: _onScanError,
      onDone: () {
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

  Future<void> stop() async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    if (_state.isScanning) {
      _state = _state.copyWith(isScanning: false);
      notifyListeners();
    }
  }

  void _onCandidate(DeviceCandidate candidate) {
    if (!_filter.matches(candidate)) {
      return;
    }
    final candidates = [
      for (final existing in _state.candidates)
        if (existing.id != candidate.id) existing,
      candidate,
    ]..sort((left, right) => right.rssi.compareTo(left.rssi));
    final selected = _state.selected?.id == candidate.id
        ? candidate
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
    );
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_scanSubscription?.cancel());
    super.dispose();
  }
}
