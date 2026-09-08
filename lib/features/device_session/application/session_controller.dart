import 'dart:async';
import 'dart:math';
import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/ble/ble_transport.dart';
import 'package:aipin/core/ble/device_profile.dart';
import 'package:aipin/core/diagnostics/evt_failure.dart';
import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/core/protocol/device_event.dart';
import 'package:aipin/core/protocol/evt_command_client.dart';
import 'package:aipin/core/protocol/evt_frame.dart';
import 'package:aipin/core/protocol/evt_protocol_contract.dart';
import 'package:aipin/core/protocol/evt_protocol_codec.dart';
import 'package:aipin/features/device_session/data/device_protocol_repository.dart';
import 'package:aipin/features/device_session/domain/device_configuration.dart';
import 'package:aipin/features/device_session/domain/device_permission.dart';
import 'package:aipin/features/device_session/domain/evt_legacy_security_gateway.dart';
import 'package:aipin/features/device_session/domain/device_file.dart';
import 'package:aipin/features/device_session/domain/device_file_transfer_gateway.dart';
import 'package:aipin/features/device_session/domain/device_info.dart';
import 'package:aipin/features/device_discovery/domain/device_candidate.dart';
import 'package:aipin/features/device_session/application/session_state.dart';
import 'package:aipin/features/device_session/domain/device_session.dart';
import 'package:aipin/features/device_session/domain/device_snapshot.dart';
import 'package:aipin/features/device_session/domain/session_phase.dart';
import 'package:flutter/foundation.dart';

class SessionController extends ChangeNotifier
    implements DeviceFileTransferGateway, EvtLegacySecurityGateway {
  SessionController(
    this._transport,
    this._profile,
    this._codec, {
    SafeAppLogger? logger,
    this._legacySecurityResponseTimeout = const Duration(seconds: 2),
    this._fileListResponseTimeout = const Duration(seconds: 2),
    this._fileTransferIdleTimeout = const Duration(seconds: 15),
    this._permissionGate,
  }) : _logger = logger ?? const DebugSafeAppLogger(scope: 'SESSION');

  static const _connectionSetupTimeout = Duration(seconds: 15);
  static const _operationTimeout = Duration(seconds: 15);
  static const _notificationSetupTimeout = Duration(seconds: 8);
  // The largest legal 0x81 indication is 133 bytes, plus the ATT header.
  static const _v3AdmissionMinimumAttMtu = 136;
  static const _evtResponseCommandByEndpoint = <BleLogicalEndpoint, int>{
    BleLogicalEndpoint.fa10Fa11: 0x81,
    BleLogicalEndpoint.fa10Fa12: 0x82,
    BleLogicalEndpoint.fa10Fa15: 0x85,
    BleLogicalEndpoint.fa10Fa16: 0x86,
    BleLogicalEndpoint.fa10Fa17: 0x87,
    BleLogicalEndpoint.fa10Fa19: 0x89,
    BleLogicalEndpoint.fb10Fb11: 0x91,
    BleLogicalEndpoint.ff10Ff11: 0xA1,
    BleLogicalEndpoint.ff10Ff12: 0xA2,
    BleLogicalEndpoint.ff10Ff13: 0x23,
  };

  final BleTransport _transport;
  final DeviceProfile _profile;
  final EvtProtocolCodec _codec;
  final SafeAppLogger _logger;
  final Duration _legacySecurityResponseTimeout;
  final Duration _fileListResponseTimeout;
  final Duration _fileTransferIdleTimeout;
  final DevicePermissionGate? _permissionGate;
  StreamSubscription<BleConnectionState>? _connectionSubscription;
  final List<StreamSubscription<Uint8List>> _notificationSubscriptions = [];
  final Set<String> _subscribedEndpointKeys = <String>{};
  final Map<String, Future<void>> _subscriptionReadiness =
      <String, Future<void>>{};
  StreamController<Uint8List>? _responseController;
  EvtCommandClient? _commandClient;
  DeviceProtocolRepository? _protocolRepository;
  Future<void>? _deviceDetailsRefresh;
  Future<void>? _closeFuture;
  Future<void>? _transportCloseFuture;
  int? _attMtu;
  int _connectionAttempt = 0;
  var _isDisposed = false;
  var _changeNotifierDisposed = false;
  SessionState _state = const SessionState(
    phase: SessionPhase.environmentReady,
  );

  SessionState get state => _state;

  Future<DeviceInfo> readDeviceInfo() async {
    _requireDevicePermission(DevicePermission.status);
    _requireAuthenticationReadyEndpoint(
      BleLogicalEndpoint.fa10Fa11,
      BleOperation.write,
    );
    _requireAuthenticationReadyEndpoint(
      BleLogicalEndpoint.fa10Fa11,
      BleOperation.indicate,
    );
    await _ensureResponseSubscription(
      BleLogicalEndpoint.fa10Fa11,
      critical: true,
    );
    // CCC registration can outlive the V1 authentication window. Recheck
    // immediately before scheduling the protected device-info request.
    _requireDevicePermission(DevicePermission.status);
    return _requireProtocol().readDeviceInfo();
  }

  Future<void> writeConfiguration(DeviceConfiguration configuration) =>
      _writeConfiguration(configuration);

  Future<void> _writeConfiguration(
    DeviceConfiguration configuration, {
    bool refreshDetails = true,
  }) async {
    _requireDevicePermission(DevicePermission.configuration);
    _requireCommandEndpoint(BleLogicalEndpoint.fa10Fa12, BleOperation.indicate);
    await _ensureResponseSubscription(
      BleLogicalEndpoint.fa10Fa12,
      critical: true,
    );
    _requireDevicePermission(DevicePermission.configuration);
    await _requireProtocol().writeConfiguration(configuration);
    _cacheConfigurationTemplate(configuration);
    if (refreshDetails) {
      await refreshDeviceDetails(const {DevicePermission.configuration});
    }
  }

  Future<void> _writeAuthenticationConfiguration(
    DeviceConfiguration configuration,
  ) async {
    _requireDevicePermission(DevicePermission.configuration);
    _requireAuthenticationReadyEndpoint(
      BleLogicalEndpoint.fa10Fa12,
      BleOperation.write,
    );
    _requireAuthenticationReadyEndpoint(
      BleLogicalEndpoint.fa10Fa12,
      BleOperation.indicate,
    );
    await _ensureResponseSubscription(
      BleLogicalEndpoint.fa10Fa12,
      critical: true,
    );
    _requireDevicePermission(DevicePermission.configuration);
    await _requireProtocol().writeConfiguration(configuration);
    _cacheConfigurationTemplate(configuration);
  }

  void _cacheConfigurationTemplate(DeviceConfiguration configuration) {
    _logger.info(
      'configuration_applied',
      fields: {
        'duration_seconds': configuration.recordDurationSeconds,
        'record_mode': configuration.recordMode,
        'record_type': configuration.recordType,
      },
    );
  }

  Future<DeviceStatus> readStatus() async {
    _requireDevicePermission(DevicePermission.status);
    _requireCommandEndpoint(BleLogicalEndpoint.fa10Fa16, BleOperation.indicate);
    await _ensureResponseSubscription(
      BleLogicalEndpoint.fa10Fa16,
      critical: true,
    );
    _requireDevicePermission(DevicePermission.status);
    final status = await _requireProtocol().readStatus();
    _updateDeviceDetails(deviceStatus: status);
    return status;
  }

  Future<void> setRecordConsent(bool granted) async {
    _requireDevicePermission(DevicePermission.configuration);
    _requireCommandEndpoint(BleLogicalEndpoint.fa10Fa16, BleOperation.indicate);
    await _ensureResponseSubscription(
      BleLogicalEndpoint.fa10Fa16,
      critical: true,
    );
    _requireDevicePermission(DevicePermission.configuration);
    await _requireProtocol().setRecordConsent(granted);
    final actual = await readStatus();
    if (actual.recordConsent != granted) {
      throw StateError('设备录音授权状态未按请求更新。');
    }
    _logger.info('record_consent_verified', fields: {'granted': granted});
  }

  Future<void> setPrivacyDuration(int durationCode) async {
    _requireDevicePermission(DevicePermission.configuration);
    _requireCommandEndpoint(BleLogicalEndpoint.fa10Fa16, BleOperation.indicate);
    await _ensureResponseSubscription(
      BleLogicalEndpoint.fa10Fa16,
      critical: true,
    );
    _requireDevicePermission(DevicePermission.configuration);
    await _requireProtocol().setPrivacyDuration(durationCode);
    final actual = await readPrivacyDuration();
    if (actual != durationCode) {
      throw StateError('设备隐私时长未按请求更新。');
    }
    _logger.info(
      'privacy_duration_verified',
      fields: {'duration_code': actual},
    );
  }

  Future<int> readPrivacyDuration() async {
    _requireDevicePermission(DevicePermission.configuration);
    _requireCommandEndpoint(BleLogicalEndpoint.fa10Fa16, BleOperation.indicate);
    await _ensureResponseSubscription(
      BleLogicalEndpoint.fa10Fa16,
      critical: true,
    );
    _requireDevicePermission(DevicePermission.configuration);
    final durationCode = await _requireProtocol().readPrivacyDuration();
    _updateDeviceDetails(privacyDurationCode: durationCode);
    return durationCode;
  }

  Future<void> refreshDeviceDetails(Set<DevicePermission> permissions) {
    final pending = _deviceDetailsRefresh;
    if (pending != null) {
      return pending;
    }
    final authorizedPermissions = _authorizedPermissions(permissions);
    if (authorizedPermissions.isEmpty) {
      return Future<void>.value();
    }
    final work = _refreshDeviceDetails(authorizedPermissions);
    _deviceDetailsRefresh = work;
    return work.whenComplete(() {
      if (identical(_deviceDetailsRefresh, work)) {
        _deviceDetailsRefresh = null;
      }
    });
  }

  Future<EvtFrame> setRecordAction(int action) async {
    _requireDevicePermission(DevicePermission.configuration);
    _requireCommandEndpoint(BleLogicalEndpoint.fa10Fa17, BleOperation.indicate);
    await _ensureResponseSubscription(
      BleLogicalEndpoint.fa10Fa17,
      critical: true,
    );
    _requireDevicePermission(DevicePermission.configuration);
    return _setRecordAction(action);
  }

  @override
  Future<bool> executeEvtLegacySecurity(
    EvtLegacySecurityRequest request,
  ) async {
    _requireAuthenticationReadyEndpoint(
      BleLogicalEndpoint.fa10Fa19,
      BleOperation.write,
    );
    _requireAuthenticationReadyEndpoint(
      BleLogicalEndpoint.fa10Fa19,
      BleOperation.indicate,
    );
    await _ensureResponseSubscription(
      BleLogicalEndpoint.fa10Fa19,
      critical: true,
    );
    try {
      return await _requireProtocol().executeEvtLegacySecurity(request);
    } catch (error, stackTrace) {
      // V1 only returns BindResult. Without an action or transaction id, a
      // late response cannot be distinguished from the next 0x09 operation.
      await _invalidateSessionForAmbiguousProtocolResult(
        event: 'legacy_security_result_uncertain',
        message: '设备认证结果未确认，已断开连接，请重新连接后重试。',
        fields: {
          'action': request.action.name,
          'error': error.runtimeType.toString(),
        },
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> synchronizeAfterAuthentication(
    Set<DevicePermission> permissions,
  ) async {
    final connectionAttempt = _connectionAttempt;
    if (_state.isObservable) {
      await refreshDeviceDetails(permissions);
      return;
    }
    _requireDevicePermission(DevicePermission.status);
    _requireDevicePermission(DevicePermission.configuration);
    _requireAuthenticationReadyEndpoint(
      BleLogicalEndpoint.fa10Fa11,
      BleOperation.write,
    );
    _requireAuthenticationReadyEndpoint(
      BleLogicalEndpoint.fa10Fa11,
      BleOperation.indicate,
    );
    final repository = _requireProtocol();
    final deviceId = _state.session?.candidate.connectionId;
    late final int mtu;
    late final DeviceInfo info;
    late final DeviceConfiguration configuration;
    try {
      await _ensureResponseSubscription(
        BleLogicalEndpoint.fa10Fa11,
        critical: true,
      );
      _requireDevicePermission(DevicePermission.status);
      mtu = await _ensureV3AdmissionAttMtu();
      // The V1 authentication window can end while CCC/MTU setup is pending.
      // Recheck immediately before the protected 0x01 command is scheduled.
      _requireDevicePermission(DevicePermission.status);
      info = await repository.readDeviceInfo();
      if (info.capabilities.protocolVersion != 3) {
        throw BleTransportException(
          EvtFailure.protocol(
            message: '设备协议版本不受支持。',
            detail:
                '需要 ProtocolVersion=3，实际为 ${info.capabilities.protocolVersion}。',
          ),
        );
      }
      configuration = _baselineConfigurationFor(info);
      await _writeAuthenticationConfiguration(configuration);
    } catch (error) {
      if (_isCurrentConnectionAttempt(connectionAttempt) &&
          _state.phase == SessionPhase.authenticationReady) {
        _fail(
          _failureFor(error, fallback: '认证后的设备信息或配置同步失败。'),
          interrupt: true,
        );
        if (deviceId != null) {
          await _closeTransport(
            deviceId,
            expectedConnectionAttempt: connectionAttempt,
          );
        }
      }
      rethrow;
    }
    if (!_isCurrentConnectionAttempt(connectionAttempt) ||
        _state.phase != SessionPhase.authenticationReady) {
      return;
    }
    _transition(
      SessionPhase.observable,
      session: _state.session!.copyWith(observableAt: DateTime.now()),
      latestSnapshot: _snapshotFromDeviceInfo(info),
    );
    _state = _state.copyWith(deviceInfo: info);
    notifyListeners();
    _logger.info(
      'authentication_synchronization_started',
      fields: {
        'mtu': mtu,
        'permissions': permissions
            .map((permission) => permission.name)
            .join(','),
      },
    );
    await refreshDeviceDetails(permissions);
  }

  DeviceConfiguration _baselineConfigurationFor(DeviceInfo info) {
    return DeviceConfiguration(
      systemTime: DateTime.now(),
      recordDurationSeconds: 1800,
      recordMode: 1,
      recordType: 2,
      denoise: false,
      powerOff: info.powerOff,
      chargingMode: info.chargingMode,
    );
  }

  Future<EvtFrame> _setRecordAction(int action) async {
    if (_state.isRecordActionInFlight) {
      throw StateError('录音操作正在执行。');
    }
    _state = _state.copyWith(isRecordActionInFlight: true);
    notifyListeners();
    try {
      final response = await _requireProtocol().setRecordAction(action);
      final snapshot = _snapshotFromFrame(response, source: '录音控制响应');
      if (snapshot != null && _state.isObservable) {
        _state = _state.copyWith(latestSnapshot: snapshot, failure: null);
        notifyListeners();
      }
      return response;
    } catch (error) {
      _state = _state.copyWith(
        failure: _failureFor(error, fallback: '录音操作失败。'),
      );
      notifyListeners();
      rethrow;
    } finally {
      _state = _state.copyWith(isRecordActionInFlight: false);
      notifyListeners();
    }
  }

  Future<List<DeviceFile>> listFiles({
    int offset = 0,
    int pageSize = 10,
  }) async {
    _requireDevicePermission(DevicePermission.files);
    _requireCommandEndpoint(BleLogicalEndpoint.ff10Ff12, BleOperation.indicate);
    await _ensureResponseSubscription(
      BleLogicalEndpoint.ff10Ff12,
      critical: true,
    );
    _requireDevicePermission(DevicePermission.files);
    final mtu = await _ensureAttMtu(31);
    // The V1 authentication window can expire while CCC or MTU work is
    // pending. Check again immediately before the 0x22 command is written.
    _requireDevicePermission(DevicePermission.files);
    final supportedPageSize = max(1, min(20, (mtu - 10) ~/ 21));
    try {
      return await _requireProtocol().listFiles(
        offset: offset,
        pageSize: min(pageSize, supportedPageSize),
      );
    } catch (error, stackTrace) {
      // V1.5 0xA2 does not carry the requested page offset. A late indication
      // therefore cannot be safely distinguished from a later 0x22 request.
      // Reset the BLE session after any dispatched 0x22 failure before a new
      // listing can begin. That also covers an ambiguous GATT write failure.
      final timeoutError = error is EvtCommandTimeoutException ? error : null;
      final timedOut = timeoutError != null;
      await _invalidateSessionForAmbiguousProtocolResult(
        event: timedOut
            ? 'file_list_response_timeout_requires_reconnect'
            : 'file_list_response_uncertain_requires_reconnect',
        message: timedOut
            ? '设备文件列表响应超时，已断开连接以避免使用迟到数据。'
            : '设备文件列表响应异常，已断开连接以避免使用迟到数据。',
        fields: {
          'offset': offset,
          'error': error.runtimeType.toString(),
          if (timeoutError != null) 'attempts': timeoutError.attempts,
        },
      );
      Error.throwWithStackTrace(
        StateError(
          timedOut ? '设备文件列表响应超时，请重新连接设备后刷新。' : '设备文件列表响应异常，请重新连接设备后刷新。',
        ),
        stackTrace,
      );
    }
  }

  @override
  Stream<EvtDeviceFileTransferEvent> downloadEvtFile({
    required List<int> nameSlot,
    int startOffset = 0,
    int chunkSize = 0,
  }) {
    // An async* wrapper does not propagate a caller's cancellation through an
    // await-for until its child stream resumes. A silent 0x23 transfer can
    // therefore wait for the 15-second idle timer after the file screen has
    // gone away. Keep a direct subscription here so caller cancellation can
    // close the ambiguous V1.5 transfer session immediately while this layer
    // remains available to absorb the resulting source-stream error.
    late final StreamController<EvtDeviceFileTransferEvent> controller;
    StreamSubscription<EvtDeviceFileTransferEvent>? transferSubscription;
    var transferStarted = false;
    var terminalReceived = false;
    var callerCancelled = false;
    Future<void>? incompleteTransferReset;

    Future<void> resetIncompleteTransfer({
      required String event,
      required String message,
      required Object error,
    }) {
      if (!transferStarted || terminalReceived) {
        return Future<void>.value();
      }
      return incompleteTransferReset ??=
          _invalidateSessionForAmbiguousProtocolResult(
            event: event,
            message: message,
            fields: {
              'offset': startOffset,
              'error': error.runtimeType.toString(),
            },
          );
    }

    Future<void> cancelSource(
      StreamSubscription<EvtDeviceFileTransferEvent> subscription,
    ) async {
      try {
        await subscription.cancel();
      } catch (error) {
        // The transport-close error is expected after the caller leaves an
        // active stream. It has already been converted into session state by
        // resetIncompleteTransfer, so do not leak it as an unhandled zone
        // error after the consumer has cancelled.
        _logger.info(
          'file_transfer_source_cancelled',
          fields: {'error': error.runtimeType.toString()},
        );
      }
    }

    void startSource() {
      transferSubscription =
          _downloadEvtFileInternal(
            nameSlot: nameSlot,
            startOffset: startOffset,
            chunkSize: chunkSize,
            onTransferStarted: () => transferStarted = true,
            onTerminalReceived: () => terminalReceived = true,
            isCallerCancelled: () => callerCancelled,
            onIncompleteTransfer: (error) => resetIncompleteTransfer(
              event: 'file_transfer_requires_reconnect',
              message: '设备文件传输中断，已断开连接以避免接收旧数据。',
              error: error,
            ),
          ).listen(
            (event) {
              // Set this before forwarding: a listener can cancel from onData.
              if (event.isTerminal) {
                terminalReceived = true;
              }
              if (!callerCancelled && !controller.isClosed) {
                controller.add(event);
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!callerCancelled && !controller.isClosed) {
                controller.addError(error, stackTrace);
              }
            },
            onDone: () {
              if (!controller.isClosed) {
                unawaited(controller.close());
              }
            },
          );
    }

    controller = StreamController<EvtDeviceFileTransferEvent>(
      onListen: startSource,
      onCancel: () async {
        callerCancelled = true;
        // Do not await the source cancellation. Its async* body can be
        // waiting for the next Notify, while the V1.5 session must be reset
        // now to stop a late frame entering a later transfer.
        final subscription = transferSubscription;
        if (subscription != null) {
          unawaited(cancelSource(subscription));
        }
        await resetIncompleteTransfer(
          event: 'file_transfer_cancelled_requires_reconnect',
          message: '已取消设备文件传输，已断开连接以避免接收旧数据。',
          error: StateError('连续文件传输已取消。'),
        );
      },
    );
    return controller.stream;
  }

  Stream<EvtDeviceFileTransferEvent> _downloadEvtFileInternal({
    required List<int> nameSlot,
    required int startOffset,
    required int chunkSize,
    required VoidCallback onTransferStarted,
    required VoidCallback onTerminalReceived,
    required bool Function() isCallerCancelled,
    required Future<void> Function(Object error) onIncompleteTransfer,
  }) async* {
    void requireActiveCaller() {
      if (isCallerCancelled()) {
        throw StateError('设备文件传输已取消。');
      }
    }

    _requireDevicePermission(DevicePermission.files);
    _requireCommandEndpoint(BleLogicalEndpoint.ff10Ff13, BleOperation.notify);
    await _ensureResponseSubscription(
      BleLogicalEndpoint.ff10Ff13,
      critical: true,
    );
    requireActiveCaller();
    _requireDevicePermission(DevicePermission.files);
    await _ensureAttMtu(
      _requiredFileTransferMtu(startOffset: startOffset, chunkSize: chunkSize),
    );
    requireActiveCaller();
    // Do not let an expired V1 window reach the 0x23 write after an awaited
    // setup step. The per-event check below also stops an active transfer.
    _requireDevicePermission(DevicePermission.files);
    var terminalReceived = false;

    try {
      final transfer = _requireProtocol().downloadEvtFile(
        nameSlot: nameSlot,
        startOffset: startOffset,
        chunkSize: chunkSize,
      );
      onTransferStarted();
      await for (final event in transfer) {
        // The permission is checked immediately before the one and only 0x23
        // Write. Once the device has accepted that write, every following
        // Notify belongs to the same continuous transfer. A V1 auth window
        // expiring while a large file is in flight must block a later command,
        // not discard already-authorized bytes and force a needless restart.
        if (event.isTerminal) {
          terminalReceived = true;
          onTerminalReceived();
        }
        yield event;
      }
      if (!terminalReceived) {
        throw StateError('设备文件传输未返回结束帧。');
      }
    } catch (error, stackTrace) {
      await onIncompleteTransfer(error);
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      await onIncompleteTransfer(StateError('连续文件传输已取消。'));
    }
  }

  Future<void> connect(DeviceCandidate candidate) async {
    if (_isDisposed) {
      throw StateError('设备会话已关闭。');
    }
    final connectionAttempt = ++_connectionAttempt;
    final previousDeviceId = _state.session?.candidate.connectionId;
    await _connectionSubscription?.cancel();
    if (!_isCurrentConnectionAttempt(connectionAttempt)) {
      return;
    }
    _connectionSubscription = null;
    await _cancelNotificationSubscriptions();
    if (!_isCurrentConnectionAttempt(connectionAttempt)) {
      return;
    }
    await _commandClient?.close();
    if (!_isCurrentConnectionAttempt(connectionAttempt)) {
      return;
    }
    _commandClient = null;
    await _responseController?.close();
    if (!_isCurrentConnectionAttempt(connectionAttempt)) {
      return;
    }
    _responseController = null;
    _protocolRepository = null;
    _attMtu = null;
    if (previousDeviceId != null) {
      await _transport.disconnect(previousDeviceId);
      if (!_isCurrentConnectionAttempt(connectionAttempt)) {
        return;
      }
    }
    _state = const SessionState(phase: SessionPhase.environmentReady);
    _transition(SessionPhase.discovered);
    _logger.info(
      'connect_start',
      fields: {'device': _redactDeviceId(candidate.connectionId)},
    );

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
    final connected = Completer<void>();
    _connectionSubscription = _transport
        .connect(candidate.connectionId)
        .listen(
          (connection) {
            if (!_isCurrentConnectionAttempt(connectionAttempt)) {
              return;
            }
            _logger.info(
              'connection_state',
              fields: {
                'device': _redactDeviceId(candidate.connectionId),
                'state': connection.name,
              },
            );
            if (connection == BleConnectionState.connected) {
              if (!connected.isCompleted) {
                connected.complete();
              }
              return;
            }
            if (connection == BleConnectionState.disconnected &&
                !connected.isCompleted) {
              connected.completeError(
                BleTransportException(
                  EvtFailure.transport(message: '蓝牙连接在建立后立即断开。'),
                ),
              );
              return;
            }
            if (connection == BleConnectionState.disconnected &&
                _state.phase != SessionPhase.interrupted) {
              _interrupt(
                BleTransportException(
                  EvtFailure.transport(message: '蓝牙连接已断开。'),
                ),
              );
              unawaited(
                _closeTransport(
                  candidate.connectionId,
                  expectedConnectionAttempt: connectionAttempt,
                ),
              );
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!_isCurrentConnectionAttempt(connectionAttempt)) {
              return;
            }
            _logger.info(
              'connection_stream_error',
              fields: {
                'device': _redactDeviceId(candidate.connectionId),
                'error': '$error',
              },
            );
            if (!connected.isCompleted) {
              connected.completeError(error, stackTrace);
            } else if (_state.phase != SessionPhase.interrupted) {
              _interrupt(error);
              unawaited(
                _closeTransport(
                  candidate.connectionId,
                  expectedConnectionAttempt: connectionAttempt,
                ),
              );
            }
          },
          onDone: () {
            if (!_isCurrentConnectionAttempt(connectionAttempt)) {
              return;
            }
            _logger.info(
              'connection_stream_done',
              fields: {'device': _redactDeviceId(candidate.connectionId)},
            );
            if (!connected.isCompleted) {
              connected.completeError(
                BleTransportException(
                  EvtFailure.transport(message: '蓝牙连接流已结束。'),
                ),
              );
            } else if (_state.phase != SessionPhase.interrupted &&
                _state.phase != SessionPhase.completed) {
              _interrupt(
                BleTransportException(
                  EvtFailure.transport(message: '蓝牙连接流已结束。'),
                ),
              );
              unawaited(
                _closeTransport(
                  candidate.connectionId,
                  expectedConnectionAttempt: connectionAttempt,
                ),
              );
            }
          },
        );

    try {
      await connected.future.timeout(_connectionSetupTimeout);
      if (!_isCurrentConnectionAttempt(connectionAttempt) ||
          _state.phase != SessionPhase.connecting) {
        return;
      }
      _transition(
        SessionPhase.servicesDiscovered,
        session: _state.session!.copyWith(connectedAt: DateTime.now()),
      );
      final services = await _transport
          .discoverServices(candidate.connectionId)
          .timeout(_operationTimeout);
      if (!_isCurrentConnectionAttempt(connectionAttempt) ||
          _state.phase != SessionPhase.servicesDiscovered) {
        return;
      }
      final missingEndpointOperations = _missingRequiredEndpointOperations(
        services,
      );
      if (missingEndpointOperations.isNotEmpty) {
        _logger.info(
          'evt_gatt_contract_mismatch',
          fields: {'missing': missingEndpointOperations.join(',')},
        );
        _fail(
          EvtFailure.access(
            message: '设备 GATT 不符合 EVT V1.5 联调要求。',
            detail: '缺少或不支持：${missingEndpointOperations.join('、')}。',
          ),
          interrupt: true,
        );
        await _closeTransport(
          candidate.connectionId,
          expectedConnectionAttempt: connectionAttempt,
        );
        return;
      }
      _state = _state.copyWith(
        endpointCapabilities: _discoveredEndpointCapabilities(services),
      );
      notifyListeners();

      _transition(SessionPhase.subscribing);
      _responseController = StreamController<Uint8List>.broadcast();
      _commandClient = EvtCommandClient(
        transport: _transport,
        codec: _codec,
        responses: _responseController!.stream,
        beforeWrite: _admitEvtCommandWrite,
      );
      _protocolRepository = DeviceProtocolRepository(
        deviceId: candidate.connectionId,
        profile: _profile,
        transport: _transport,
        commands: _commandClient!,
        codec: _codec,
        legacySecurityResponseTimeout: _legacySecurityResponseTimeout,
        fileListResponseTimeout: _fileListResponseTimeout,
        fileTransferIdleTimeout: _fileTransferIdleTimeout,
      );
      await _subscribeEvtEndpointsBeforeAuthentication();
      if (!_isCurrentConnectionAttempt(connectionAttempt) ||
          _state.phase != SessionPhase.subscribing) {
        return;
      }
      _transition(SessionPhase.authenticationReady);
      _logger.info('session_authentication_ready', fields: {'stage': 'evt_v1'});
    } catch (error) {
      if (!_isCurrentConnectionAttempt(connectionAttempt)) {
        return;
      }
      _interrupt(error);
      await _closeTransport(
        candidate.connectionId,
        expectedConnectionAttempt: connectionAttempt,
      );
    }
  }

  Future<void> _refreshDeviceDetails(Set<DevicePermission> permissions) async {
    final repository = _protocolRepository;
    if (repository == null || !_state.isObservable) {
      return;
    }
    if (permissions.contains(DevicePermission.status)) {
      await _loadDeviceStatus(repository);
      await _loadDeviceBattery(repository);
      await _loadDeviceStorage(repository);
    }
    if (permissions.contains(DevicePermission.configuration)) {
      await _loadConfigurationTime(repository);
      await _loadPrivacyDuration(repository);
    }
    if (permissions.contains(DevicePermission.files)) {
      await _loadFileCount(repository);
    }
  }

  Future<void> _loadDeviceStatus(DeviceProtocolRepository repository) async {
    if (!_state.supportsEndpoint(
          BleLogicalEndpoint.fa10Fa16,
          BleOperation.write,
        ) ||
        !_state.supportsEndpoint(
          BleLogicalEndpoint.fa10Fa16,
          BleOperation.indicate,
        )) {
      return;
    }
    try {
      await _ensureResponseSubscription(
        BleLogicalEndpoint.fa10Fa16,
        critical: false,
      );
      _requireDevicePermission(DevicePermission.status);
      final status = await repository.readStatus();
      _updateDeviceDetails(deviceStatus: status, repository: repository);
      _logger.info('device_status_loaded');
    } catch (error) {
      _logDeviceDetailFailure('device_status_load_failed', error);
    }
  }

  Future<void> _loadDeviceBattery(DeviceProtocolRepository repository) async {
    if (!_state.supportsEndpoint(
      BleLogicalEndpoint.fb10Fb11,
      BleOperation.read,
    )) {
      return;
    }
    try {
      _requireDevicePermission(DevicePermission.status);
      final battery = await repository.readBattery();
      _updateDeviceDetails(deviceBattery: battery, repository: repository);
      _logger.info(
        'device_battery_loaded',
        fields: {'percent': battery.percent},
      );
    } catch (error) {
      _logDeviceDetailFailure('device_battery_load_failed', error);
    }
  }

  Future<void> _loadPrivacyDuration(DeviceProtocolRepository repository) async {
    if (!_state.supportsEndpoint(
          BleLogicalEndpoint.fa10Fa16,
          BleOperation.write,
        ) ||
        !_state.supportsEndpoint(
          BleLogicalEndpoint.fa10Fa16,
          BleOperation.indicate,
        )) {
      return;
    }
    try {
      await _ensureResponseSubscription(
        BleLogicalEndpoint.fa10Fa16,
        critical: false,
      );
      _requireDevicePermission(DevicePermission.configuration);
      final durationCode = await repository.readPrivacyDuration();
      _updateDeviceDetails(
        privacyDurationCode: durationCode,
        repository: repository,
      );
      _logger.info(
        'device_privacy_duration_loaded',
        fields: {'duration_code': durationCode},
      );
    } catch (error) {
      _logDeviceDetailFailure('device_privacy_duration_load_failed', error);
    }
  }

  Future<void> _loadConfigurationTime(
    DeviceProtocolRepository repository,
  ) async {
    if (!_state.supportsEndpoint(
      BleLogicalEndpoint.fa10Fa12,
      BleOperation.read,
    )) {
      return;
    }
    try {
      _requireDevicePermission(DevicePermission.configuration);
      final time = await repository.readConfigurationTime();
      _logger.info(
        'device_configuration_time_loaded',
        fields: {'utc_seconds': time.millisecondsSinceEpoch ~/ 1000},
      );
    } catch (error) {
      _logDeviceDetailFailure('device_configuration_time_load_failed', error);
    }
  }

  Future<void> _loadDeviceStorage(DeviceProtocolRepository repository) async {
    if (!_state.supportsEndpoint(
      BleLogicalEndpoint.fa10Fa15,
      BleOperation.read,
    )) {
      return;
    }
    try {
      _requireDevicePermission(DevicePermission.status);
      final storage = await repository.readStorage();
      _updateDeviceDetails(deviceStorage: storage, repository: repository);
      _logger.info(
        'device_storage_loaded',
        fields: {
          'total_mb': storage.totalMegabytes,
          'free_mb': storage.freeMegabytes,
        },
      );
    } catch (error) {
      _logDeviceDetailFailure('device_storage_load_failed', error);
    }
  }

  Future<void> _loadFileCount(DeviceProtocolRepository repository) async {
    if (!_state.supportsEndpoint(
      BleLogicalEndpoint.ff10Ff11,
      BleOperation.read,
    )) {
      return;
    }
    try {
      _requireDevicePermission(DevicePermission.files);
      final count = await repository.readFileCount();
      _updateDeviceDetails(fileCount: count, repository: repository);
      _logger.info('device_file_count_loaded', fields: {'count': count});
    } catch (error) {
      _logDeviceDetailFailure('device_file_count_load_failed', error);
    }
  }

  void _updateDeviceDetails({
    DeviceStatus? deviceStatus,
    DeviceBattery? deviceBattery,
    DeviceStorage? deviceStorage,
    int? privacyDurationCode,
    int? fileCount,
    DeviceProtocolRepository? repository,
  }) {
    if (!_state.isObservable ||
        (repository != null && !identical(_protocolRepository, repository))) {
      return;
    }
    _state = _state.copyWith(
      deviceStatus: deviceStatus ?? _state.deviceStatus,
      deviceBattery: deviceBattery ?? _state.deviceBattery,
      deviceStorage: deviceStorage ?? _state.deviceStorage,
      privacyDurationCode: privacyDurationCode ?? _state.privacyDurationCode,
      fileCount: fileCount ?? _state.fileCount,
    );
    notifyListeners();
  }

  void _logDeviceDetailFailure(String event, Object error) {
    _logger.info(event, fields: {'error': '$error'});
  }

  Future<void> disconnect() async {
    final connectionAttempt = ++_connectionAttempt;
    final session = _state.session;
    if (session != null) {
      await _closeTransport(
        session.candidate.connectionId,
        expectedConnectionAttempt: connectionAttempt,
      );
    } else {
      await _cancelNotificationSubscriptions();
      await _commandClient?.close();
      _commandClient = null;
      await _responseController?.close();
      _responseController = null;
      _protocolRepository = null;
      await _connectionSubscription?.cancel();
      _connectionSubscription = null;
    }
    if (_state.phase != SessionPhase.completed) {
      _transition(SessionPhase.interrupted);
    }
  }

  void _onNotification(Uint8List bytes) {
    final result = _codec.decode(bytes);
    if (!result.isSuccess) {
      _state = _state.copyWith(failure: result.failure);
      notifyListeners();
      _logger.info(
        'notification_decode_failure',
        fields: {
          'bytes': bytes.length,
          'message': result.failure?.message ?? 'unknown',
        },
      );
      return;
    }
    final frame = result.value!;
    final event = DeviceEvent.fromFrame(frame, source: '状态订阅');
    final status = _statusFromNotification(frame);
    final battery = _batteryFromNotification(frame);
    final storage = _storageFromNotification(frame);
    final fileCount = _fileCountFromNotification(frame);
    final snapshot = _snapshotFromFrame(
      frame,
      source: '状态订阅 0x${frame.command.toRadixString(16).toUpperCase()}',
    );
    _state = _state.copyWith(
      events: List.unmodifiable([..._state.events, event]),
      latestSnapshot: snapshot ?? _state.latestSnapshot,
      deviceStatus: status ?? _state.deviceStatus,
      deviceBattery: battery ?? _state.deviceBattery,
      deviceStorage: storage ?? _state.deviceStorage,
      fileCount: fileCount ?? _state.fileCount,
    );
    notifyListeners();
    _logger.info(
      'notification_event',
      fields: {
        'command': '0x${frame.command.toRadixString(16).padLeft(2, '0')}',
        'bytes': bytes.length,
        'event': event.kind.name,
      },
    );
  }

  DeviceStatus? _statusFromNotification(EvtFrame frame) {
    if (frame.command != 0x86 ||
        frame.content.isEmpty ||
        frame.content.first != 0x80) {
      return null;
    }
    try {
      return DeviceProtocolRepository.decodeStatusEvent(frame);
    } catch (error) {
      _logger.info('status_event_decode_failed', fields: {'error': '$error'});
      return null;
    }
  }

  DeviceBattery? _batteryFromNotification(EvtFrame frame) {
    if (frame.command != 0x91) {
      return null;
    }
    try {
      return DeviceProtocolRepository.decodeBattery(frame);
    } catch (error) {
      _logger.info('battery_event_decode_failed', fields: {'error': '$error'});
      return null;
    }
  }

  DeviceStorage? _storageFromNotification(EvtFrame frame) {
    if (frame.command != 0x85) {
      return null;
    }
    try {
      return DeviceProtocolRepository.decodeStorage(frame);
    } catch (error) {
      _logger.info('storage_event_decode_failed', fields: {'error': '$error'});
      return null;
    }
  }

  int? _fileCountFromNotification(EvtFrame frame) {
    if (frame.command != 0xA1) {
      return null;
    }
    try {
      return DeviceProtocolRepository.decodeFileCount(frame);
    } catch (error) {
      _logger.info(
        'file_count_event_decode_failed',
        fields: {'error': '$error'},
      );
      return null;
    }
  }

  void _onTransportError(
    Object error,
    StackTrace stackTrace, {
    int? expectedConnectionAttempt,
  }) {
    final connectionAttempt = expectedConnectionAttempt ?? _connectionAttempt;
    if (!_isCurrentConnectionAttempt(connectionAttempt)) {
      return;
    }
    _interrupt(error);
    final deviceId = _state.session?.candidate.connectionId;
    if (deviceId != null) {
      unawaited(
        _closeTransport(deviceId, expectedConnectionAttempt: connectionAttempt),
      );
    }
  }

  /// Registers one GATT response stream before the matching command is sent.
  Future<void> _ensureResponseSubscription(
    BleLogicalEndpoint logicalEndpoint, {
    required bool critical,
  }) async {
    final responseController = _responseController;
    if (responseController == null) {
      throw StateError('协议响应通道尚未初始化。');
    }
    if (!EvtProtocolContract.subscriptionEndpoints.contains(logicalEndpoint)) {
      EvtProtocolContract.rejectUnavailableCapability(
        '特征 ${logicalEndpoint.name} 的通知订阅',
      );
    }
    final session = _state.session;
    if (session == null || !_state.hasActiveBleConnection) {
      throw StateError('设备尚未完成连接，无法订阅协议响应。');
    }
    final connectionAttempt = _connectionAttempt;
    final supportsIndication = _state.supportsEndpoint(
      logicalEndpoint,
      BleOperation.indicate,
    );
    final supportsNotification = _state.supportsEndpoint(
      logicalEndpoint,
      BleOperation.notify,
    );
    if (!supportsIndication && !supportsNotification) {
      if (critical) {
        throw StateError('设备未提供 ${logicalEndpoint.name} 的通知或指示能力。');
      }
      _logger.info(
        'notification_subscription_skipped',
        fields: {'endpoint': logicalEndpoint.name, 'reason': 'unsupported'},
      );
      return;
    }
    final endpoint = _profile.endpoint(logicalEndpoint);
    final key = '${endpoint.serviceUuid}|${endpoint.characteristicUuid}';
    final existingReadiness = _subscriptionReadiness[key];
    if (existingReadiness != null) {
      await _awaitResponseSubscriptionReadiness(
        existingReadiness,
        logicalEndpoint: logicalEndpoint,
        critical: critical,
        connectionAttempt: connectionAttempt,
      );
      return;
    }
    if (_subscribedEndpointKeys.contains(key)) {
      return;
    }
    _subscribedEndpointKeys.add(key);
    late final StreamSubscription<Uint8List> subscription;
    subscription = _transport
        .subscribe(_characteristic(session.candidate.connectionId, endpoint))
        .listen(
          (bytes) {
            if (!_isCurrentConnectionAttempt(connectionAttempt) ||
                responseController.isClosed) {
              return;
            }
            final decoded = _codec.decode(bytes);
            if (!decoded.isSuccess) {
              _onNotification(bytes);
              return;
            }
            final frame = decoded.value!;
            if (!_isExpectedResponseForEndpoint(logicalEndpoint, frame)) {
              _logger.info(
                'notification_endpoint_mismatch',
                fields: {
                  'endpoint': logicalEndpoint.name,
                  'command':
                      '0x${frame.command.toRadixString(16).padLeft(2, '0')}',
                },
              );
              return;
            }
            responseController.add(bytes);
            if (logicalEndpoint == BleLogicalEndpoint.ff10Ff13) {
              // File payloads are consumed by the active 0x23 transfer only.
              // Retaining every chunk as a session event would duplicate audio
              // bytes, rebuild listeners per packet, and grow memory with the
              // full device file.
              return;
            }
            _onNotification(bytes);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!_isCurrentConnectionAttempt(connectionAttempt)) {
              return;
            }
            _subscribedEndpointKeys.remove(key);
            _subscriptionReadiness.remove(key);
            _notificationSubscriptions.remove(subscription);
            _logger.info(
              'notification_subscription_failed',
              fields: {'endpoint': logicalEndpoint.name, 'critical': critical},
            );
            if (critical) {
              _onTransportError(
                error,
                stackTrace,
                expectedConnectionAttempt: connectionAttempt,
              );
            }
          },
          onDone: () {
            if (!_isCurrentConnectionAttempt(connectionAttempt)) {
              return;
            }
            _subscribedEndpointKeys.remove(key);
            _subscriptionReadiness.remove(key);
            _notificationSubscriptions.remove(subscription);
            _logger.info(
              'notification_subscription_closed',
              fields: {'endpoint': logicalEndpoint.name, 'critical': critical},
            );
            if (critical && _state.hasActiveBleConnection) {
              _onTransportError(
                StateError('关键响应特征 ${logicalEndpoint.name} 的通知通道已关闭。'),
                StackTrace.current,
                expectedConnectionAttempt: connectionAttempt,
              );
            }
          },
        );
    _notificationSubscriptions.add(subscription);
    final readiness = _transport
        .awaitSubscriptionReady(
          _characteristic(session.candidate.connectionId, endpoint),
        )
        .timeout(_notificationSetupTimeout);
    _subscriptionReadiness[key] = readiness;
    _logger.info(
      'notification_subscribed',
      fields: {
        'endpoint': logicalEndpoint.name,
        'mode': supportsIndication ? 'indicate' : 'notify',
        'critical': critical,
      },
    );
    await _awaitResponseSubscriptionReadiness(
      readiness,
      logicalEndpoint: logicalEndpoint,
      critical: critical,
      subscription: subscription,
      key: key,
      connectionAttempt: connectionAttempt,
    );
  }

  Future<void> _awaitResponseSubscriptionReadiness(
    Future<void> readiness, {
    required BleLogicalEndpoint logicalEndpoint,
    required bool critical,
    required int connectionAttempt,
    StreamSubscription<Uint8List>? subscription,
    String? key,
  }) async {
    try {
      await readiness;
      if (!_isCurrentConnectionAttempt(connectionAttempt)) {
        throw StateError('蓝牙连接已切换，通知订阅结果已失效。');
      }
      _logger.info(
        'notification_subscription_confirmed',
        fields: {'endpoint': logicalEndpoint.name, 'critical': critical},
      );
    } catch (error, stackTrace) {
      if (!_isCurrentConnectionAttempt(connectionAttempt)) {
        Error.throwWithStackTrace(StateError('蓝牙连接已切换，通知订阅结果已失效。'), stackTrace);
      }
      if (key != null && identical(_subscriptionReadiness[key], readiness)) {
        _subscriptionReadiness.remove(key);
        _subscribedEndpointKeys.remove(key);
      }
      if (subscription != null) {
        _notificationSubscriptions.remove(subscription);
        await subscription.cancel();
      }
      _logger.info(
        'notification_subscription_confirmation_failed',
        fields: {
          'endpoint': logicalEndpoint.name,
          'critical': critical,
          'error': error.runtimeType.toString(),
        },
      );
      if (critical) {
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
  }

  static bool _isExpectedResponseForEndpoint(
    BleLogicalEndpoint endpoint,
    EvtFrame frame,
  ) => _evtResponseCommandByEndpoint[endpoint] == frame.command;

  /// Establishes required EVT CCCs before V1 `0x09` is sent.
  ///
  /// `FF11 / 0x21` is a compatibility-only file-count summary. It is
  /// subscribed when present, but cannot block authentication because `0x22`
  /// supplies the required file-list synchronization path.
  Future<void> _subscribeEvtEndpointsBeforeAuthentication() async {
    for (final endpoint in EvtProtocolContract.requiredSubscriptionOrder) {
      await _ensureResponseSubscription(endpoint, critical: true);
    }
    for (final endpoint in EvtProtocolContract.optionalSubscriptionOrder) {
      await _ensureResponseSubscription(endpoint, critical: false);
    }
  }

  DeviceSnapshot? _snapshotFromFrame(EvtFrame frame, {required String source}) {
    switch (frame.command) {
      case 0x87:
        try {
          DeviceProtocolRepository.validateRecordState(frame);
        } catch (error) {
          _logger.info(
            'record_state_event_decode_failed',
            fields: {'error': '$error'},
          );
          return null;
        }
        return DeviceSnapshot(
          state: switch (frame.content.first) {
            1 || 3 => DeviceState.recording,
            2 => DeviceState.paused,
            _ => DeviceState.standby,
          },
          observedAt: DateTime.now(),
          source: source,
        );
      default:
        return null;
    }
  }

  DeviceSnapshot _snapshotFromDeviceInfo(DeviceInfo info) => DeviceSnapshot(
    state: switch (info.recordStatus) {
      1 || 3 => DeviceState.recording,
      2 => DeviceState.paused,
      _ => DeviceState.standby,
    },
    observedAt: DateTime.now(),
    source: '认证后设备信息',
    batteryPercent: info.batteryLevel,
    isCharging: info.charging != 0,
  );

  List<String> _missingRequiredEndpointOperations(List<BleService> services) {
    return [
      for (final entry
          in DeviceProfile.evtV15RequiredEndpointOperations.entries)
        for (final operation in entry.value)
          if (!_hasEndpoint(services, _profile.endpoint(entry.key), operation))
            '${entry.key.name}.${operation.name}',
    ];
  }

  bool _hasEndpoint(
    List<BleService> services,
    BleEndpoint endpoint,
    BleOperation operation,
  ) {
    final characteristic = _discoveredCharacteristic(services, endpoint);
    return characteristic?.operations.contains(operation) ?? false;
  }

  BleDiscoveredCharacteristic? _discoveredCharacteristic(
    List<BleService> services,
    BleEndpoint endpoint,
  ) {
    for (final service in services) {
      if (service.uuid.toUpperCase() == endpoint.serviceUuid.toUpperCase()) {
        return service.characteristic(endpoint.characteristicUuid);
      }
    }
    return null;
  }

  Map<BleLogicalEndpoint, Set<BleOperation>> _discoveredEndpointCapabilities(
    List<BleService> services,
  ) {
    final capabilities = <BleLogicalEndpoint, Set<BleOperation>>{};
    for (final entry in _profile.endpoints.entries) {
      final characteristic = _discoveredCharacteristic(services, entry.value);
      if (characteristic != null) {
        capabilities[entry.key] = Set.unmodifiable(characteristic.operations);
      }
    }
    return Map.unmodifiable(capabilities);
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
    final previous = _state.phase;
    _state = _state.copyWith(
      phase: next,
      session: session ?? _state.session,
      latestSnapshot: latestSnapshot ?? _state.latestSnapshot,
      failure: null,
    );
    notifyListeners();
    _logger.info(
      'phase_changed',
      fields: {'from': previous.name, 'to': next.name},
    );
  }

  void _interrupt(Object error) {
    _logger.info('session_interrupted', fields: {'error': '$error'});
    _fail(_failureFor(error, fallback: '连接或服务发现中断。'), interrupt: true);
  }

  void _fail(EvtFailure failure, {bool interrupt = false}) {
    _logger.info(
      'session_failure',
      fields: {
        'kind': failure.kind.name,
        'message': failure.message,
        'detail': failure.detail ?? 'none',
        'interrupt': interrupt,
      },
    );
    _state = _state.copyWith(
      phase: interrupt ? SessionPhase.interrupted : _state.phase,
      failure: failure,
    );
    notifyListeners();
  }

  /// Clears a GATT session when V1.5 cannot correlate a delayed response or
  /// an old continuous file stream with a future request.
  Future<void> _invalidateSessionForAmbiguousProtocolResult({
    required String event,
    required String message,
    required Map<String, Object?> fields,
  }) async {
    final connectionAttempt = _connectionAttempt;
    final deviceId = _state.session?.candidate.connectionId;
    _logger.info(event, fields: fields);
    if (deviceId == null || !_state.hasActiveBleConnection) {
      return;
    }
    _fail(EvtFailure.transport(message: message), interrupt: true);
    await _closeTransport(
      deviceId,
      expectedConnectionAttempt: connectionAttempt,
    );
  }

  Future<void> _closeTransport(
    String deviceId, {
    int? expectedConnectionAttempt,
  }) {
    final pending = _transportCloseFuture;
    if (pending != null) {
      return pending;
    }
    if (!_ownsConnectionForCleanup(expectedConnectionAttempt)) {
      return Future<void>.value();
    }
    late final Future<void> closing;
    closing =
        _closeTransportInternal(
          deviceId,
          expectedConnectionAttempt: expectedConnectionAttempt,
        ).whenComplete(() {
          if (identical(_transportCloseFuture, closing)) {
            _transportCloseFuture = null;
          }
        });
    _transportCloseFuture = closing;
    return closing;
  }

  Future<void> _closeTransportInternal(
    String deviceId, {
    int? expectedConnectionAttempt,
  }) async {
    if (!_ownsConnectionForCleanup(expectedConnectionAttempt)) {
      return;
    }
    await _cancelNotificationSubscriptions();
    if (!_ownsConnectionForCleanup(expectedConnectionAttempt)) {
      return;
    }
    final commandClient = _commandClient;
    _commandClient = null;
    await commandClient?.close();
    if (!_ownsConnectionForCleanup(expectedConnectionAttempt)) {
      return;
    }
    final responseController = _responseController;
    _responseController = null;
    await responseController?.close();
    if (!_ownsConnectionForCleanup(expectedConnectionAttempt)) {
      return;
    }
    _protocolRepository = null;
    _attMtu = null;
    final connectionSubscription = _connectionSubscription;
    _connectionSubscription = null;
    await connectionSubscription?.cancel();
    if (!_ownsConnectionForCleanup(expectedConnectionAttempt)) {
      return;
    }
    await _transport.disconnect(deviceId);
    _logger.info(
      'transport_closed',
      fields: {'device': _redactDeviceId(deviceId)},
    );
  }

  Future<void> _cancelNotificationSubscriptions() async {
    if (_notificationSubscriptions.isEmpty) {
      _subscribedEndpointKeys.clear();
      _subscriptionReadiness.clear();
      return;
    }
    final subscriptions = List<StreamSubscription<Uint8List>>.of(
      _notificationSubscriptions,
    );
    _notificationSubscriptions.clear();
    _subscribedEndpointKeys.clear();
    _subscriptionReadiness.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }

  bool _isCurrentConnectionAttempt(int connectionAttempt) =>
      !_isDisposed && connectionAttempt == _connectionAttempt;

  bool _ownsConnectionForCleanup(int? expectedConnectionAttempt) =>
      expectedConnectionAttempt == null ||
      expectedConnectionAttempt == _connectionAttempt;

  Set<DevicePermission> _authorizedPermissions(
    Set<DevicePermission> permissions,
  ) {
    return {
      for (final permission in permissions)
        if (_hasDevicePermission(permission)) permission,
    };
  }

  bool _hasDevicePermission(DevicePermission permission) {
    final gate = _permissionGate;
    return gate == null || gate.allows(permission);
  }

  void _requireDevicePermission(DevicePermission permission) {
    if (!_hasDevicePermission(permission)) {
      throw StateError('当前认证未授予设备${permission.name}权限，请重新认证设备。');
    }
  }

  /// Rechecks the V1 authorization window when a queued EVT command reaches
  /// the head of the BLE write queue. Initial UI checks alone are not enough:
  /// a command can wait behind a long-running request until the 60-second
  /// window has expired.
  void _admitEvtCommandWrite(EvtCommandRequest request) {
    switch (request.command) {
      case 0x01:
        _requireDevicePermission(DevicePermission.status);
        return;
      case 0x02:
      case 0x06:
      case 0x07:
        _requireDevicePermission(DevicePermission.configuration);
        return;
      case 0x22:
      case 0x23:
        _requireDevicePermission(DevicePermission.files);
        return;
      case 0x09:
        // V1 code authentication must remain callable before authentication
        // has granted any scoped permissions. The V2 envelope is DVT-only,
        // so keep its marker and variable-length payload out of EVT even if
        // a future caller bypasses the repository boundary.
        if (request.content.length != 7 || request.content.first > 2) {
          throw StateError('EVT 阶段只允许 V1 认证码格式的 0x09 命令。');
        }
        return;
      default:
        throw StateError(
          'EVT 阶段不允许发送未声明授权范围的设备命令 '
          '0x${request.command.toRadixString(16).padLeft(2, '0').toUpperCase()}。',
        );
    }
  }

  void _requireObservableEndpoint(
    BleLogicalEndpoint endpoint,
    BleOperation operation,
  ) {
    if (!_state.isObservable) {
      throw StateError('设备尚未完成可用状态确认。');
    }
    if (!_profile.canOperate(endpoint, operation)) {
      throw StateError('设备配置未声明所需的 GATT 操作。');
    }
    if (!_state.supportsEndpoint(endpoint, operation)) {
      throw StateError('当前连接的设备未提供所需的 GATT 操作。');
    }
  }

  void _requireAuthenticationReadyEndpoint(
    BleLogicalEndpoint endpoint,
    BleOperation operation,
  ) {
    if (!_state.isAuthenticationReady) {
      throw StateError('设备尚未完成认证通道准备。');
    }
    if (!_profile.canOperate(endpoint, operation)) {
      throw StateError('设备配置未声明所需的 GATT 操作。');
    }
    if (!_state.supportsEndpoint(endpoint, operation)) {
      throw StateError('当前连接的设备未提供所需的 GATT 操作。');
    }
  }

  void _requireCommandEndpoint(
    BleLogicalEndpoint endpoint,
    BleOperation responseOperation,
  ) {
    _requireObservableEndpoint(endpoint, BleOperation.write);
    _requireObservableEndpoint(endpoint, responseOperation);
  }

  Future<int> _ensureV3AdmissionAttMtu() async {
    try {
      return await _ensureAttMtu(_v3AdmissionMinimumAttMtu);
    } on BleTransportException {
      rethrow;
    } on StateError catch (error) {
      throw BleTransportException(
        EvtFailure.transport(
          message: '设备蓝牙 MTU 不足，无法读取设备信息。',
          detail:
              'V3 设备信息最大 Indicate 需要 ATT MTU >= '
              '$_v3AdmissionMinimumAttMtu。$error',
        ),
      );
    }
  }

  Future<int> _ensureAttMtu(int requiredMtu) async {
    if (requiredMtu < 23) {
      requiredMtu = 23;
    }
    final cached = _attMtu;
    if (cached != null && cached >= requiredMtu) {
      return cached;
    }
    final deviceId = _state.session?.candidate.connectionId;
    if (deviceId == null || !_state.hasActiveBleConnection) {
      throw StateError('设备尚未完成连接，无法协商 ATT MTU。');
    }
    final mtu = await _transport.requestMtu(deviceId, preferredMtu: 517);
    if (mtu < 23) {
      throw StateError('设备协商的 ATT MTU 小于 23。');
    }
    _attMtu = mtu;
    _logger.info(
      'att_mtu_ready',
      fields: {'mtu': mtu, 'required_mtu': requiredMtu},
    );
    if (mtu < requiredMtu) {
      throw StateError('当前 ATT MTU 为 $mtu，无法发送需要 $requiredMtu 的设备协议帧。');
    }
    return mtu;
  }

  static int _requiredFileTransferMtu({
    required int startOffset,
    required int chunkSize,
  }) => startOffset == 0 && chunkSize == 0 ? 26 : 32;

  DeviceProtocolRepository _requireProtocol() {
    final repository = _protocolRepository;
    if (repository == null || !_state.hasActiveBleConnection) {
      throw StateError('设备尚未完成连接。');
    }
    return repository;
  }

  EvtFailure _failureFor(Object error, {required String fallback}) {
    return error is BleTransportException
        ? error.failure
        : EvtFailure.transport(message: fallback, detail: '$error');
  }

  /// Stops the current transport and waits until its native disconnect call
  /// has completed. AppShell uses this before replacing a session so an old
  /// controller cannot disconnect a newer connection to the same device.
  Future<void> close() {
    final pending = _closeFuture;
    if (pending != null) {
      return pending;
    }
    _isDisposed = true;
    final deviceId = _state.session?.candidate.connectionId;
    final closing = _closeResources(deviceId);
    _closeFuture = closing;
    return closing;
  }

  Future<void> _closeResources(String? deviceId) async {
    if (deviceId != null) {
      await _closeTransport(deviceId);
      return;
    }
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    await _cancelNotificationSubscriptions();
    await _commandClient?.close();
    _commandClient = null;
    await _responseController?.close();
    _responseController = null;
    _protocolRepository = null;
    _attMtu = null;
  }

  @override
  void dispose() {
    if (_changeNotifierDisposed) {
      return;
    }
    _changeNotifierDisposed = true;
    unawaited(close());
    super.dispose();
  }

  static String _redactDeviceId(String deviceId) {
    if (deviceId.length <= 4) {
      return deviceId;
    }
    return '...${deviceId.substring(deviceId.length - 4)}';
  }
}
