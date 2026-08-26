import 'package:aipin/core/diagnostics/evt_failure.dart';
import 'package:aipin/core/protocol/device_event.dart';
import 'package:aipin/features/device_session/domain/device_session.dart';
import 'package:aipin/features/device_session/domain/device_snapshot.dart';
import 'package:aipin/features/device_session/domain/session_phase.dart';

class SessionState {
  const SessionState({
    required this.phase,
    this.session,
    this.latestSnapshot,
    this.events = const [],
    this.failure,
  });

  static const _unset = Object();

  final SessionPhase phase;
  final DeviceSession? session;
  final DeviceSnapshot? latestSnapshot;
  final List<DeviceEvent> events;
  final EvtFailure? failure;

  bool get isObservable => phase == SessionPhase.observable;

  bool get hasActiveBleConnection => switch (phase) {
    SessionPhase.servicesDiscovered ||
    SessionPhase.subscribing ||
    SessionPhase.initialSnapshotRead ||
    SessionPhase.observable ||
    SessionPhase.observing ||
    SessionPhase.verifying ||
    SessionPhase.completed => true,
    _ => false,
  };

  SessionState copyWith({
    SessionPhase? phase,
    Object? session = _unset,
    Object? latestSnapshot = _unset,
    List<DeviceEvent>? events,
    Object? failure = _unset,
  }) {
    return SessionState(
      phase: phase ?? this.phase,
      session: identical(session, _unset)
          ? this.session
          : session as DeviceSession?,
      latestSnapshot: identical(latestSnapshot, _unset)
          ? this.latestSnapshot
          : latestSnapshot as DeviceSnapshot?,
      events: events ?? this.events,
      failure: identical(failure, _unset)
          ? this.failure
          : failure as EvtFailure?,
    );
  }
}
