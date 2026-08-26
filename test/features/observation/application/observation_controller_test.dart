import 'package:aipin/core/protocol/device_event.dart';
import 'package:aipin/features/device_session/domain/device_snapshot.dart';
import 'package:aipin/features/observation/application/observation_controller.dart';
import 'package:aipin/features/observation/domain/observation_scenario.dart';
import 'package:aipin/features/observation/domain/observation_verdict.dart';
import 'package:aipin/features/observation/domain/observation_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/device_fixtures.dart';

void main() {
  test('controller only completes a VAD run from recorded protocol facts', () {
    final controller = ObservationController(ObservationVerifier());
    controller.start(
      scenario: ObservationScenario.vadRecording,
      initialSnapshot: snapshot(state: DeviceState.standby),
    );
    controller.addEvent(event(DeviceEventKind.recordingStarted));
    controller.addEvent(event(DeviceEventKind.silenceEnded));

    final result = controller.complete(snapshot(state: DeviceState.standby));

    expect(result.verdict, ObservationVerdict.passed);
    expect(controller.state.result, result);
  });

  test('controller retains a manual observation note in the completed run', () {
    final controller = ObservationController(ObservationVerifier());
    controller.start(
      scenario: ObservationScenario.physicalFeedback,
      initialSnapshot: snapshot(),
    );
    controller.setManualNote('LED 与状态上报时间一致');

    final result = controller.complete(snapshot());

    expect(result.verdict, ObservationVerdict.passed);
    expect(controller.state.run!.manualNote, 'LED 与状态上报时间一致');
  });
}
