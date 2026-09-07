import 'package:aipin/features/device_session/application/session_state.dart';
import 'package:aipin/features/device_session/domain/device_snapshot.dart';

final class DeviceStatusViewModel {
  const DeviceStatusViewModel({
    required this.connectionLabel,
    required this.recordingLabel,
    required this.updatedAt,
    required this.canReconnect,
    this.batteryLabel,
  });

  factory DeviceStatusViewModel.from(SessionState state) {
    final snapshot = state.latestSnapshot;
    final connected = state.hasActiveBleConnection;
    return DeviceStatusViewModel(
      connectionLabel: !connected
          ? '已断开'
          : state.isObservable
          ? '已连接'
          : '已连接，待认证',
      recordingLabel: switch (snapshot?.state) {
        DeviceState.recording => '正在录音',
        DeviceState.paused => '已暂停',
        DeviceState.standby => '未在录音',
        _ => '暂时无法获取',
      },
      batteryLabel: snapshot?.batteryPercent?.toString(),
      updatedAt: snapshot?.observedAt,
      canReconnect: !connected,
    );
  }

  final String connectionLabel;
  final String recordingLabel;
  final String? batteryLabel;
  final DateTime? updatedAt;
  final bool canReconnect;
}
