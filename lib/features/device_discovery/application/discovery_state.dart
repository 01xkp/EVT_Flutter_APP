import 'package:aipin/core/diagnostics/evt_failure.dart';
import 'package:aipin/features/device_discovery/domain/device_candidate.dart';

class DiscoveryState {
  const DiscoveryState({
    this.isScanning = false,
    this.candidates = const [],
    this.selected,
    this.failure,
    this.isBluetoothOff = false,
  });

  static const _unset = Object();

  final bool isScanning;
  final List<DeviceCandidate> candidates;
  final DeviceCandidate? selected;
  final EvtFailure? failure;
  final bool isBluetoothOff;

  bool get connectEnabled => selected != null && failure == null;

  DiscoveryState copyWith({
    bool? isScanning,
    List<DeviceCandidate>? candidates,
    bool? isBluetoothOff,
    Object? selected = _unset,
    Object? failure = _unset,
  }) {
    return DiscoveryState(
      isScanning: isScanning ?? this.isScanning,
      candidates: candidates ?? this.candidates,
      selected: identical(selected, _unset)
          ? this.selected
          : selected as DeviceCandidate?,
      failure: identical(failure, _unset)
          ? this.failure
          : failure as EvtFailure?,
      isBluetoothOff: isBluetoothOff ?? this.isBluetoothOff,
    );
  }
}
