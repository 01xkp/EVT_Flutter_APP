import 'package:aipin/features/device_session/domain/session_phase.dart';
import 'package:aipin/features/device_session/application/session_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('observable requires subscription and initial snapshot', () {
    expect(
      SessionPhase.subscribing.canTransitionTo(SessionPhase.observable),
      isFalse,
    );
    expect(
      SessionPhase.initialSnapshotRead.canTransitionTo(SessionPhase.observable),
      isTrue,
    );
  });

  test('interruption is a legal terminal transition from any phase', () {
    expect(
      SessionPhase.connecting.canTransitionTo(SessionPhase.interrupted),
      isTrue,
    );
  });

  test('identifies phases with an active Bluetooth connection', () {
    expect(
      const SessionState(phase: SessionPhase.connecting).hasActiveBleConnection,
      isFalse,
    );
    expect(
      const SessionState(
        phase: SessionPhase.servicesDiscovered,
      ).hasActiveBleConnection,
      isTrue,
    );
    expect(
      const SessionState(
        phase: SessionPhase.interrupted,
      ).hasActiveBleConnection,
      isFalse,
    );
  });
}
