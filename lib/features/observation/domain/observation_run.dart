import 'package:evt_ble_app/core/protocol/device_event.dart';
import 'package:evt_ble_app/features/device_session/domain/device_snapshot.dart';
import 'package:evt_ble_app/features/observation/domain/observation_scenario.dart';

class ObservationRun {
  ObservationRun({
    required this.scenario,
    required this.initialSnapshot,
    this.finalSnapshot,
    this.events = const [],
    this.manualNote,
    DateTime? startedAt,
  }) : startedAt = startedAt ?? DateTime.now();

  final ObservationScenario scenario;
  final DeviceSnapshot initialSnapshot;
  final DeviceSnapshot? finalSnapshot;
  final List<DeviceEvent> events;
  final String? manualNote;
  final DateTime startedAt;

  ObservationRun copyWith({
    DeviceSnapshot? finalSnapshot,
    List<DeviceEvent>? events,
    Object? manualNote = _unset,
  }) {
    return ObservationRun(
      scenario: scenario,
      initialSnapshot: initialSnapshot,
      finalSnapshot: finalSnapshot ?? this.finalSnapshot,
      events: events ?? this.events,
      manualNote: identical(manualNote, _unset)
          ? this.manualNote
          : manualNote as String?,
      startedAt: startedAt,
    );
  }

  static const _unset = Object();
}
