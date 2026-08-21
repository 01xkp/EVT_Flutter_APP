import 'package:evt_ble_app/core/protocol/device_event.dart';
import 'package:evt_ble_app/features/device_session/domain/device_snapshot.dart';
import 'package:evt_ble_app/features/observation/domain/observation_run.dart';
import 'package:evt_ble_app/features/observation/domain/observation_scenario.dart';
import 'package:evt_ble_app/features/observation/domain/observation_verdict.dart';
import 'package:evt_ble_app/features/observation/domain/observation_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/device_fixtures.dart';

void main() {
  final verifier = ObservationVerifier();

  test('VAD passes only after recording then silence return to standby', () {
    final result = verifier.verify(
      ObservationRun(
        scenario: ObservationScenario.vadRecording,
        initialSnapshot: snapshot(state: DeviceState.standby),
        events: [
          event(DeviceEventKind.recordingStarted),
          event(DeviceEventKind.silenceEnded),
        ],
        finalSnapshot: snapshot(state: DeviceState.standby),
      ),
    );

    expect(result.verdict, ObservationVerdict.passed);
  });

  test('VAD fails when its final state remains recording', () {
    final result = verifier.verify(
      ObservationRun(
        scenario: ObservationScenario.vadRecording,
        initialSnapshot: snapshot(state: DeviceState.standby),
        events: [
          event(DeviceEventKind.recordingStarted),
          event(DeviceEventKind.silenceEnded),
        ],
        finalSnapshot: snapshot(state: DeviceState.recording),
      ),
    );

    expect(result.verdict, ObservationVerdict.failed);
  });

  test('missing standby power is unverifiable instead of passed', () {
    final result = verifier.verify(
      ObservationRun(
        scenario: ObservationScenario.standbyPower,
        initialSnapshot: snapshot(),
        finalSnapshot: snapshot(),
      ),
    );

    expect(result.verdict, ObservationVerdict.unverifiable);
    expect(result.missingFields, contains('standbyPowerMilliwatts'));
  });

  test('physical feedback requires an explicit human note', () {
    final result = verifier.verify(
      ObservationRun(
        scenario: ObservationScenario.physicalFeedback,
        initialSnapshot: snapshot(),
        finalSnapshot: snapshot(),
      ),
    );

    expect(result.verdict, ObservationVerdict.unverifiable);
    expect(result.missingFields, contains('manualNote'));
  });

  test('unknown protocol events make an observation unverifiable', () {
    final result = verifier.verify(
      ObservationRun(
        scenario: ObservationScenario.vadRecording,
        initialSnapshot: snapshot(),
        events: [event(DeviceEventKind.unknown)],
        finalSnapshot: snapshot(),
      ),
    );

    expect(result.verdict, ObservationVerdict.unverifiable);
  });
}
