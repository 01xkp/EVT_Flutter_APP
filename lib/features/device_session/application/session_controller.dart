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
import 'package:aipin/core/protocol/evt_protocol_codec.dart';
import 'package:aipin/core/protocol/wqota_client.dart';
import 'package:aipin/core/protocol/wqota_codec.dart';
import 'package:aipin/features/device_session/data/device_protocol_repository.dart';
import 'package:aipin/features/device_session/application/device_auth_controller.dart';
import 'package:aipin/features/device_session/domain/device_configuration.dart';
import 'package:aipin/features/device_session/domain/device_file.dart';
import 'package:aipin/features/device_session/domain/device_file_gateway.dart';
import 'package:aipin/features/device_session/domain/device_info.dart';
import 'package:aipin/features/device_discovery/domain/device_candidate.dart';
import 'package:aipin/features/device_session/application/session_state.dart';
import 'package:aipin/features/device_session/domain/device_session.dart';
import 'package:aipin/features/device_session/domain/device_snapshot.dart';
import 'package:aipin/features/device_session/domain/device_security_gateway.dart';
import 'package:aipin/features/device_session/domain/realtime_audio_gateway.dart';
import 'package:aipin/features/device_session/domain/session_phase.dart';
import 'package:flutter/foundation.dart';

class SessionController extends ChangeNotifier
    implements RealtimeAudioGateway, DeviceFileGateway, DeviceSecurityGateway {
  SessionController(
    this._transport,
    this._profile,
    this._codec, {
    SafeAppLogger? logger,
    this._subscriptionSettleDelay = const Duration(milliseconds: 250),
  }) : _logger = logger ?? const DebugSafeAppLogger(scope: 'SESSION');

  static const _connectionSetupTimeout = Duration(seconds: 15);
  static const _operationTimeout = Duration(seconds: 15);
  // The largest legal 0x81 indication is 133 bytes, plus the ATT header.
  static const _v3AdmissionMinimumAttMtu = 136;

  final BleTransport _transport;
  final DeviceProfile _profile;
  final EvtProtocolCodec _codec;
  final SafeAppLogger _logger;
  final Duration _subscriptionSettleDelay;
  StreamSubscription<BleConnectionState>? _connectionSubscription;
  final List<StreamSubscription<Uint8List>> _notificationSubscriptions = [];
  final List<WqotaClient> _wqotaClients = <WqotaClient>[];
  StreamSubscription<Uint8List>? _realtimeAudioSubscription;
  StreamController<Uint8List>? _realtimeAudioController;
  StreamController<Uint8List>? _responseController;
  EvtCommandClient? _commandClient;
  DeviceProtocolRepository? _protocolRepository;
  Future<void>? _deviceDetailsRefresh;
  DeviceConfiguration? _configurationTemplate;
  int? _attMtu;
  SessionState _state = const SessionState(
    phase: SessionPhase.environmentReady,
  );

  SessionState get state => _state;

  DeviceProtocolRepository? get protocolRepository => _protocolRepository;

  Future<DeviceInfo> readDeviceInfo() => _requireProtocol().readDeviceInfo();

  Future<void> writeConfiguration(DeviceConfiguration configuration) =>
      _writeConfiguration(configuration);

  Future<void> _writeConfiguration(
    DeviceConfiguration configuration, {
    bool refreshDetails = true,
  }) async {
    _requireCommandEndpoint(BleLogicalEndpoint.fa10Fa12, BleOperation.indicate);
    await _requireProtocol().writeConfiguration(configuration);
    _cacheConfigurationTemplate(configuration);
    if (refreshDetails) {
      await refreshDeviceDetails(const {DevicePermission.configuration});
    }
  }

  Future<void> _writeAuthenticationConfiguration(
    DeviceConfiguration configuration,
  ) async {
    _requireAuthenticationReadyEndpoint(
      BleLogicalEndpoint.fa10Fa12,
      BleOperation.write,
    );
    _requireAuthenticationReadyEndpoint(
      BleLogicalEndpoint.fa10Fa12,
      BleOperation.indicate,
    );
    await _requireProtocol().writeConfiguration(configuration);
    _cacheConfigurationTemplate(configuration);
  }

  void _cacheConfigurationTemplate(DeviceConfiguration configuration) {
    _configurationTemplate = configuration;
    _logger.info(
      'configuration_template_updated',
      fields: {
        'duration_seconds': configuration.recordDurationSeconds,
        'record_mode': configuration.recordMode,
        'record_type': configuration.recordType,
        'audio_stream': configuration.audioStreamEnabled,
      },
    );
  }

  Future<DeviceStatus> readStatus() async {
    _requireCommandEndpoint(BleLogicalEndpoint.fa10Fa16, BleOperation.indicate);
    final status = await _requireProtocol().readStatus();
    _updateDeviceDetails(deviceStatus: status);
    return status;
  }

  Future<void> setRecordConsent(bool granted) async {
    _requireCommandEndpoint(BleLogicalEndpoint.fa10Fa16, BleOperation.indicate);
    await _requireProtocol().setRecordConsent(granted);
    await refreshDeviceDetails(const {DevicePermission.configuration});
  }

  Future<void> setPrivacyDuration(int durationCode) async {
    _requireCommandEndpoint(BleLogicalEndpoint.fa10Fa16, BleOperation.indicate);
    await _requireProtocol().setPrivacyDuration(durationCode);
    await refreshDeviceDetails(const {DevicePermission.configuration});
  }

  Future<int> readPrivacyDuration() async {
    _requireCommandEndpoint(BleLogicalEndpoint.fa10Fa16, BleOperation.indicate);
    final durationCode = await _requireProtocol().readPrivacyDuration();
    _updateDeviceDetails(privacyDurationCode: durationCode);
    return durationCode;
  }

  Future<void> refreshDeviceDetails(Set<DevicePermission> permissions) {
    final pending = _deviceDetailsRefresh;
    if (pending != null) {
      return pending;
    }
    final work = _refreshDeviceDetails(permissions);
    _deviceDetailsRefresh = work;
    return work.whenComplete(() {
      if (identical(_deviceDetailsRefresh, work)) {
        _deviceDetailsRefresh = null;
      }
    });
  }

  Future<EvtFrame> setRecordAction(int action) {
    _requireCommandEndpoint(BleLogicalEndpoint.fa10Fa17, BleOperation.indicate);
    return _setRecordAction(action);
  }

  WqotaClient openWqotaClient(WqotaCodec codec) {
    _requireObservableEndpoint(
      BleLogicalEndpoint.wqota2001,
      BleOperation.writeWithoutResponse,
    );
    _requireObservableEndpoint(
      BleLogicalEndpoint.wqota2002,
      BleOperation.notify,
    );
    final deviceId = _state.session!.candidate.connectionId;
    final client = WqotaClient(
      transport: _transport,
      writeCharacteristic: _characteristic(
        deviceId,
        _profile.endpoint(BleLogicalEndpoint.wqota2001),
      ),
      notifications: _transport.subscribe(
        _characteristic(
          deviceId,
          _profile.endpoint(BleLogicalEndpoint.wqota2002),
        ),
      ),
      codec: codec,
    );
    _wqotaClients.add(client);
    _logger.info('wqota_subscribed');
    return client;
  }

  Future<int> requestWqotaMtu() async {
    _requireObservableEndpoint(
      BleLogicalEndpoint.wqota2001,
      BleOperation.writeWithoutResponse,
    );
    final mtu = await _ensureAttMtu(30);
    _logger.info('wqota_mtu_ready', fields: {'mtu': mtu});
    return mtu;
  }

  Future<void> closeWqotaClient(WqotaClient client) async {
    if (_wqotaClients.remove(client)) {
      await client.close();
    }
  }

  @override
  Stream<Uint8List> subscribeRealtimeAudio() {
    _requireObservableEndpoint(
      BleLogicalEndpoint.fa10Fa18,
      BleOperation.notify,
    );
    final existing = _realtimeAudioController;
    if (existing != null && !existing.isClosed) {
      return existing.stream;
    }
    final deviceId = _state.session!.candidate.connectionId;
    final endpoint = _profile.endpoint(BleLogicalEndpoint.fa10Fa18);
    late final StreamController<Uint8List> controller;
    controller = StreamController<Uint8List>.broadcast(
      onListen: () {
        final subscription = _transport
            .subscribe(_characteristic(deviceId, endpoint))
            .listen(
              controller.add,
              onError: controller.addError,
              onDone: () {
                _realtimeAudioSubscription = null;
              },
            );
        _realtimeAudioSubscription = subscription;
        _logger.info(
          'realtime_audio_subscribed',
          fields: {'characteristic': endpoint.characteristicUuid},
        );
      },
      onCancel: _cancelRealtimeAudioSubscription,
    );
    _realtimeAudioController = controller;
    return controller.stream;
  }

  @override
  Future<void> setAudioStreamEnabled(bool enabled) async {
    _requireCommandEndpoint(BleLogicalEndpoint.fa10Fa12, BleOperation.indicate);
    final template = _configurationTemplate;
    if (template == null) {
      throw StateError('请先完成设备认证和配置同步，再开启实时音频。');
    }
    final chargingMode = _state.deviceBattery?.chargingMode;
    await writeConfiguration(
      template.copyWith(
        systemTime: DateTime.now(),
        chargingMode: chargingMode ?? template.chargingMode,
        audioStreamEnabled: enabled,
      ),
    );
  }

  Future<void> synchronizeAfterAuthentication(
    Set<DevicePermission> permissions,
  ) async {
    if (_state.isObservable) {
      await refreshDeviceDetails(permissions);
      return;
    }
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
      mtu = await _ensureV3AdmissionAttMtu();
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
      _fail(_failureFor(error, fallback: '认证后的设备信息或配置同步失败。'), interrupt: true);
      if (deviceId != null) {
        await _closeTransport(deviceId);
      }
      rethrow;
    }
    if (_state.phase == SessionPhase.authenticationReady) {
      _transition(
        SessionPhase.observable,
        session: _state.session!.copyWith(observableAt: DateTime.now()),
        latestSnapshot: _snapshotFromDeviceInfo(info),
      );
    }
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
      // A previous app process can die before it disables the volatile stream.
      // Each authenticated session starts with the V1.5 stream gate closed.
      audioStreamEnabled: false,
    );
  }

  @override
  Future<void> setRealtimeRecording(bool active) async {
    _requireCommandEndpoint(BleLogicalEndpoint.fa10Fa17, BleOperation.indicate);
    await setRecordAction(active ? 1 : 0);
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
    _requireCommandEndpoint(BleLogicalEndpoint.ff10Ff12, BleOperation.indicate);
    final mtu = await _ensureAttMtu(31);
    final supportedPageSize = max(1, min(20, (mtu - 10) ~/ 21));
    return _requireProtocol().listFiles(
      offset: offset,
      pageSize: min(pageSize, supportedPageSize),
    );
  }

  @override
  Future<DeviceFileMetadata> readFileMetadata(List<int> nameSlot) async {
    _requireCommandEndpoint(BleLogicalEndpoint.ff10Ff16, BleOperation.indicate);
    await _ensureAttMtu(57);
    return _requireProtocol().readFileMetadata(nameSlot);
  }

  @override
  Stream<Uint8List> downloadFile({
    required List<int> nameSlot,
    int startOffset = 0,
    int chunkSize = 0,
  }) async* {
    _requireCommandEndpoint(BleLogicalEndpoint.ff10Ff13, BleOperation.notify);
    await _ensureAttMtu(
      _requiredFileTransferMtu(startOffset: startOffset, chunkSize: chunkSize),
    );
    yield* _requireProtocol().downloadFile(
      nameSlot: nameSlot,
      startOffset: startOffset,
      chunkSize: chunkSize,
    );
  }

  @override
  Future<Uint8List> readFileChunk({
    required List<int> nameSlot,
    int startOffset = 0,
    int chunkSize = 0,
  }) async {
    _requireCommandEndpoint(BleLogicalEndpoint.ff10Ff13, BleOperation.notify);
    await _ensureAttMtu(
      _requiredFileTransferMtu(startOffset: startOffset, chunkSize: chunkSize),
    );
    return _requireProtocol().readFileChunk(
      nameSlot: nameSlot,
      startOffset: startOffset,
      chunkSize: chunkSize,
    );
  }

  @override
  Future<int> confirmArchive({
    required List<int> nameSlot,
    required int fileSize,
    required int crc32,
  }) async {
    _requireCommandEndpoint(BleLogicalEndpoint.ff10Ff16, BleOperation.indicate);
    await _ensureAttMtu(37);
    return _requireProtocol().confirmArchive(
      nameSlot: nameSlot,
      fileSize: fileSize,
      crc32: crc32,
    );
  }

  @override
  Future<DeviceSecurityResponse> execute(DeviceSecurityRequest request) async {
    _requireAuthenticationReadyEndpoint(
      BleLogicalEndpoint.fa10Fa19,
      BleOperation.write,
    );
    _requireAuthenticationReadyEndpoint(
      BleLogicalEndpoint.fa10Fa19,
      BleOperation.indicate,
    );
    await _ensureAttMtu(17 + request.data.length);
    return _requireProtocol().execute(request);
  }

  Future<void> connect(DeviceCandidate candidate) async {
    final previousDeviceId = _state.session?.candidate.connectionId;
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    await _closeWqotaClients();
    await _closeRealtimeAudioStream();
    await _cancelNotificationSubscriptions();
    await _commandClient?.close();
    _commandClient = null;
    await _responseController?.close();
    _responseController = null;
    _protocolRepository = null;
    _configurationTemplate = null;
    _attMtu = null;
    if (previousDeviceId != null) {
      await _transport.disconnect(previousDeviceId);
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
              unawaited(_closeTransport(candidate.connectionId));
            }
          },
          onError: (Object error, StackTrace stackTrace) {
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
              unawaited(_closeTransport(candidate.connectionId));
            }
          },
          onDone: () {
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
              unawaited(_closeTransport(candidate.connectionId));
            }
          },
        );

    try {
      await connected.future.timeout(_connectionSetupTimeout);
      if (_state.phase != SessionPhase.connecting) {
        return;
      }
      _transition(
        SessionPhase.servicesDiscovered,
        session: _state.session!.copyWith(connectedAt: DateTime.now()),
      );
      final services = await _transport
          .discoverServices(candidate.connectionId)
          .timeout(_operationTimeout);
      if (!_hasRequiredEndpoints(services)) {
        _fail(EvtFailure.access(message: '设备缺少所需的状态读取或订阅特征。'), interrupt: true);
        await _closeTransport(candidate.connectionId);
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
      );
      _protocolRepository = DeviceProtocolRepository(
        deviceId: candidate.connectionId,
        profile: _profile,
        transport: _transport,
        commands: _commandClient!,
        codec: _codec,
      );
      await _subscribeConfiguredEndpoints(candidate.connectionId, services);
      if (_subscriptionSettleDelay > Duration.zero) {
        _logger.info(
          'notification_subscription_settling',
          fields: {'milliseconds': _subscriptionSettleDelay.inMilliseconds},
        );
        await Future<void>.delayed(_subscriptionSettleDelay);
      }
      _transition(SessionPhase.authenticationReady);
      _logger.info('session_authentication_ready');
    } catch (error) {
      _interrupt(error);
      await _closeTransport(candidate.connectionId);
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
    )) {
      return;
    }
    try {
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
    )) {
      return;
    }
    try {
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
          BleOperation.write,
        ) ||
        !_state.supportsEndpoint(
          BleLogicalEndpoint.fa10Fa12,
          BleOperation.indicate,
        )) {
      return;
    }
    try {
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
    final session = _state.session;
    if (session != null) {
      await _closeTransport(session.candidate.connectionId);
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
    final snapshot = _snapshotFromFrame(
      frame,
      source: '状态订阅 0x${frame.command.toRadixString(16).toUpperCase()}',
    );
    _state = _state.copyWith(
      events: List.unmodifiable([..._state.events, event]),
      latestSnapshot: snapshot ?? _state.latestSnapshot,
      deviceStatus: status ?? _state.deviceStatus,
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

  void _onTransportError(Object error, StackTrace stackTrace) {
    _interrupt(error);
    final deviceId = _state.session?.candidate.connectionId;
    if (deviceId != null) {
      unawaited(_closeTransport(deviceId));
    }
  }

  Future<void> _subscribeConfiguredEndpoints(
    String deviceId,
    List<BleService> services,
  ) async {
    final responseController = _responseController;
    if (responseController == null) {
      throw StateError('协议响应通道尚未初始化。');
    }
    final notifyEndpoint = _profile.notifyEndpoint;
    final endpoints = <String, BleEndpoint>{};
    void addEndpoint(BleEndpoint endpoint) {
      endpoints['${endpoint.serviceUuid}|${endpoint.characteristicUuid}'] =
          endpoint;
    }

    addEndpoint(
      BleEndpoint(
        serviceUuid: notifyEndpoint.serviceUuid,
        characteristicUuid: notifyEndpoint.characteristicUuid,
        operations: const {BleOperation.indicate},
      ),
    );
    for (final entry in _profile.endpoints.entries) {
      if (entry.key == BleLogicalEndpoint.fa10Fa18 ||
          entry.key == BleLogicalEndpoint.wqota2001 ||
          entry.key == BleLogicalEndpoint.wqota2002) {
        continue;
      }
      addEndpoint(entry.value);
    }
    for (final endpoint in endpoints.values) {
      final subscribable =
          endpoint.operations.contains(BleOperation.notify) ||
          endpoint.operations.contains(BleOperation.indicate);
      if (!subscribable || !_hasSubscriptionEndpoint(services, endpoint)) {
        continue;
      }
      final characteristic = BleCharacteristic(
        deviceId: deviceId,
        serviceUuid: endpoint.serviceUuid,
        characteristicUuid: endpoint.characteristicUuid,
      );
      final subscription = _transport.subscribe(characteristic).listen((bytes) {
        responseController.add(bytes);
        _onNotification(bytes);
      }, onError: _onTransportError);
      _notificationSubscriptions.add(subscription);
      _logger.info(
        'notification_subscribed',
        fields: {'characteristic': endpoint.characteristicUuid},
      );
    }
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

  bool _hasRequiredEndpoints(List<BleService> services) {
    return _hasEndpoint(services, _profile.readEndpoint, BleOperation.read) &&
        _hasEndpoint(
          services,
          _profile.notifyEndpoint,
          BleOperation.indicate,
        ) &&
        _hasEndpoint(
          services,
          _profile.endpoint(BleLogicalEndpoint.fa10Fa11),
          BleOperation.write,
        ) &&
        _hasEndpoint(
          services,
          _profile.endpoint(BleLogicalEndpoint.fa10Fa11),
          BleOperation.indicate,
        ) &&
        _hasEndpoint(
          services,
          _profile.endpoint(BleLogicalEndpoint.fa10Fa19),
          BleOperation.write,
        ) &&
        _hasEndpoint(
          services,
          _profile.endpoint(BleLogicalEndpoint.fa10Fa19),
          BleOperation.indicate,
        ) &&
        _hasEndpoint(
          services,
          _profile.endpoint(BleLogicalEndpoint.fa10Fa12),
          BleOperation.write,
        ) &&
        _hasEndpoint(
          services,
          _profile.endpoint(BleLogicalEndpoint.fa10Fa12),
          BleOperation.indicate,
        );
  }

  bool _hasEndpoint(
    List<BleService> services,
    BleEndpoint endpoint,
    BleOperation operation,
  ) {
    final characteristic = _discoveredCharacteristic(services, endpoint);
    return characteristic?.operations.contains(operation) ?? false;
  }

  bool _hasSubscriptionEndpoint(
    List<BleService> services,
    BleEndpoint endpoint,
  ) {
    final operations = _discoveredCharacteristic(
      services,
      endpoint,
    )?.operations;
    return operations?.contains(BleOperation.notify) == true ||
        operations?.contains(BleOperation.indicate) == true;
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

  Future<void> _closeTransport(String deviceId) async {
    await _closeWqotaClients();
    await _closeRealtimeAudioStream();
    await _cancelNotificationSubscriptions();
    await _commandClient?.close();
    _commandClient = null;
    await _responseController?.close();
    _responseController = null;
    _protocolRepository = null;
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    await _transport.disconnect(deviceId);
    _logger.info(
      'transport_closed',
      fields: {'device': _redactDeviceId(deviceId)},
    );
  }

  Future<void> _cancelNotificationSubscriptions() async {
    if (_notificationSubscriptions.isEmpty) {
      return;
    }
    final subscriptions = List<StreamSubscription<Uint8List>>.of(
      _notificationSubscriptions,
    );
    _notificationSubscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }

  Future<void> _cancelRealtimeAudioSubscription() async {
    final subscription = _realtimeAudioSubscription;
    _realtimeAudioSubscription = null;
    await subscription?.cancel();
  }

  Future<void> _closeRealtimeAudioStream() async {
    await _cancelRealtimeAudioSubscription();
    final controller = _realtimeAudioController;
    _realtimeAudioController = null;
    await controller?.close();
  }

  Future<void> _closeWqotaClients() async {
    final clients = List<WqotaClient>.of(_wqotaClients);
    _wqotaClients.clear();
    for (final client in clients) {
      await client.close();
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

  @override
  void dispose() {
    final deviceId = _state.session?.candidate.connectionId;
    if (deviceId != null) {
      unawaited(_closeTransport(deviceId));
    }
    unawaited(_connectionSubscription?.cancel());
    unawaited(_cancelNotificationSubscriptions());
    unawaited(_closeRealtimeAudioStream());
    unawaited(_closeWqotaClients());
    super.dispose();
  }

  static String _redactDeviceId(String deviceId) {
    if (deviceId.length <= 4) {
      return deviceId;
    }
    return '...${deviceId.substring(deviceId.length - 4)}';
  }
}
