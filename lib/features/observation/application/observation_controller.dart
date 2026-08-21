import 'package:evt_ble_app/core/protocol/device_event.dart';
import 'package:evt_ble_app/features/device_session/domain/device_snapshot.dart';
import 'package:evt_ble_app/features/observation/domain/observation_run.dart';
import 'package:evt_ble_app/features/observation/domain/observation_scenario.dart';
import 'package:evt_ble_app/features/observation/domain/observation_verifier.dart';
import 'package:flutter/foundation.dart';

class ObservationState {
  const ObservationState({this.run, this.result});

  final ObservationRun? run;
  final VerificationResult? result;

  bool get isRunning => run != null && result == null;
}

class ObservationController extends ChangeNotifier {
  ObservationController(this._verifier);

  final ObservationVerifier _verifier;
  ObservationState _state = const ObservationState();

  ObservationState get state => _state;

  void start({
    required ObservationScenario scenario,
    required DeviceSnapshot initialSnapshot,
  }) {
    _state = ObservationState(
      run: ObservationRun(scenario: scenario, initialSnapshot: initialSnapshot),
    );
    notifyListeners();
  }

  void addEvent(DeviceEvent event) {
    final run = _state.run;
    if (run == null || _state.result != null) {
      return;
    }
    _state = ObservationState(
      run: run.copyWith(events: [...run.events, event]),
    );
    notifyListeners();
  }

  void setManualNote(String value) {
    final run = _state.run;
    if (run == null || _state.result != null) {
      return;
    }
    _state = ObservationState(run: run.copyWith(manualNote: value));
    notifyListeners();
  }

  VerificationResult complete(DeviceSnapshot finalSnapshot) {
    final run = _state.run;
    if (run == null) {
      throw StateError('观察尚未开始。');
    }
    final completedRun = run.copyWith(finalSnapshot: finalSnapshot);
    final result = _verifier.verify(completedRun);
    _state = ObservationState(run: completedRun, result: result);
    notifyListeners();
    return result;
  }
}
