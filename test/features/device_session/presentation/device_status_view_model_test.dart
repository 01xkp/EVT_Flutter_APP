import 'package:aipin/features/device_session/application/session_state.dart';
import 'package:aipin/features/device_session/domain/device_snapshot.dart';
import 'package:aipin/features/device_session/domain/session_phase.dart';
import 'package:aipin/features/device_session/presentation/device_status_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recording snapshot maps to ordinary consumer status', () {
    final viewModel = DeviceStatusViewModel.from(
      SessionState(
        phase: SessionPhase.observable,
        latestSnapshot: DeviceSnapshot(
          state: DeviceState.recording,
          observedAt: DateTime(2026, 8, 21, 9, 41),
          source: 'test',
        ),
      ),
    );

    expect(viewModel.connectionLabel, '已连接');
    expect(viewModel.recordingLabel, '正在录音');
    expect(viewModel.canReconnect, isFalse);
  });
}
