import 'package:evt_ble_app/core/ble/device_profile.dart';
import 'package:evt_ble_app/features/device_discovery/domain/device_candidate.dart';

class DeviceSession {
  const DeviceSession({
    required this.candidate,
    required this.profile,
    required this.startedAt,
    this.connectedAt,
    this.observableAt,
  });

  final DeviceCandidate candidate;
  final DeviceProfile profile;
  final DateTime startedAt;
  final DateTime? connectedAt;
  final DateTime? observableAt;

  DeviceSession copyWith({DateTime? connectedAt, DateTime? observableAt}) {
    return DeviceSession(
      candidate: candidate,
      profile: profile,
      startedAt: startedAt,
      connectedAt: connectedAt ?? this.connectedAt,
      observableAt: observableAt ?? this.observableAt,
    );
  }
}
