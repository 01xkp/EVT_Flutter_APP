import 'dart:async';
import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/ble/ble_transport.dart';
import 'package:aipin/core/ble/device_profile.dart';
import 'package:aipin/core/diagnostics/evt_failure.dart';
import 'package:aipin/core/protocol/device_event.dart';
import 'package:aipin/core/protocol/evt_frame.dart';
import 'package:aipin/core/protocol/evt_protocol_codec.dart';
import 'package:aipin/features/device_discovery/domain/device_candidate.dart';
import 'package:aipin/features/device_session/application/session_state.dart';
import 'package:aipin/features/device_session/domain/device_session.dart';
import 'package:aipin/features/device_session/domain/device_snapshot.dart';
import 'package:aipin/features/device_session/domain/session_phase.dart';
import 'package:flutter/foundation.dart';

class SessionController extends ChangeNotifier {
  SessionController(this._transport, this._profile, this._codec);

  final BleTransport _transport;
  final DeviceProfile _profile;
  final EvtProtocolCodec _codec;
  StreamSubscription<Uint8List>? _notificationSubscription;
  SessionState _state = const SessionState(
    phase: SessionPhase.environmentReady,
  );

  SessionState get state => _state;

  Future<void> connect(DeviceCandidate candidate) async {
    await _notificationSubscription?.cancel();
    _notificationSubscription = null;
    _state = const SessionState(phase: SessionPhase.environmentReady);
    _transition(SessionPhase.discovered);

    if (!_profile.isGattReady) {
      _state = _state.copyWith(failure: _profile.validationFailure);
      notifyListeners();
      return;
    }

    _transition(
      SessionPhase.connecting,
      session: DeviceSession(
        candidate: candidate,
        profile: _profile,
        startedAt: DateTime.now(),
      ),
    );
    try {
      await _transport
          .connect(candidate.id)
          .firstWhere(
            (connection) => connection == BleConnectionState.connected,
          );
      _transition(
        SessionPhase.servicesDiscovered,
        session: _state.session!.copyWith(connectedAt: DateTime.now()),
      );
      final services = await _transport.discoverServices(candidate.id);
      if (!_hasRequiredEndpoints(services)) {
        _fail(EvtFailure.access(message: '设备缺少所需的状态读取或订阅特征。'));
        return;
      }

      _transition(SessionPhase.subscribing);
      _notificationSubscription = _transport
          .subscribe(_notifyCharacteristic(candidate.id))
          .listen(_onNotification, onError: _onTransportError);
      _transition(SessionPhase.initialSnapshotRead);
      unawaited(_requestInitialRead(candidate.id));
    } catch (error) {
      _interrupt(error);
    }
  }

  void completeInitialRead(List<int> bytes) {
    if (_state.phase != SessionPhase.initialSnapshotRead) {
      return;
    }
    final result = _codec.decode(bytes);
    if (!result.isSuccess) {
      _state = _state.copyWith(failure: result.failure);
      notifyListeners();
      return;
    }
    final snapshot = _snapshotFromFrame(
      result.value!,
      source: '首读 0x${result.value!.command.toRadixString(16).toUpperCase()}',
    );
    if (snapshot == null) {
      _state = _state.copyWith(
        failure: EvtFailure.protocol(message: '首读返回不包含可验证状态。'),
      );
      notifyListeners();
      return;
    }
    _transition(
      SessionPhase.observable,
      latestSnapshot: snapshot,
      session: _state.session?.copyWith(observableAt: DateTime.now()),
    );
  }

  Future<void> disconnect() async {
    final session = _state.session;
    await _notificationSubscription?.cancel();
    _notificationSubscription = null;
    if (session != null) {
      await _transport.disconnect(session.candidate.id);
    }
    if (_state.phase != SessionPhase.completed) {
      _transition(SessionPhase.interrupted);
    }
  }

  Future<void> _requestInitialRead(String deviceId) async {
    try {
      final bytes = await _transport.read(_readCharacteristic(deviceId));
      completeInitialRead(bytes);
    } catch (error) {
      if (_state.phase == SessionPhase.initialSnapshotRead) {
        _fail(_failureFor(error, fallback: '状态首读失败。'));
      }
    }
  }

  void _onNotification(Uint8List bytes) {
    final result = _codec.decode(bytes);
    if (!result.isSuccess) {
      _state = _state.copyWith(failure: result.failure);
      notifyListeners();
      return;
    }
    final frame = result.value!;
    final event = DeviceEvent.fromFrame(frame, source: '状态订阅');
    final snapshot = _snapshotFromFrame(
      frame,
      source: '状态订阅 0x${frame.command.toRadixString(16).toUpperCase()}',
    );
    _state = _state.copyWith(
      events: List.unmodifiable([..._state.events, event]),
      latestSnapshot: snapshot ?? _state.latestSnapshot,
    );
    notifyListeners();
  }

  void _onTransportError(Object error, StackTrace stackTrace) {
    _interrupt(error);
  }

  DeviceSnapshot? _snapshotFromFrame(EvtFrame frame, {required String source}) {
    switch (frame.command) {
      case 0x91:
        if (frame.content.length < 2) {
          return null;
        }
        final charging = frame.content[1] == 1;
        return DeviceSnapshot(
          state: charging ? DeviceState.charging : DeviceState.unknown,
          observedAt: DateTime.now(),
          source: source,
          batteryPercent: frame.content[0],
          isCharging: charging,
        );
      case 0x87:
        if (frame.content.isEmpty) {
          return null;
        }
        return DeviceSnapshot(
          state: frame.content.first == 1
              ? DeviceState.recording
              : DeviceState.standby,
          observedAt: DateTime.now(),
          source: source,
        );
      default:
        return null;
    }
  }

  bool _hasRequiredEndpoints(List<BleService> services) {
    return _hasEndpoint(services, _profile.readEndpoint) &&
        _hasEndpoint(services, _profile.notifyEndpoint);
  }

  bool _hasEndpoint(List<BleService> services, BleEndpoint endpoint) {
    return services.any(
      (service) =>
          service.uuid.toUpperCase() == endpoint.serviceUuid.toUpperCase() &&
          service.characteristicUuids.any(
            (uuid) =>
                uuid.toUpperCase() == endpoint.characteristicUuid.toUpperCase(),
          ),
    );
  }

  BleCharacteristic _readCharacteristic(String deviceId) {
    return _characteristic(deviceId, _profile.readEndpoint);
  }

  BleCharacteristic _notifyCharacteristic(String deviceId) {
    return _characteristic(deviceId, _profile.notifyEndpoint);
  }

  BleCharacteristic _characteristic(String deviceId, BleEndpoint endpoint) {
    return BleCharacteristic(
      deviceId: deviceId,
      serviceUuid: endpoint.serviceUuid,
      characteristicUuid: endpoint.characteristicUuid,
    );
  }

  void _transition(
    SessionPhase next, {
    DeviceSession? session,
    DeviceSnapshot? latestSnapshot,
  }) {
    if (!_state.phase.canTransitionTo(next)) {
      _fail(EvtFailure.validation(message: '非法会话状态迁移。'));
      return;
    }
    _state = _state.copyWith(
      phase: next,
      session: session ?? _state.session,
      latestSnapshot: latestSnapshot ?? _state.latestSnapshot,
      failure: null,
    );
    notifyListeners();
  }

  void _interrupt(Object error) {
    _fail(_failureFor(error, fallback: '连接或服务发现中断。'), interrupt: true);
  }

  void _fail(EvtFailure failure, {bool interrupt = false}) {
    _state = _state.copyWith(
      phase: interrupt ? SessionPhase.interrupted : _state.phase,
      failure: failure,
    );
    notifyListeners();
  }

  EvtFailure _failureFor(Object error, {required String fallback}) {
    return error is BleTransportException
        ? error.failure
        : EvtFailure.transport(message: fallback, detail: '$error');
  }

  @override
  void dispose() {
    unawaited(_notificationSubscription?.cancel());
    super.dispose();
  }
}
