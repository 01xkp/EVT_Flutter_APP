import 'package:aipin/core/diagnostics/evt_failure.dart';
import 'package:aipin/core/protocol/device_event.dart';
import 'package:aipin/features/device_session/domain/device_session.dart';
import 'package:aipin/features/device_session/domain/device_snapshot.dart';
import 'package:aipin/features/device_session/domain/device_info.dart';
import 'package:aipin/features/device_session/domain/device_configuration.dart';
import 'package:aipin/features/device_session/domain/session_phase.dart';

class SessionState {
  const SessionState({
    required this.phase,
    this.session,
    this.latestSnapshot,
    this.deviceInfo,
    this.deviceStatus,
    this.deviceBattery,
    this.deviceStorage,
    this.privacyDurationCode,
    this.fileCount,
    this.events = const [],
    this.failure,
    this.isRecordActionInFlight = false,
  });

  static const _unset = Object();

  final SessionPhase phase;
  final DeviceSession? session;
  final DeviceSnapshot? latestSnapshot;
  final DeviceInfo? deviceInfo;
  final DeviceStatus? deviceStatus;
  final DeviceBattery? deviceBattery;
  final DeviceStorage? deviceStorage;
  final int? privacyDurationCode;
  final int? fileCount;
  final List<DeviceEvent> events;
  final EvtFailure? failure;
  final bool isRecordActionInFlight;

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
    Object? deviceInfo = _unset,
    Object? deviceStatus = _unset,
    Object? deviceBattery = _unset,
    Object? deviceStorage = _unset,
    Object? privacyDurationCode = _unset,
    Object? fileCount = _unset,
    List<DeviceEvent>? events,
    Object? failure = _unset,
    bool? isRecordActionInFlight,
  }) {
    return SessionState(
      phase: phase ?? this.phase,
      session: identical(session, _unset)
          ? this.session
          : session as DeviceSession?,
      latestSnapshot: identical(latestSnapshot, _unset)
          ? this.latestSnapshot
          : latestSnapshot as DeviceSnapshot?,
      deviceInfo: identical(deviceInfo, _unset)
          ? this.deviceInfo
          : deviceInfo as DeviceInfo?,
      deviceStatus: identical(deviceStatus, _unset)
          ? this.deviceStatus
          : deviceStatus as DeviceStatus?,
      deviceBattery: identical(deviceBattery, _unset)
          ? this.deviceBattery
          : deviceBattery as DeviceBattery?,
      deviceStorage: identical(deviceStorage, _unset)
          ? this.deviceStorage
          : deviceStorage as DeviceStorage?,
      privacyDurationCode: identical(privacyDurationCode, _unset)
          ? this.privacyDurationCode
          : privacyDurationCode as int?,
      fileCount: identical(fileCount, _unset) ? this.fileCount : fileCount as int?,
      events: events ?? this.events,
      failure: identical(failure, _unset)
          ? this.failure
          : failure as EvtFailure?,
      isRecordActionInFlight:
          isRecordActionInFlight ?? this.isRecordActionInFlight,
    );
  }
}
