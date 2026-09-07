import 'package:aipin/core/ble/ble_models.dart';
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
    this.endpointCapabilities = const {},
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
  final Map<BleLogicalEndpoint, Set<BleOperation>> endpointCapabilities;
  final EvtFailure? failure;
  final bool isRecordActionInFlight;

  bool get isObservable => phase == SessionPhase.observable;

  /// GATT discovery and response subscriptions are ready, so the app may
  /// start the mandatory 0x09 bind/authentication handshake.
  bool get isAuthenticationReady => switch (phase) {
    SessionPhase.authenticationReady ||
    SessionPhase.observable ||
    SessionPhase.observing ||
    SessionPhase.verifying ||
    SessionPhase.completed => true,
    _ => false,
  };

  bool supportsEndpoint(BleLogicalEndpoint endpoint, BleOperation operation) {
    final operations = endpointCapabilities[endpoint];
    if (operations == null) {
      return false;
    }
    return operations.contains(operation);
  }

  bool get hasActiveBleConnection => switch (phase) {
    SessionPhase.servicesDiscovered ||
    SessionPhase.subscribing ||
    SessionPhase.authenticationReady ||
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
    Map<BleLogicalEndpoint, Set<BleOperation>>? endpointCapabilities,
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
      fileCount: identical(fileCount, _unset)
          ? this.fileCount
          : fileCount as int?,
      events: events ?? this.events,
      endpointCapabilities: endpointCapabilities ?? this.endpointCapabilities,
      failure: identical(failure, _unset)
          ? this.failure
          : failure as EvtFailure?,
      isRecordActionInFlight:
          isRecordActionInFlight ?? this.isRecordActionInFlight,
    );
  }
}
