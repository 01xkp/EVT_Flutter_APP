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
import 'package:aipin/core/protocol/evt_frame_assembler.dart';
import 'package:aipin/core/protocol/evt_protocol_contract.dart';
import 'package:aipin/core/protocol/evt_protocol_codec.dart';
import 'package:aipin/features/device_session/data/device_protocol_repository.dart';
import 'package:aipin/features/device_session/domain/device_configuration.dart';
import 'package:aipin/features/device_session/domain/device_permission.dart';
import 'package:aipin/features/device_session/domain/evt_legacy_security_gateway.dart';
import 'package:aipin/features/device_session/domain/evt_unbind_preflight.dart';
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
    SafeAppLogger? commandLogger,
    this._legacySecurityResponseTimeout = const Duration(seconds: 2),
    this._legacyBindResponseTimeout = const Duration(seconds: 65),
    this._legacyUnbindResponseTimeout = const Duration(seconds: 120),
    this._fileListResponseTimeout = const Duration(seconds: 2),
    this._fileTransferIdleTimeout = const Duration(seconds: 15),
    this._permissionGate,
  }) : _logger = logger ?? const DebugSafeAppLogger(scope: 'SESSION'),
       _commandLogger = commandLogger ?? const DebugSafeAppLogger(scope: 'CMD');

  static const _connectionSetupTimeout = Duration(seconds: 15);
  static const _operationTimeout = Duration(seconds: 15);
  static const _notificationSetupTimeout = Duration(seconds: 8);
  // V1.6 pre-authentication 0x81 is a fixed 90-byte Content payload. The
  // complete business frame is 96 bytes and an ATT indication reserves three
  // bytes for its ATT/L2CAP header, so the connection must negotiate MTU 99
  // before the identity read is dispatched.
  static const _v16PreAuthenticationMinimumAttMtu = 99;
  // Authenticated 0x81 may include the 30-byte compatibility area and the
  // seven-byte active-record fields. Its largest legal frame is 133 bytes;
  // keep the larger admission gate for the protected read.
  static const _v16AuthenticatedInfoMinimumAttMtu = 136;
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
    // V1.6 reserves CMD=0x23 for the request; file-data Notify uses
    // response CMD=0xA3 (0x23 | 0x80).
    BleLogicalEndpoint.ff10Ff13: 0xA3,
  };

  final BleTransport _transport;
  final DeviceProfile _profile;
  final EvtProtocolCodec _codec;
  final SafeAppLogger _logger;
  final SafeAppLogger _commandLogger;
  final Duration _legacySecurityResponseTimeout;
  final Duration _legacyBindResponseTimeout;
  final Duration _legacyUnbindResponseTimeout;
  final Duration _fileListResponseTimeout;
  final Duration _fileTransferIdleTimeout;
  final DevicePermissionGate? _permissionGate;
  StreamSubscription<BleConnectionState>? _connectionSubscription;
  final List<StreamSubscription<Uint8List>> _notificationSubscriptions = [];
  final Set<String> _subscribedEndpointKeys = <String>{};
  final Map<String, Future<void>> _subscriptionReadiness =
      <String, Future<void>>{};
  final Map<String, EvtFrameAssembler> _notificationFrameAssemblers = {};
  StreamController<Uint8List>? _responseController;
  EvtCommandClient? _commandClient;
  DeviceProtocolRepository? _protocolRepository;
  Future<void>? _deviceDetailsRefresh;
  Future<void>? _closeFuture;
  Future<void>? _transportCloseFuture;
  int? _attMtu;
  // Only the connection-time, fixed 90-byte 0x01 read may bypass the normal
  // permission gate. The flag is scoped to the pending command and cleared in
  // a finally block so no later business request can use the exception.
  var _preAuthenticationInfoReadInProgress = false;
  int _connectionAttempt = 0;
  var _isDisposed = false;
  var _changeNotifierDisposed = false;
  SessionState _state = const SessionState(
    phase: SessionPhase.environmentReady,
  );

  SessionState get state => _state;

  Future<DeviceInfo> readDeviceInfo() async {
    final startedAt = DateTime.now();
    _logger.info(
      'device_info_read_requested',
      operation: 'device_connect',
      stage: 'request',
      result: 'pending',
      fields: _sessionFields('【会话读取】准备读取设备信息并校验状态权限', {
        'endpoint': BleLogicalEndpoint.fa10Fa11.name,
        'command': '0x01',
        'expected_command': '0x81',
      }),
    );
    try {
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
      // Recheck connection-scoped authorization immediately before scheduling
      // the protected device-info request; this closes a disconnect/revoke
      // race while CCC registration is pending.
      _requireDevicePermission(DevicePermission.status);
      // An authenticated 0x81 response may include the optional 30-byte
      // compatibility area and active-record fields (up to a 133-byte frame).
      // The pre-auth identity read only requires ATT MTU 99, so refresh the
      // negotiated capacity before every public protected read as well. The
      // cached value makes this a no-op after the normal post-auth sync.
      await _ensureAuthenticatedDeviceInfoAttMtu();
      _requireCurrentConnectionAttempt(_connectionAttempt);
      _requireDevicePermission(DevicePermission.status);
      final info = await _requireProtocol().readDeviceInfo();
      _logger.info(
        'device_info_read_completed',
        operation: 'device_connect',
        stage: 'response',
        result: 'success',
        elapsed: DateTime.now().difference(startedAt),
        fields: _sessionFields('【会话读取】设备信息响应已校验并写入会话快照', {
          'endpoint': BleLogicalEndpoint.fa10Fa11.name,
          'command': '0x81',
          'protocol_version': info.capabilities.protocolVersion,
        }),
      );
      return info;
    } catch (error) {
      _logger.warning(
        'device_info_read_failed',
        operation: 'device_connect',
        stage: 'response',
        result: 'failed',
        elapsed: DateTime.now().difference(startedAt),
        fields: _sessionFields('【会话读取】设备信息读取未完成，保留可定位的错误类型', {
          'endpoint': BleLogicalEndpoint.fa10Fa11.name,
          'command': '0x01',
          'error_type': error.runtimeType.toString(),
        }),
      );
      rethrow;
    }
  }

  Future<void> writeConfiguration(DeviceConfiguration configuration) =>
      _writeConfiguration(configuration);

  Future<void> _writeConfiguration(
    DeviceConfiguration configuration, {
    bool refreshDetails = true,
  }) async {
    final startedAt = DateTime.now();
    _logger.info(
      'configuration_write_requested',
      operation: 'device_connect',
      stage: 'write',
      result: 'pending',
      fields: _sessionFields('【会话配置】准备写入设备配置，不记录配置原始字节', {
        'endpoint': BleLogicalEndpoint.fa10Fa12.name,
        'command': '0x02',
        'expected_command': '0x82',
        'configured': true,
      }),
    );
    try {
      _requireDevicePermission(DevicePermission.configuration);
      _requireCommandEndpoint(
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
      if (refreshDetails) {
        await refreshDeviceDetails(const {DevicePermission.configuration});
      }
      _logger.info(
        'configuration_write_completed',
        operation: 'device_connect',
        stage: 'response',
        result: 'success',
        elapsed: DateTime.now().difference(startedAt),
        fields: _sessionFields('【会话配置】设备已确认配置写入，随后按需刷新配置状态', {
          'endpoint': BleLogicalEndpoint.fa10Fa12.name,
          'command': '0x82',
          'configured': true,
        }),
      );
    } catch (error) {
      _logger.warning(
        'configuration_write_failed',
        operation: 'device_connect',
        stage: 'response',
        result: 'failed',
        elapsed: DateTime.now().difference(startedAt),
        fields: _sessionFields('【会话配置】配置写入未完成，未输出配置内容', {
          'endpoint': BleLogicalEndpoint.fa10Fa12.name,
          'command': '0x02',
          'error_type': error.runtimeType.toString(),
        }),
      );
      rethrow;
    }
  }

  Future<void> _writeAuthenticationConfiguration(
    DeviceConfiguration configuration,
  ) async {
    final startedAt = DateTime.now();
    _logger.info(
      'authentication_configuration_write_requested',
      operation: 'device_authenticate',
      stage: 'sync',
      result: 'pending',
      fields: _sessionFields('【会话认证】认证成功后准备写入基线配置', {
        'endpoint': BleLogicalEndpoint.fa10Fa12.name,
        'command': '0x02',
        'expected_command': '0x82',
        'configured': true,
      }),
    );
    try {
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
      _logger.info(
        'authentication_configuration_write_completed',
        operation: 'device_authenticate',
        stage: 'sync',
        result: 'success',
        elapsed: DateTime.now().difference(startedAt),
        fields: _sessionFields('【会话认证】基线配置已被设备确认', {
          'endpoint': BleLogicalEndpoint.fa10Fa12.name,
          'command': '0x82',
          'configured': true,
        }),
      );
    } catch (error) {
      _logger.warning(
        'authentication_configuration_write_failed',
        operation: 'device_authenticate',
        stage: 'sync',
        result: 'failed',
        elapsed: DateTime.now().difference(startedAt),
        fields: _sessionFields('【会话认证】基线配置同步失败，认证会话不能继续使用', {
          'endpoint': BleLogicalEndpoint.fa10Fa12.name,
          'command': '0x02',
          'error_type': error.runtimeType.toString(),
        }),
      );
      rethrow;
    }
  }

  void _cacheConfigurationTemplate(DeviceConfiguration configuration) {
    _logger.info(
      'configuration_applied',
      operation: 'device_connect',
      stage: 'response',
      result: 'success',
      fields: _sessionFields('【会话配置】已缓存设备确认的配置摘要', {
        'duration_seconds': configuration.recordDurationSeconds,
        'record_mode': configuration.recordMode,
        'record_type': configuration.recordType,
      }),
    );
  }

  Future<DeviceStatus> readStatus() async {
    final startedAt = DateTime.now();
    _logger.info(
      'device_status_read_requested',
      operation: 'device_connect',
      stage: 'request',
      result: 'pending',
      fields: _sessionFields('【会话读取】准备读取设备状态并确认状态权限', {
        'endpoint': BleLogicalEndpoint.fa10Fa16.name,
        'command': '0x06',
        'expected_command': '0x86',
      }),
    );
    try {
      _requireDevicePermission(DevicePermission.status);
      _requireCommandEndpoint(
        BleLogicalEndpoint.fa10Fa16,
        BleOperation.indicate,
      );
      await _ensureResponseSubscription(
        BleLogicalEndpoint.fa10Fa16,
        critical: true,
      );
      _requireDevicePermission(DevicePermission.status);
      final status = await _requireProtocol().readStatus();
      _updateDeviceDetails(deviceStatus: status);
      _logger.info(
        'device_status_read_completed',
        operation: 'device_connect',
        stage: 'response',
        result: 'success',
        elapsed: DateTime.now().difference(startedAt),
        fields: _sessionFields('【会话读取】设备状态响应已校验并更新详情', {
          'endpoint': BleLogicalEndpoint.fa10Fa16.name,
          'command': '0x86',
          'status': 'loaded',
        }),
      );
      return status;
    } catch (error) {
      _logger.warning(
        'device_status_read_failed',
        operation: 'device_connect',
        stage: 'response',
        result: 'failed',
        elapsed: DateTime.now().difference(startedAt),
        fields: _sessionFields('【会话读取】设备状态读取未完成，保留错误类型供联调判断', {
          'endpoint': BleLogicalEndpoint.fa10Fa16.name,
          'command': '0x06',
          'error_type': error.runtimeType.toString(),
        }),
      );
      rethrow;
    }
  }

  Future<void> setRecordConsent(bool granted) async {
    final startedAt = DateTime.now();
    _logger.info(
      'record_consent_update_requested',
      operation: 'device_connect',
      stage: 'write',
      result: 'pending',
      fields: _sessionFields('【会话配置】准备更新设备录音授权状态', {
        'endpoint': BleLogicalEndpoint.fa10Fa16.name,
        'command': '0x06',
        'expected_command': '0x86',
        'granted': granted,
      }),
    );
    try {
      _requireDevicePermission(DevicePermission.configuration);
      _requireCommandEndpoint(
        BleLogicalEndpoint.fa10Fa16,
        BleOperation.indicate,
      );
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
      _logger.info(
        'record_consent_verified',
        operation: 'device_connect',
        stage: 'response',
        result: 'success',
        elapsed: DateTime.now().difference(startedAt),
        fields: _sessionFields('【会话配置】设备状态回读已确认录音授权更新', {
          'endpoint': BleLogicalEndpoint.fa10Fa16.name,
          'command': '0x86',
          'granted': granted,
        }),
      );
    } catch (error) {
      _logger.warning(
        'record_consent_update_failed',
        operation: 'device_connect',
        stage: 'response',
        result: 'failed',
        elapsed: DateTime.now().difference(startedAt),
        fields: _sessionFields('【会话配置】录音授权更新或回读校验失败', {
          'endpoint': BleLogicalEndpoint.fa10Fa16.name,
          'command': '0x06',
          'error_type': error.runtimeType.toString(),
        }),
      );
      rethrow;
    }
  }

  Future<void> setPrivacyDuration(int durationCode) async {
    final startedAt = DateTime.now();
    _logger.info(
      'privacy_duration_update_requested',
      operation: 'device_connect',
      stage: 'write',
      result: 'pending',
      fields: _sessionFields('【会话配置】准备更新设备隐私时长代码', {
        'endpoint': BleLogicalEndpoint.fa10Fa16.name,
        'command': '0x06',
        'expected_command': '0x86',
        'duration_code': durationCode,
      }),
    );
    try {
      _requireDevicePermission(DevicePermission.configuration);
      _requireCommandEndpoint(
        BleLogicalEndpoint.fa10Fa16,
        BleOperation.indicate,
      );
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
        operation: 'device_connect',
        stage: 'response',
        result: 'success',
        elapsed: DateTime.now().difference(startedAt),
        fields: _sessionFields('【会话配置】隐私时长已通过设备回读校验', {
          'endpoint': BleLogicalEndpoint.fa10Fa16.name,
          'command': '0x86',
          'duration_code': actual,
        }),
      );
    } catch (error) {
      _logger.warning(
        'privacy_duration_update_failed',
        operation: 'device_connect',
        stage: 'response',
        result: 'failed',
        elapsed: DateTime.now().difference(startedAt),
        fields: _sessionFields('【会话配置】隐私时长更新或回读校验失败', {
          'endpoint': BleLogicalEndpoint.fa10Fa16.name,
          'command': '0x06',
          'error_type': error.runtimeType.toString(),
        }),
      );
      rethrow;
    }
  }

  Future<int> readPrivacyDuration() async {
    final startedAt = DateTime.now();
    _logger.info(
      'privacy_duration_read_requested',
      operation: 'device_connect',
      stage: 'request',
      result: 'pending',
      fields: _sessionFields('【会话读取】准备读取设备隐私时长代码', {
        'endpoint': BleLogicalEndpoint.fa10Fa16.name,
        'command': '0x06',
        'expected_command': '0x86',
      }),
    );
    try {
      _requireDevicePermission(DevicePermission.configuration);
      _requireCommandEndpoint(
        BleLogicalEndpoint.fa10Fa16,
        BleOperation.indicate,
      );
      await _ensureResponseSubscription(
        BleLogicalEndpoint.fa10Fa16,
        critical: true,
      );
      _requireDevicePermission(DevicePermission.configuration);
      final durationCode = await _requireProtocol().readPrivacyDuration();
      _updateDeviceDetails(privacyDurationCode: durationCode);
      _logger.info(
        'privacy_duration_read_completed',
        operation: 'device_connect',
        stage: 'response',
        result: 'success',
        elapsed: DateTime.now().difference(startedAt),
        fields: _sessionFields('【会话读取】隐私时长响应已写入会话详情', {
          'endpoint': BleLogicalEndpoint.fa10Fa16.name,
          'command': '0x86',
          'duration_code': durationCode,
        }),
      );
      return durationCode;
    } catch (error) {
      _logger.warning(
        'privacy_duration_read_failed',
        operation: 'device_connect',
        stage: 'response',
        result: 'failed',
        elapsed: DateTime.now().difference(startedAt),
        fields: _sessionFields('【会话读取】隐私时长读取未完成，保留错误类型供联调判断', {
          'endpoint': BleLogicalEndpoint.fa10Fa16.name,
          'command': '0x06',
          'error_type': error.runtimeType.toString(),
        }),
      );
      rethrow;
    }
  }

  Future<void> refreshDeviceDetails(Set<DevicePermission> permissions) {
    final pending = _deviceDetailsRefresh;
    if (pending != null) {
      _logger.info(
        'device_details_refresh_reused',
        operation: 'device_connect',
        stage: 'sync',
        result: 'pending',
        fields: _sessionFields('【会话刷新】复用正在执行的设备详情刷新任务', {
          'granted_permissions': permissions
              .map((permission) => permission.name)
              .toList(growable: false),
        }),
      );
      return pending;
    }
    final authorizedPermissions = _authorizedPermissions(permissions);
    if (authorizedPermissions.isEmpty) {
      _logger.info(
        'device_details_refresh_skipped',
        operation: 'device_connect',
        stage: 'sync',
        result: 'cancelled',
        fields: _sessionFields('【会话刷新】当前认证未授予可刷新的设备详情权限', {
          'granted_permissions': const <String>[],
        }),
      );
      return Future<void>.value();
    }
    _logger.info(
      'device_details_refresh_requested',
      operation: 'device_connect',
      stage: 'sync',
      result: 'pending',
      fields: _sessionFields('【会话刷新】按当前认证权限开始刷新设备详情', {
        'granted_permissions': authorizedPermissions
            .map((permission) => permission.name)
            .toList(growable: false),
      }),
    );
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
    final connectionAttempt = _connectionAttempt;
    final startedAt = DateTime.now();
    final operation = switch (request.action) {
      EvtLegacySecurityAction.authenticate => 'device_authenticate',
      EvtLegacySecurityAction.bind => 'device_bind',
      EvtLegacySecurityAction.unbind => 'device_unbind',
    };
    final responseTimeout = switch (request.action) {
      EvtLegacySecurityAction.authenticate => _legacySecurityResponseTimeout,
      EvtLegacySecurityAction.bind => _legacyBindResponseTimeout,
      EvtLegacySecurityAction.unbind => _legacyUnbindResponseTimeout,
    };
    _logger.info(
      'legacy_security_exchange_started',
      operation: operation,
      stage: 'fa19_write',
      result: 'pending',
      fields: _sessionFields('【会话认证】准备通过 FA19 发起 V1.6 认证或绑定交换', {
        'connection_attempt': connectionAttempt,
        'action': request.action.name,
        'endpoint': BleLogicalEndpoint.fa10Fa19.name,
        'timeout_ms': responseTimeout.inMilliseconds,
        'length': request.securityCode.length,
      }),
    );
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
    _requireCurrentConnectionAttempt(connectionAttempt);
    _logger.info(
      'legacy_security_exchange_dispatching',
      operation: operation,
      stage: 'fa19_write',
      result: 'pending',
      elapsed: DateTime.now().difference(startedAt),
      fields: _sessionFields('【会话认证】认证通道就绪，准备下发不含认证码的命令摘要', {
        'action': request.action.name,
        'endpoint': BleLogicalEndpoint.fa10Fa19.name,
        'command': '0x09',
        'expected_command': '0x89',
      }),
    );
    try {
      final accepted = await _requireProtocol().executeEvtLegacySecurity(
        request,
      );
      _requireCurrentConnectionAttempt(connectionAttempt);
      _logger.info(
        'legacy_security_exchange_result_received',
        operation: operation,
        stage: 'response',
        result: accepted ? 'success' : 'failed',
        elapsed: DateTime.now().difference(startedAt),
        fields: _sessionFields('【会话认证】已收到设备认证结果，只记录结果不记录认证码', {
          'action': request.action.name,
          'endpoint': BleLogicalEndpoint.fa10Fa19.name,
          'command': '0x89',
        }),
      );
      return accepted;
    } catch (error, stackTrace) {
      final cacheRefresh = await _recoverGattAfterLegacySecurityTimeout(
        error,
        connectionAttempt: connectionAttempt,
        operation: operation,
        action: request.action,
      );
      _logger.warning(
        'legacy_security_exchange_failed',
        operation: operation,
        stage: 'response',
        result: 'failed',
        elapsed: DateTime.now().difference(startedAt),
        fields: _sessionFields('【会话认证】认证结果未确认，准备关闭当前会话避免迟到响应', {
          'action': request.action.name,
          'endpoint': BleLogicalEndpoint.fa10Fa19.name,
          'error_type': error.runtimeType.toString(),
          if (cacheRefresh != null)
            'gatt_cache_refresh_result': cacheRefresh.name,
        }),
      );
      // V1.6 only returns BindResult. Without an action or transaction id, a
      // late response cannot be distinguished from the next 0x09 operation.
      await _invalidateSessionForAmbiguousProtocolResult(
        connectionAttempt: connectionAttempt,
        event: 'legacy_security_result_uncertain',
        message: '设备认证结果未确认，已断开连接，请重新连接后重试。',
        fields: _sessionFields('【会话认证】V1.6 认证响应无法关联，主动断开避免误用迟到数据', {
          'action': request.action.name,
          'error_type': error.runtimeType.toString(),
          if (cacheRefresh != null)
            'gatt_cache_refresh_result': cacheRefresh.name,
          if (cacheRefresh != null) 'next_action': 'reconnect',
        }),
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// A V1.6 `0x09` response has no action or transaction identifier. Once its
  /// response window expires, the session must be discarded instead of
  /// retrying the command. On Android, clear the cache while the connection is
  /// still alive so the user's next reconnect re-discovers the current GATT
  /// layout. The cache action is best-effort and never replaces the timeout.
  Future<BleGattCacheClearResult?> _recoverGattAfterLegacySecurityTimeout(
    Object error, {
    required int connectionAttempt,
    required String operation,
    required EvtLegacySecurityAction action,
  }) async {
    if (error is! EvtCommandTimeoutException ||
        !_isCurrentConnectionAttempt(connectionAttempt)) {
      return null;
    }
    final deviceId = _state.session?.candidate.connectionId;
    if (deviceId == null || !_state.hasActiveBleConnection) {
      _logger.info(
        'legacy_security_gatt_recovery_skipped',
        operation: operation,
        stage: 'response',
        result: 'cancelled',
        fields: _sessionFields('【会话认证】认证或绑定响应超时时连接已不可用，跳过 GATT 缓存恢复', {
          'action': action.name,
          'gatt_cache_refresh_attempted': false,
          'next_action': 'reconnect',
        }),
      );
      return null;
    }
    _logger.info(
      'legacy_security_gatt_recovery_requested',
      operation: operation,
      stage: 'response',
      result: 'pending',
      fields: _sessionFields('【会话认证】认证或绑定响应超时，尝试在断开前恢复 GATT 缓存', {
        'action': action.name,
        'command': '0x09',
        'expected_command': '0x89',
        'gatt_cache_refresh_attempted': true,
      }),
    );
    try {
      final result = await _transport.clearGattCache(deviceId);
      _logger.info(
        'legacy_security_gatt_recovery_completed',
        operation: operation,
        stage: 'response',
        result: switch (result) {
          BleGattCacheClearResult.cleared => 'success',
          BleGattCacheClearResult.unsupported => 'cancelled',
          BleGattCacheClearResult.failed => 'failed',
        },
        fields: _sessionFields('【会话认证】认证或绑定超时后的 GATT 缓存恢复已结束，下一步重新连接', {
          'action': action.name,
          'gatt_cache_refresh_attempted': true,
          'gatt_cache_refresh_result': result.name,
          'next_action': 'reconnect',
        }),
      );
      return result;
    } catch (recoveryError) {
      _logger.warning(
        'legacy_security_gatt_recovery_failed',
        operation: operation,
        stage: 'response',
        result: 'failed',
        fields: _sessionFields('【会话认证】GATT 缓存恢复发生异常，不覆盖原认证或绑定超时结果', {
          'action': action.name,
          'gatt_cache_refresh_attempted': true,
          'gatt_cache_refresh_result': BleGattCacheClearResult.failed.name,
          'error_type': recoveryError.runtimeType.toString(),
          'next_action': 'reconnect',
        }),
      );
      return BleGattCacheClearResult.failed;
    }
  }

  Future<void> synchronizeAfterAuthentication(
    Set<DevicePermission> permissions,
  ) async {
    final startedAt = DateTime.now();
    final connectionAttempt = _connectionAttempt;
    if (_state.isObservable) {
      _logger.info(
        'authentication_synchronization_reused',
        operation: 'device_authenticate',
        stage: 'sync',
        result: 'pending',
        fields: _sessionFields('【会话认证】设备已可用，仅刷新认证权限范围内的详情', {
          'connection_attempt': connectionAttempt,
          'granted_permissions': permissions
              .map((permission) => permission.name)
              .toList(growable: false),
        }),
      );
      await refreshDeviceDetails(permissions);
      return;
    }
    _logger.info(
      'authentication_synchronization_requested',
      operation: 'device_authenticate',
      stage: 'sync',
      result: 'pending',
      fields: _sessionFields('【会话认证】认证成功后开始读取设备信息并写入基线配置', {
        'connection_attempt': connectionAttempt,
        'endpoint': BleLogicalEndpoint.fa10Fa11.name,
        'command': '0x01',
        'expected_command': '0x81',
        'granted_permissions': permissions
            .map((permission) => permission.name)
            .toList(growable: false),
      }),
    );
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
      // V1.6 gates every protected characteristic behind the current
      // connection's Action=00. FA11/FA19 were subscribed during admission;
      // all other EVT CCCs are enabled only after the AUTH response arrives.
      await _subscribeEvtEndpointsAfterAuthentication();
      _requireDevicePermission(DevicePermission.status);
      mtu = await _ensureAuthenticatedDeviceInfoAttMtu();
      // Recheck connection-scoped authorization immediately before the
      // protected 0x01 command is scheduled. V1.6's 60-second value is only
      // the firmware deadline before AUTH succeeds, not a post-AUTH TTL.
      _requireDevicePermission(DevicePermission.status);
      info = await repository.readDeviceInfo();
      _logger.info(
        'authentication_device_info_received',
        operation: 'device_authenticate',
        stage: 'sync',
        result: 'success',
        elapsed: DateTime.now().difference(startedAt),
        fields: _sessionFields('【会话认证】已收到认证后的设备信息，记录设备上报的协议版本', {
          'connection_attempt': connectionAttempt,
          'endpoint': BleLogicalEndpoint.fa10Fa11.name,
          'command': '0x81',
          'protocol_version': info.capabilities.protocolVersion,
          'mtu': mtu,
        }),
      );
      // TEMP(EVT): Skip only the version gate during firmware integration.
      // Restore after firmware alignment; payload and FileName[17] rules stay.
      // if (info.capabilities.protocolVersion !=
      //     EvtProtocolContract.evtV16ProtocolVersion) {
      //   throw BleTransportException(
      //     EvtFailure.protocol(
      //       message: '设备协议版本不受支持。',
      //       detail:
      //           '需要 ProtocolVersion=${EvtProtocolContract.evtV16ProtocolVersion}，实际为 ${info.capabilities.protocolVersion}。',
      //     ),
      //   );
      // }
      _logger.warning(
        'authentication_protocol_version_check_skipped',
        operation: 'device_authenticate',
        stage: 'validation',
        result: 'accepted',
        fields: _sessionFields('【协议版本】联调阶段临时跳过版本号校验，仍按当前字段布局和 17 字节文件名规则处理', {
          'connection_attempt': connectionAttempt,
          'protocol_version': info.capabilities.protocolVersion,
        }),
      );
      configuration = _baselineConfigurationFor(info);
      await _writeAuthenticationConfiguration(configuration);
    } catch (error) {
      _logger.warning(
        'authentication_synchronization_failed',
        operation: 'device_authenticate',
        stage: 'sync',
        result: 'failed',
        elapsed: DateTime.now().difference(startedAt),
        fields: _sessionFields('【会话认证】认证后的设备信息或基线配置同步失败', {
          'connection_attempt': connectionAttempt,
          'error_type': error.runtimeType.toString(),
        }),
      );
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
      'authentication_synchronization_completed',
      operation: 'device_authenticate',
      stage: 'sync',
      result: 'success',
      elapsed: DateTime.now().difference(startedAt),
      fields: _sessionFields('【会话认证】认证后同步完成，设备会话已进入可用状态', {
        'connection_attempt': connectionAttempt,
        'mtu': mtu,
        'granted_permissions': permissions
            .map((permission) => permission.name)
            .toList(growable: false),
      }),
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
      // EVT does not expose the FA18 real-time audio feature. Always clear
      // the fixed V1.6 AudioStream byte so an earlier P2/PVT state cannot be
      // retained when this connection completes authentication.
      audioStream: 0,
    );
  }

  Future<EvtFrame> _setRecordAction(int action) async {
    if (_state.isRecordActionInFlight) {
      throw StateError('录音操作正在执行。');
    }
    final startedAt = DateTime.now();
    _logger.info(
      'record_action_requested',
      operation: 'device_connect',
      stage: 'write',
      result: 'pending',
      fields: _sessionFields('【会话录音】准备向设备下发录音控制命令', {
        'endpoint': BleLogicalEndpoint.fa10Fa17.name,
        'action': action,
        'command': '0x07',
        'expected_command': '0x87',
      }),
    );
    _state = _state.copyWith(isRecordActionInFlight: true);
    notifyListeners();
    try {
      final response = await _requireProtocol().setRecordAction(action);
      final snapshot = _snapshotFromFrame(response, source: '录音控制响应');
      if (snapshot != null && _state.isObservable) {
        _state = _state.copyWith(latestSnapshot: snapshot, failure: null);
        notifyListeners();
      }
      _logger.info(
        'record_action_completed',
        operation: 'device_connect',
        stage: 'response',
        result: 'success',
        elapsed: DateTime.now().difference(startedAt),
        fields: _sessionFields('【会话录音】已收到设备录音控制响应并更新状态快照', {
          'endpoint': BleLogicalEndpoint.fa10Fa17.name,
          'action': action,
          'command': '0x87',
          'content_length': response.content.length,
        }),
      );
      return response;
    } catch (error) {
      _logger.warning(
        'record_action_failed',
        operation: 'device_connect',
        stage: 'response',
        result: 'failed',
        elapsed: DateTime.now().difference(startedAt),
        fields: _sessionFields('【会话录音】录音控制未完成，保留错误类型供联调判断', {
          'endpoint': BleLogicalEndpoint.fa10Fa17.name,
          'action': action,
          'error_type': error.runtimeType.toString(),
        }),
      );
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

  /// Confirms that normal V1.6 Action=2 may be sent on the current session.
  ///
  /// This is deliberately a fresh device-side check rather than a check of
  /// only cached UI values: a destructive UNBIND must not race an active
  /// recording, sync, or an unsynchronized file. A recovery Action=2 is not
  /// routed here because it represents a command that was already sent.
  Future<void> verifyEvtUnbindPreflight() async {
    final connectionAttempt = _connectionAttempt;
    final startedAt = DateTime.now();
    _logger.info(
      'evt_unbind_preflight_requested',
      operation: 'device_unbind',
      stage: 'preflight',
      result: 'pending',
      fields: _sessionFields('【解绑预检】开始确认设备可以安全执行解绑，不发送 Action=2', {
        'connection_attempt': connectionAttempt,
        'checks': const <String>[
          'observable_session',
          'record_state',
          'sync_state',
          'first_file_page',
        ],
      }),
    );
    if (!_state.isObservable) {
      _rejectEvtUnbindPreflight(
        connectionAttempt: connectionAttempt,
        startedAt: startedAt,
        check: 'observable_session',
        message: '设备尚未完成认证并进入可用状态，暂时不能解绑。',
      );
    }
    if (_state.isRecordActionInFlight) {
      _rejectEvtUnbindPreflight(
        connectionAttempt: connectionAttempt,
        startedAt: startedAt,
        check: 'record_action',
        message: '设备录音操作仍在处理中，请完成后再解绑。',
      );
    }
    final cachedState = _state.latestSnapshot?.state;
    if (cachedState == DeviceState.recording ||
        cachedState == DeviceState.paused) {
      _rejectEvtUnbindPreflight(
        connectionAttempt: connectionAttempt,
        startedAt: startedAt,
        check: 'record_state_cached',
        message: '设备正在录音或已暂停录音，请先结束录音后再解绑。',
        fields: {'state': cachedState?.name},
      );
    }

    try {
      _requireDevicePermission(DevicePermission.status);
      _requireDevicePermission(DevicePermission.files);
      final info = await readDeviceInfo();
      _requireCurrentConnectionAttempt(connectionAttempt);
      if (info.recordStatus != 0) {
        _rejectEvtUnbindPreflight(
          connectionAttempt: connectionAttempt,
          startedAt: startedAt,
          check: 'record_state_live',
          message: info.recordStatus == 1 || info.recordStatus == 2
              ? '设备正在录音或已暂停录音，请先结束录音后再解绑。'
              : '设备录音状态异常，无法确认可以安全解绑。',
          fields: {'record_status': info.recordStatus},
        );
      }

      final status = await readStatus();
      _requireCurrentConnectionAttempt(connectionAttempt);
      if (status.syncState != 0) {
        _rejectEvtUnbindPreflight(
          connectionAttempt: connectionAttempt,
          startedAt: startedAt,
          check: 'sync_state',
          message: '设备正在同步或同步状态异常，请完成文件同步后再解绑。',
          fields: {'sync_state': status.syncState},
        );
      }

      final files = await listFiles(offset: 0, pageSize: 1);
      _requireCurrentConnectionAttempt(connectionAttempt);
      _requireDevicePermission(DevicePermission.files);
      if (files.isNotEmpty) {
        _rejectEvtUnbindPreflight(
          connectionAttempt: connectionAttempt,
          startedAt: startedAt,
          check: 'first_file_page',
          message: '设备仍有未同步录音文件，请先完成文件同步后再解绑。',
          fields: {'file_count_on_first_page': files.length},
        );
      }
    } on EvtUnbindPreflightException {
      rethrow;
    } catch (error) {
      _rejectEvtUnbindPreflight(
        connectionAttempt: connectionAttempt,
        startedAt: startedAt,
        check: 'device_verification',
        message: '无法确认设备录音、同步和文件状态，请重新连接后完成文件同步再解绑。',
        fields: {'error_type': error.runtimeType.toString()},
      );
    }

    _logger.info(
      'evt_unbind_preflight_completed',
      operation: 'device_unbind',
      stage: 'preflight',
      result: 'success',
      elapsed: DateTime.now().difference(startedAt),
      fields: _sessionFields('【解绑预检】设备处于空闲、未同步文件为空，可以打开安全码输入', {
        'connection_attempt': connectionAttempt,
        'sync_state': 0,
        'file_count_on_first_page': 0,
      }),
    );
  }

  Never _rejectEvtUnbindPreflight({
    required int connectionAttempt,
    required DateTime startedAt,
    required String check,
    required String message,
    Map<String, Object?> fields = const {},
  }) {
    _logger.warning(
      'evt_unbind_preflight_rejected',
      operation: 'device_unbind',
      stage: 'preflight',
      result: 'failed',
      elapsed: DateTime.now().difference(startedAt),
      fields: _sessionFields('【解绑预检】$message', {
        'connection_attempt': connectionAttempt,
        'check': check,
        ...fields,
      }),
    );
    throw EvtUnbindPreflightException(message);
  }

  Future<List<DeviceFile>> listFiles({
    int offset = 0,
    int pageSize = 10,
  }) async {
    final connectionAttempt = _connectionAttempt;
    final startedAt = DateTime.now();
    _logger.info(
      'file_list_requested',
      operation: 'device_file_import',
      stage: 'request',
      result: 'pending',
      fields: _sessionFields('【会话文件】准备请求设备文件列表，不记录文件名称或内容', {
        'endpoint': BleLogicalEndpoint.ff10Ff12.name,
        'command': '0x22',
        'expected_command': '0xA2',
        'offset': offset,
        'length': pageSize,
      }),
    );
    _requireDevicePermission(DevicePermission.files);
    _requireCommandEndpoint(BleLogicalEndpoint.ff10Ff12, BleOperation.indicate);
    await _ensureResponseSubscription(
      BleLogicalEndpoint.ff10Ff12,
      critical: true,
    );
    _requireCurrentConnectionAttempt(connectionAttempt);
    _requireDevicePermission(DevicePermission.files);
    final mtu = await _ensureAttMtu(31);
    _requireCurrentConnectionAttempt(connectionAttempt);
    // Recheck connection-scoped authorization immediately before the 0x22
    // command is written. This also closes a disconnect/revoke race while CCC
    // or MTU setup is pending; V1.6 has no post-AUTH local TTL.
    _requireDevicePermission(DevicePermission.files);
    // A 0xA2 page has a seven-byte outer-frame overhead plus 21 bytes per
    // entry, and the ATT indication reserves three bytes. Do not turn an
    // undersized MTU into a fictitious one-entry capability; _ensureAttMtu
    // above has already required the protocol minimum of 31.
    final supportedPageSize = min(20, (mtu - 10) ~/ 21);
    final effectivePageSize = min(pageSize, supportedPageSize);
    _logger.info(
      'file_list_request_admitted',
      operation: 'device_file_import',
      stage: 'request',
      result: 'accepted',
      elapsed: DateTime.now().difference(startedAt),
      fields: _sessionFields('【会话文件】文件列表请求已通过 MTU 和当前连接认证权限校验', {
        'endpoint': BleLogicalEndpoint.ff10Ff12.name,
        'command': '0x22',
        'offset': offset,
        'length': effectivePageSize,
        'mtu': mtu,
      }),
    );
    try {
      final files = await _requireProtocol().listFiles(
        offset: offset,
        pageSize: effectivePageSize,
      );
      _requireCurrentConnectionAttempt(connectionAttempt);
      _logger.info(
        'file_list_completed',
        operation: 'device_file_import',
        stage: 'response',
        result: 'success',
        elapsed: DateTime.now().difference(startedAt),
        fields: _sessionFields('【会话文件】文件列表响应已校验，只记录条目数量', {
          'endpoint': BleLogicalEndpoint.ff10Ff12.name,
          'command': '0xA2',
          'offset': offset,
          'file_count': files.length,
          'mtu': mtu,
        }),
      );
      return files;
    } catch (error, stackTrace) {
      // V1.6 0xA2 does not carry the requested page offset. A late indication
      // therefore cannot be safely distinguished from a later 0x22 request.
      // Reset the BLE session after any dispatched 0x22 failure before a new
      // listing can begin. That also covers an ambiguous GATT write failure.
      final timeoutError = error is EvtCommandTimeoutException ? error : null;
      final timedOut = timeoutError != null;
      _logger.warning(
        'file_list_failed',
        operation: 'device_file_import',
        stage: 'response',
        result: 'failed',
        elapsed: DateTime.now().difference(startedAt),
        fields: _sessionFields('【会话文件】文件列表响应不确定，准备重置连接避免旧响应混入', {
          'endpoint': BleLogicalEndpoint.ff10Ff12.name,
          'command': '0xA2',
          'offset': offset,
          'error_type': error.runtimeType.toString(),
          if (timeoutError != null) 'attempt': timeoutError.attempts,
        }),
      );
      await _invalidateSessionForAmbiguousProtocolResult(
        connectionAttempt: connectionAttempt,
        event: timedOut
            ? 'file_list_response_timeout_requires_reconnect'
            : 'file_list_response_uncertain_requires_reconnect',
        message: timedOut
            ? '设备文件列表响应超时，已断开连接以避免使用迟到数据。'
            : '设备文件列表响应异常，已断开连接以避免使用迟到数据。',
        fields: _sessionFields('【会话文件】文件列表无法关联当前请求，主动断开连接', {
          'offset': offset,
          'error_type': error.runtimeType.toString(),
          if (timeoutError != null) 'attempt': timeoutError.attempts,
        }),
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
    int? expectedFileLength,
  }) {
    final connectionAttempt = _connectionAttempt;
    final transferRequestFields = <String, Object?>{
      'endpoint': BleLogicalEndpoint.ff10Ff13.name,
      'command': '0x23',
      'expected_command': '0xA3',
      'offset': startOffset,
      'length': chunkSize,
      'content_length': nameSlot.length,
    };
    if (expectedFileLength != null) {
      transferRequestFields['expected_file_length'] = expectedFileLength;
    }
    _logger.info(
      'file_transfer_requested',
      operation: 'device_file_import',
      stage: 'request',
      result: 'pending',
      fields: _sessionFields(
        '【会话文件】准备请求设备文件流，不记录文件名槽位或音频内容',
        transferRequestFields,
      ),
    );
    // An async* wrapper does not propagate a caller's cancellation through an
    // await-for until its child stream resumes. A silent 0x23 transfer can
    // therefore wait for the 15-second idle timer after the file screen has
    // gone away. Keep a direct subscription here so caller cancellation can
    // close the ambiguous V1.6 transfer session immediately while this layer
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
            connectionAttempt: connectionAttempt,
            event: event,
            message: message,
            fields: _sessionFields('【会话文件】连续文件流未收到结束帧，主动关闭会话避免旧数据串入', {
              'offset': startOffset,
              'error_type': error.runtimeType.toString(),
            }),
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
          operation: 'device_file_import',
          stage: 'idle',
          result: 'cancelled',
          fields: _sessionFields('【会话文件】调用方取消文件流，忽略关闭后的预期源流错误', {
            'error_type': error.runtimeType.toString(),
          }),
        );
      }
    }

    void startSource() {
      _logger.info(
        'file_transfer_source_started',
        operation: 'device_file_import',
        stage: 'download',
        result: 'pending',
        fields: _sessionFields('【会话文件】订阅已建立，开始等待设备文件流数据', {
          'endpoint': BleLogicalEndpoint.ff10Ff13.name,
          'command': '0x23',
          'offset': startOffset,
          'length': chunkSize,
        }),
      );
      transferSubscription =
          _downloadEvtFileInternal(
            connectionAttempt: connectionAttempt,
            nameSlot: nameSlot,
            startOffset: startOffset,
            chunkSize: chunkSize,
            expectedFileLength: expectedFileLength,
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
                _logger.info(
                  'file_transfer_terminal_forwarded',
                  operation: 'device_file_import',
                  stage: 'download',
                  result: 'completed',
                  fields: _sessionFields('【会话文件】已转发设备文件流结束帧给调用方', {
                    'endpoint': BleLogicalEndpoint.ff10Ff13.name,
                    'command': '0x23',
                    'offset': startOffset,
                  }),
                );
              }
              if (!callerCancelled && !controller.isClosed) {
                controller.add(event);
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              _logger.warning(
                'file_transfer_source_failed',
                operation: 'device_file_import',
                stage: 'download',
                result: 'failed',
                fields: _sessionFields('【会话文件】设备文件流发生错误，等待会话清理结果', {
                  'endpoint': BleLogicalEndpoint.ff10Ff13.name,
                  'command': '0x23',
                  'error_type': error.runtimeType.toString(),
                }),
              );
              if (!callerCancelled && !controller.isClosed) {
                controller.addError(error, stackTrace);
              }
            },
            onDone: () {
              _logger.info(
                'file_transfer_source_completed',
                operation: 'device_file_import',
                stage: 'download',
                result: terminalReceived ? 'completed' : 'failed',
                fields: _sessionFields(
                  terminalReceived
                      ? '【会话文件】设备文件流已在结束帧后关闭'
                      : '【会话文件】设备文件流未见结束帧即关闭，后续将清理会话',
                  {
                    'endpoint': BleLogicalEndpoint.ff10Ff13.name,
                    'command': '0x23',
                  },
                ),
              );
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
        _logger.info(
          'file_transfer_cancellation_requested',
          operation: 'device_file_import',
          stage: 'idle',
          result: 'cancelled',
          fields: _sessionFields('【会话文件】调用方停止接收文件流，开始取消源流并清理会话', {
            'endpoint': BleLogicalEndpoint.ff10Ff13.name,
            'command': '0x23',
            'offset': startOffset,
          }),
        );
        // Do not await the source cancellation. Its async* body can be
        // waiting for the next Notify, while the V1.6 session must be reset
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
    required int connectionAttempt,
    required List<int> nameSlot,
    required int startOffset,
    required int chunkSize,
    required int? expectedFileLength,
    required VoidCallback onTransferStarted,
    required VoidCallback onTerminalReceived,
    required bool Function() isCallerCancelled,
    required Future<void> Function(Object error) onIncompleteTransfer,
  }) async* {
    void requireActiveCaller() {
      _requireCurrentConnectionAttempt(connectionAttempt);
      if (isCallerCancelled()) {
        throw StateError('设备文件传输已取消。');
      }
    }

    final startedAt = DateTime.now();
    var receivedBytes = 0;
    var nextProgressLogBytes = 64 * 1024;
    var terminalReceived = false;
    var incompleteTransferNotified = false;

    Future<void> notifyIncompleteTransfer(Object error) async {
      // The async* body can enter both catch and finally for the same failure.
      // Keep session invalidation idempotent here so a single broken transfer
      // cannot trigger duplicate disconnects or mask the original error.
      if (terminalReceived || incompleteTransferNotified) {
        return;
      }
      incompleteTransferNotified = true;
      await onIncompleteTransfer(error);
    }

    try {
      requireActiveCaller();
      _requireDevicePermission(DevicePermission.files);
      _requireCommandEndpoint(BleLogicalEndpoint.ff10Ff13, BleOperation.notify);
      await _ensureResponseSubscription(
        BleLogicalEndpoint.ff10Ff13,
        critical: true,
      );
      requireActiveCaller();
      _requireDevicePermission(DevicePermission.files);
      final requiredMtu = _requiredFileTransferMtu(
        startOffset: startOffset,
        chunkSize: chunkSize,
      );
      final mtu = await _ensureAttMtu(requiredMtu);
      requireActiveCaller();
      final effectiveChunkLimit = _effectiveFileChunkLimit(mtu);
      if (effectiveChunkLimit < 1) {
        throw StateError('当前 ATT MTU 不足，无法接收文件数据。');
      }
      if (chunkSize > 0 && chunkSize > effectiveChunkLimit) {
        throw StateError(
          '请求分块 $chunkSize 字节超过当前 ATT MTU 可承载上限 '
          '$effectiveChunkLimit。',
        );
      }
      // Do not let a revoked/disconnected session reach the 0x23 write after
      // an awaited setup step. The per-event check below also stops an active
      // transfer; successful AUTH remains valid until BLE disconnect/restart.
      _requireDevicePermission(DevicePermission.files);
      _logger.info(
        'file_transfer_request_admitted',
        operation: 'device_file_import',
        stage: 'download',
        result: 'accepted',
        elapsed: DateTime.now().difference(startedAt),
        fields: _sessionFields('【会话文件】文件流请求已通过权限、订阅和 MTU 校验', {
          'endpoint': BleLogicalEndpoint.ff10Ff13.name,
          'command': '0x23',
          'offset': startOffset,
          'length': chunkSize,
          'required_mtu': requiredMtu,
          'mtu': mtu,
          'effective_chunk_limit': effectiveChunkLimit,
        }),
      );
      final transfer = _requireProtocol().downloadEvtFile(
        nameSlot: nameSlot,
        startOffset: startOffset,
        chunkSize: chunkSize,
        expectedFileLength: expectedFileLength,
      );
      onTransferStarted();
      _logger.info(
        'file_transfer_command_dispatched',
        operation: 'device_file_import',
        stage: 'write',
        result: 'pending',
        elapsed: DateTime.now().difference(startedAt),
        fields: _sessionFields('【会话文件】设备已接收文件流请求，开始等待连续数据帧', {
          'endpoint': BleLogicalEndpoint.ff10Ff13.name,
          'command': '0x23',
          'offset': startOffset,
        }),
      );
      await for (final event in transfer) {
        requireActiveCaller();
        // The permission is checked immediately before the one and only 0x23
        // Write. Once the device has accepted that write, every following
        // Notify belongs to the same continuous transfer. A V1.6 auth window
        // expiring while a large file is in flight must block a later command,
        // not discard already-authorized bytes and force a needless restart.
        if (event.isTerminal) {
          terminalReceived = true;
          onTerminalReceived();
          _logger.info(
            'file_transfer_terminal_received',
            operation: 'device_file_import',
            stage: 'download',
            result: 'completed',
            elapsed: DateTime.now().difference(startedAt),
            fields: _sessionFields('【会话文件】设备已发送文件流结束帧，未记录任何文件原文', {
              'endpoint': BleLogicalEndpoint.ff10Ff13.name,
              'command': '0x23',
              'bytes': receivedBytes,
            }),
          );
        } else {
          if (event.bytes.length > effectiveChunkLimit) {
            _logger.warning(
              'file_transfer_chunk_exceeds_mtu',
              operation: 'device_file_import',
              stage: 'download',
              result: 'failed',
              elapsed: DateTime.now().difference(startedAt),
              fields: _sessionFields('【会话文件】设备文件数据块超过当前 ATT MTU 可承载上限，拒绝写入本地', {
                'endpoint': BleLogicalEndpoint.ff10Ff13.name,
                'command': '0xA3',
                'chunk_bytes': event.bytes.length,
                'effective_chunk_limit': effectiveChunkLimit,
                'mtu': mtu,
                'received_bytes': receivedBytes,
              }),
            );
            throw StateError(
              '设备文件数据块 ${event.bytes.length} 字节超过当前 ATT MTU '
              '可承载上限 $effectiveChunkLimit。',
            );
          }
          receivedBytes += event.bytes.length;
          if (receivedBytes >= nextProgressLogBytes) {
            _logger.info(
              'file_transfer_progress',
              operation: 'device_file_import',
              stage: 'download',
              result: 'pending',
              elapsed: DateTime.now().difference(startedAt),
              fields: _sessionFields('【会话文件】文件流持续接收中，仅按累计字节周期记录进度', {
                'endpoint': BleLogicalEndpoint.ff10Ff13.name,
                'command': '0x23',
                'bytes': receivedBytes,
                'content_length': event.bytes.length,
              }),
            );
            nextProgressLogBytes += 64 * 1024;
          }
        }
        yield event;
      }
      if (!terminalReceived) {
        throw StateError('设备文件传输未返回结束帧。');
      }
    } catch (error, stackTrace) {
      if (error is EvtFileTransferChunkMtuException) {
        // The repository has already validated the frame shape. Preserve the
        // MTU-specific reason here so a real-device log clearly distinguishes
        // an oversized Notify from malformed or out-of-order file data before
        // the ambiguous transfer session is disconnected below.
        _logger.warning(
          'file_transfer_chunk_exceeds_mtu',
          operation: 'device_file_import',
          stage: 'download',
          result: 'failed',
          elapsed: DateTime.now().difference(startedAt),
          fields: _sessionFields('【会话文件】设备文件数据块超过当前 ATT MTU 可承载上限，拒绝写入本地', {
            'endpoint': BleLogicalEndpoint.ff10Ff13.name,
            'command': '0xA3',
            'chunk_bytes': error.chunkBytes,
            'effective_chunk_limit': error.maxChunkBytes,
            if (error.attMtu != null) 'mtu': error.attMtu,
            'received_bytes': receivedBytes,
          }),
        );
      }
      _logger.warning(
        'file_transfer_failed',
        operation: 'device_file_import',
        stage: 'download',
        result: 'failed',
        elapsed: DateTime.now().difference(startedAt),
        fields: _sessionFields('【会话文件】文件流未正常结束，准备清理会话避免旧数据进入下次请求', {
          'endpoint': BleLogicalEndpoint.ff10Ff13.name,
          'command': '0x23',
          'bytes': receivedBytes,
          'error_type': error.runtimeType.toString(),
        }),
      );
      await notifyIncompleteTransfer(error);
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      if (terminalReceived) {
        _logger.info(
          'file_transfer_completed',
          operation: 'device_file_import',
          stage: 'download',
          result: 'completed',
          elapsed: DateTime.now().difference(startedAt),
          fields: _sessionFields('【会话文件】文件流完整结束，保留连接供后续设备操作使用', {
            'endpoint': BleLogicalEndpoint.ff10Ff13.name,
            'command': '0x23',
            'bytes': receivedBytes,
          }),
        );
      } else {
        // A cancellation, source error, or stream close without EOF is an
        // ambiguous transfer result and must invalidate the session. Normal
        // EOF deliberately leaves the BLE connection usable.
        await notifyIncompleteTransfer(StateError('连续文件传输未收到结束帧。'));
      }
    }
  }

  Future<void> connect(DeviceCandidate candidate) async {
    if (_isDisposed) {
      throw StateError('设备会话已关闭。');
    }
    final startedAt = DateTime.now();
    final connectionAttempt = ++_connectionAttempt;
    final previousDeviceId = _state.session?.candidate.connectionId;
    _logger.info(
      'session_open_requested',
      operation: 'device_connect',
      stage: 'initialization',
      result: 'pending',
      fields: _sessionFields('【会话连接】收到打开设备会话请求，先关闭上一轮本地资源', {
        'connection_attempt': connectionAttempt,
        'device_suffix': _redactDeviceId(candidate.connectionId),
        'has_name': candidate.name.trim().isNotEmpty,
        'rssi': candidate.rssi,
        'previous_state': _state.phase.name,
        'configured': previousDeviceId != null,
      }),
    );
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
    _preAuthenticationInfoReadInProgress = false;
    if (previousDeviceId != null) {
      _logger.info(
        'previous_session_disconnect_requested',
        operation: 'device_connect',
        stage: 'initialization',
        result: 'pending',
        fields: _sessionFields('【会话连接】上一轮会话存在，先请求底层断开旧连接', {
          'connection_attempt': connectionAttempt,
          'device_suffix': _redactDeviceId(previousDeviceId),
        }),
      );
      await _transport.disconnect(previousDeviceId);
      if (!_isCurrentConnectionAttempt(connectionAttempt)) {
        return;
      }
    }
    _state = const SessionState(phase: SessionPhase.environmentReady);
    _transition(SessionPhase.discovered);
    _logger.info(
      'connect_start',
      operation: 'device_connect',
      stage: 'connect',
      result: 'pending',
      fields: _sessionFields('【会话连接】本地会话已重置，开始连接候选设备', {
        'connection_attempt': connectionAttempt,
        'device_suffix': _redactDeviceId(candidate.connectionId),
        'has_name': candidate.name.trim().isNotEmpty,
        'rssi': candidate.rssi,
      }),
    );

    if (!_profile.isGattReady) {
      _logger.error(
        'connect_profile_invalid',
        operation: 'device_connect',
        stage: 'validation',
        result: 'failed',
        elapsed: DateTime.now().difference(startedAt),
        fields: _sessionFields('【会话连接】本地 EVT GATT 配置无效，未调用系统连接', {
          'connection_attempt': connectionAttempt,
        }),
      );
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
    _logger.info(
      'gatt_connection_stream_requested',
      operation: 'device_connect',
      stage: 'connecting',
      result: 'pending',
      fields: _sessionFields('【会话连接】已调用底层 GATT 连接流，等待系统连接状态回调', {
        'connection_attempt': connectionAttempt,
        'device_suffix': _redactDeviceId(candidate.connectionId),
        'timeout_ms': _connectionSetupTimeout.inMilliseconds,
      }),
    );
    _connectionSubscription = _transport
        .connect(candidate.connectionId)
        .listen(
          (connection) {
            if (!_isCurrentConnectionAttempt(connectionAttempt)) {
              return;
            }
            _logger.info(
              'connection_state',
              operation: 'device_connect',
              stage: 'connect',
              fields: _sessionFields(
                switch (connection) {
                  BleConnectionState.connected => '【会话连接】系统报告 GATT 已连接，继续服务发现',
                  BleConnectionState.disconnected =>
                    '【会话连接】系统报告 GATT 已断开，准备结束会话',
                  _ => '【会话连接】收到系统 GATT 连接状态变化',
                },
                {
                  'connection_attempt': connectionAttempt,
                  'device_suffix': _redactDeviceId(candidate.connectionId),
                  'state': connection.name,
                  'elapsed_ms': DateTime.now()
                      .difference(startedAt)
                      .inMilliseconds,
                },
              ),
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
              operation: 'device_connect',
              stage: 'connect',
              result: 'failed',
              fields: _sessionFields('【会话连接】系统 GATT 连接流返回错误，准备中断会话', {
                'connection_attempt': connectionAttempt,
                'device_suffix': _redactDeviceId(candidate.connectionId),
                'error_type': error.runtimeType.toString(),
                'elapsed_ms': DateTime.now()
                    .difference(startedAt)
                    .inMilliseconds,
              }),
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
              operation: 'device_connect',
              stage: 'connect',
              fields: _sessionFields('【会话连接】系统 GATT 连接流结束，检查是否需要中断会话', {
                'connection_attempt': connectionAttempt,
                'device_suffix': _redactDeviceId(candidate.connectionId),
                'elapsed_ms': DateTime.now()
                    .difference(startedAt)
                    .inMilliseconds,
              }),
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
      _logger.info(
        'gatt_service_discovery_requested',
        operation: 'device_connect',
        stage: 'connected',
        result: 'pending',
        elapsed: DateTime.now().difference(startedAt),
        fields: _sessionFields('【会话连接】GATT 已连接，开始读取设备服务和特征能力', {
          'connection_attempt': connectionAttempt,
          'device_suffix': _redactDeviceId(candidate.connectionId),
          'timeout_ms': _operationTimeout.inMilliseconds,
        }),
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
      final iosCccModeConflicts = _iosCccModeConflicts(services);
      final gattContractViolations = <String>[
        ...missingEndpointOperations,
        ...iosCccModeConflicts,
      ];
      _logger.info(
        'gatt_service_discovery_completed',
        operation: 'device_connect',
        stage: 'validation',
        result: 'success',
        elapsed: DateTime.now().difference(startedAt),
        fields: _sessionFields('【会话连接】服务发现完成，开始校验 EVT 所需特征能力', {
          'connection_attempt': connectionAttempt,
          'service_count': services.length,
          'characteristic_count': services.fold<int>(
            0,
            (total, service) => total + service.characteristics.length,
          ),
        }),
      );
      _logger.info(
        'evt_gatt_contract_checked',
        operation: 'device_connect',
        stage: 'validation',
        result: gattContractViolations.isEmpty ? 'success' : 'failed',
        elapsed: DateTime.now().difference(startedAt),
        fields: _sessionFields(
          gattContractViolations.isEmpty
              ? '【会话连接】GATT 合约校验通过，可建立 EVT 响应订阅'
              : '【会话连接】GATT 合约不满足 EVT 联调条件，当前设备不能进入认证或控制流程',
          {
            'connection_attempt': connectionAttempt,
            'service_count': services.length,
            'characteristic_count': services.fold<int>(
              0,
              (total, service) => total + service.characteristics.length,
            ),
            'missing_count': missingEndpointOperations.length,
            'ios_ccc_mode_conflict_count': iosCccModeConflicts.length,
          },
        ),
      );
      if (gattContractViolations.isNotEmpty) {
        _logger.info(
          'evt_gatt_contract_mismatch',
          operation: 'device_connect',
          stage: 'validation',
          result: 'failed',
          fields: _sessionFields('【会话连接】已记录不符合 EVT 的特征能力，随后关闭会话', {
            'connection_attempt': connectionAttempt,
            // The sanitizer only accepts EVT endpoint.operation descriptors,
            // which keeps the precise GATT failure visible in Debug logs
            // without allowing arbitrary device-originated strings through.
            'missing_endpoints': gattContractViolations.join(','),
          }),
        );
        _fail(
          EvtFailure.access(
            message: '设备 GATT 不符合 EVT V1.6 联调要求。',
            detail: _gattContractFailureDetail(
              missingEndpointOperations: missingEndpointOperations,
              iosCccModeConflicts: iosCccModeConflicts,
            ),
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
      _logger.info(
        'evt_response_channel_initialized',
        operation: 'device_connect',
        stage: 'initialization',
        result: 'success',
        fields: _sessionFields('【会话订阅】已创建本地 EVT 响应总线，开始建立特征订阅', {
          'connection_attempt': connectionAttempt,
          'subscription_count': _subscribedEndpointKeys.length,
        }),
      );
      _commandClient = EvtCommandClient(
        transport: _transport,
        codec: _codec,
        responses: _responseController!.stream,
        logger: _commandLogger,
        beforeWrite: _admitEvtCommandWrite,
        onResponseTimeout: (request) {
          // Old native writes can finish after a reconnect. Their timeout
          // must never discard bytes belonging to the replacement session.
          if (!_isCurrentConnectionAttempt(connectionAttempt)) return;
          final characteristic = request.writeCharacteristic;
          if (characteristic.deviceId != candidate.connectionId) return;
          final key =
              '${characteristic.serviceUuid}|${characteristic.characteristicUuid}'
                  .toUpperCase();
          _notificationFrameAssemblers[key]?.reset();
        },
      );
      _protocolRepository = DeviceProtocolRepository(
        deviceId: candidate.connectionId,
        profile: _profile,
        transport: _transport,
        commands: _commandClient!,
        codec: _codec,
        legacySecurityResponseTimeout: _legacySecurityResponseTimeout,
        legacyBindResponseTimeout: _legacyBindResponseTimeout,
        legacyUnbindResponseTimeout: _legacyUnbindResponseTimeout,
        fileListResponseTimeout: _fileListResponseTimeout,
        fileTransferIdleTimeout: _fileTransferIdleTimeout,
        negotiatedAttMtuProvider: () => _attMtu,
      );
      _logger.info(
        'evt_pre_auth_subscription_setup_requested',
        operation: 'device_connect',
        stage: 'connect',
        result: 'pending',
        fields: _sessionFields('【会话订阅】V1.6 预认证阶段只订阅 FA11 和 FA19', {
          'connection_attempt': connectionAttempt,
          'endpoints': EvtProtocolContract.preAuthenticationSubscriptionOrder
              .map((endpoint) => endpoint.name)
              .toList(growable: false),
          'timeout_ms': _notificationSetupTimeout.inMilliseconds,
        }),
      );
      await _subscribeEvtEndpointsBeforeAuthentication();
      if (!_isCurrentConnectionAttempt(connectionAttempt) ||
          _state.phase != SessionPhase.subscribing) {
        return;
      }
      await _readPreAuthenticationDeviceInfo(connectionAttempt);
      if (!_isCurrentConnectionAttempt(connectionAttempt) ||
          _state.phase != SessionPhase.subscribing) {
        return;
      }
      _transition(SessionPhase.authenticationReady);
      _logger.info(
        'session_authentication_ready',
        operation: 'device_connect',
        stage: 'connect',
        result: 'success',
        elapsed: DateTime.now().difference(startedAt),
        fields: _sessionFields('【会话订阅】预认证身份读取完成，可以发起 V1.6 认证或绑定', {
          'connection_attempt': connectionAttempt,
          'subscription_count': _subscribedEndpointKeys.length,
          'protocol_version': EvtProtocolContract.evtV16ProtocolVersion,
        }),
      );
    } catch (error) {
      if (!_isCurrentConnectionAttempt(connectionAttempt)) {
        return;
      }
      _logger.warning(
        'connect_setup_failed',
        operation: 'device_connect',
        stage: 'connect',
        result: 'failed',
        elapsed: DateTime.now().difference(startedAt),
        fields: _sessionFields('【会话连接】连接、服务发现或订阅建立失败，准备清理资源', {
          'connection_attempt': connectionAttempt,
          'error_type': error.runtimeType.toString(),
          'state': _state.phase.name,
        }),
      );
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
      _logger.info(
        'device_details_refresh_not_ready',
        operation: 'device_connect',
        stage: 'sync',
        result: 'cancelled',
        fields: _sessionFields('【会话刷新】会话尚未进入可用状态，跳过设备详情读取', {
          'state': _state.phase.name,
        }),
      );
      return;
    }
    if (permissions.contains(DevicePermission.status)) {
      // GET_STATUS (0x06) does not contain RecordStatus. Re-read 0x01 so
      // refresh can recover from a lost recording indication without
      // replaying a non-idempotent 0x07 control command.
      await _loadDeviceInfo(repository);
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
    _logger.info(
      'device_details_refresh_completed',
      operation: 'device_connect',
      stage: 'sync',
      result: 'completed',
      fields: _sessionFields('【会话刷新】当前权限范围内的设备详情读取已结束', {
        'granted_permissions': permissions
            .map((permission) => permission.name)
            .toList(growable: false),
      }),
    );
  }

  Future<void> _loadDeviceInfo(DeviceProtocolRepository repository) async {
    final connectionAttempt = _connectionAttempt;
    try {
      final info = await readDeviceInfo();
      if (!_isCurrentConnectionAttempt(connectionAttempt) ||
          !identical(repository, _protocolRepository) ||
          !_state.isObservable) {
        return;
      }
      _requireDevicePermission(DevicePermission.status);
      _state = _state.copyWith(
        deviceInfo: info,
        latestSnapshot: _snapshotFromDeviceInfo(info, source: '设备状态刷新'),
      );
      notifyListeners();
    } catch (error) {
      _logDeviceDetailFailure('device_info_load_failed', error);
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
      _logger.info(
        'device_status_loaded',
        operation: 'device_connect',
        stage: 'response',
        result: 'success',
        fields: _sessionFields('【会话刷新】已读取设备状态并更新详情快照', {
          'endpoint': BleLogicalEndpoint.fa10Fa16.name,
          'command': '0x86',
          'status': 'loaded',
        }),
      );
    } catch (error) {
      _logDeviceDetailFailure('device_status_load_failed', error);
    }
  }

  Future<void> _loadDeviceBattery(DeviceProtocolRepository repository) async {
    // V1.6 defines FB11 as Read + Indicate. The Read result is used for the
    // explicit refresh below, while the Indicate subscription keeps the
    // battery/charging snapshot current when the device changes state.
    if (!_state.supportsEndpoint(
          BleLogicalEndpoint.fb10Fb11,
          BleOperation.read,
        ) ||
        !_state.supportsEndpoint(
          BleLogicalEndpoint.fb10Fb11,
          BleOperation.indicate,
        )) {
      return;
    }
    try {
      await _ensureResponseSubscription(
        BleLogicalEndpoint.fb10Fb11,
        critical: false,
      );
      _requireDevicePermission(DevicePermission.status);
      final battery = await repository.readBattery();
      _updateDeviceDetails(deviceBattery: battery, repository: repository);
      _logger.info(
        'device_battery_loaded',
        operation: 'device_connect',
        stage: 'read',
        result: 'success',
        fields: _sessionFields('【会话刷新】已读取设备电量并更新详情快照', {
          'endpoint': BleLogicalEndpoint.fb10Fb11.name,
          'command': '0x91',
          'percent': battery.percent,
        }),
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
        operation: 'device_connect',
        stage: 'response',
        result: 'success',
        fields: _sessionFields('【会话刷新】已读取设备隐私时长并更新详情快照', {
          'endpoint': BleLogicalEndpoint.fa10Fa16.name,
          'command': '0x86',
          'duration_code': durationCode,
        }),
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
        operation: 'device_connect',
        stage: 'read',
        result: 'success',
        fields: _sessionFields('【会话刷新】已读取设备配置时间，仅记录 UTC 秒级摘要', {
          'endpoint': BleLogicalEndpoint.fa10Fa12.name,
          'utc_seconds': time.millisecondsSinceEpoch ~/ 1000,
        }),
      );
    } catch (error) {
      _logDeviceDetailFailure('device_configuration_time_load_failed', error);
    }
  }

  Future<void> _loadDeviceStorage(DeviceProtocolRepository repository) async {
    if (!_state.supportsEndpoint(
          BleLogicalEndpoint.fa10Fa15,
          BleOperation.write,
        ) ||
        !_state.supportsEndpoint(
          BleLogicalEndpoint.fa10Fa15,
          BleOperation.indicate,
        )) {
      return;
    }
    try {
      await _ensureResponseSubscription(
        BleLogicalEndpoint.fa10Fa15,
        critical: false,
      );
      _requireDevicePermission(DevicePermission.status);
      final storage = await repository.readStorage();
      _updateDeviceDetails(deviceStorage: storage, repository: repository);
      _logger.info(
        'device_storage_loaded',
        operation: 'device_connect',
        stage: 'read',
        result: 'success',
        fields: _sessionFields('【会话刷新】已读取设备存储容量并更新详情快照', {
          'endpoint': BleLogicalEndpoint.fa10Fa15.name,
          'command': '0x85',
          'free_mb': storage.freeMegabytes,
          'total_mb': storage.totalMegabytes,
        }),
      );
    } catch (error) {
      _logDeviceDetailFailure('device_storage_load_failed', error);
    }
  }

  Future<void> _loadFileCount(DeviceProtocolRepository repository) async {
    if (!_state.supportsEndpoint(
          BleLogicalEndpoint.ff10Ff11,
          BleOperation.write,
        ) ||
        !_state.supportsEndpoint(
          BleLogicalEndpoint.ff10Ff11,
          BleOperation.indicate,
        )) {
      return;
    }
    try {
      await _ensureResponseSubscription(
        BleLogicalEndpoint.ff10Ff11,
        critical: false,
      );
      _requireDevicePermission(DevicePermission.files);
      final count = await repository.readFileCount();
      _updateDeviceDetails(fileCount: count, repository: repository);
      _logger.info(
        'device_file_count_loaded',
        operation: 'device_file_import',
        stage: 'read',
        result: 'success',
        fields: _sessionFields('【会话刷新】已读取设备文件数量，不记录文件名称或内容', {
          'endpoint': BleLogicalEndpoint.ff10Ff11.name,
          'command': '0xA1',
          'file_count': count,
        }),
      );
    } catch (error) {
      _logDeviceDetailFailure('device_file_count_load_failed', error);
    }
  }

  /// Performs the V1.6 connection admission read. This is intentionally
  /// separate from the public authenticated [readDeviceInfo] API: FA11/0x01
  /// is the one protected-surface exception that exposes only the fixed
  /// 90-byte identity/version layout before Action=00 authentication.
  Future<void> _readPreAuthenticationDeviceInfo(int connectionAttempt) async {
    _requireCurrentConnectionAttempt(connectionAttempt);
    final repository = _requireProtocol();
    if (!_state.supportsEndpoint(
          BleLogicalEndpoint.fa10Fa11,
          BleOperation.write,
        ) ||
        !_state.supportsEndpoint(
          BleLogicalEndpoint.fa10Fa11,
          BleOperation.indicate,
        )) {
      throw StateError('设备未提供预认证设备信息所需的 FA11 能力。');
    }
    final startedAt = DateTime.now();
    _logger.info(
      'pre_authentication_device_info_requested',
      operation: 'device_connect',
      stage: 'pre_authentication',
      result: 'pending',
      fields: _sessionFields('【预认证】开始读取未认证 0x01 身份与版本信息', {
        'connection_attempt': connectionAttempt,
        'endpoint': BleLogicalEndpoint.fa10Fa11.name,
        'command': '0x01',
        'expected_command': '0x81',
        'redacted_content_bytes': 90,
        'minimum_att_mtu': _v16PreAuthenticationMinimumAttMtu,
      }),
    );
    final mtu = await _ensureAttMtu(_v16PreAuthenticationMinimumAttMtu);
    _requireCurrentConnectionAttempt(connectionAttempt);
    _preAuthenticationInfoReadInProgress = true;
    try {
      final info = await repository.readDeviceInfo(unauthenticated: true);
      _requireCurrentConnectionAttempt(connectionAttempt);
      if (!info.isRedacted) {
        throw const FormatException('未认证设备信息未按 V1.6 脱敏布局返回。');
      }
      // Keep identity/version available to the UI and future HTTPS code
      // lookup, but never copy redacted capacity, battery or record fields to
      // the authoritative live snapshot.
      _state = _state.copyWith(deviceInfo: info);
      notifyListeners();
      _logger.info(
        'pre_authentication_device_info_received',
        operation: 'device_connect',
        stage: 'pre_authentication',
        result: 'success',
        elapsed: DateTime.now().difference(startedAt),
        fields: _sessionFields('【预认证】已收到脱敏设备信息，可据 DeviceCode 取得安全码', {
          'connection_attempt': connectionAttempt,
          'endpoint': BleLogicalEndpoint.fa10Fa11.name,
          'command': '0x81',
          'content_bytes': 90,
          'mtu': mtu,
          'protocol_version': info.capabilities.protocolVersion,
          'device_code_present': info.deviceCode.isNotEmpty,
          'redacted': info.isRedacted,
        }),
      );
    } finally {
      _preAuthenticationInfoReadInProgress = false;
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
    _logger.warning(
      event,
      operation: 'device_connect',
      stage: 'response',
      result: 'failed',
      fields: _sessionFields('【会话刷新】设备详情读取失败，保留错误类型供联调判断', {
        'error_type': error.runtimeType.toString(),
      }),
    );
  }

  Future<void> disconnect() async {
    final connectionAttempt = ++_connectionAttempt;
    final session = _state.session;
    _logger.info(
      'disconnect_started',
      operation: 'device_connect',
      stage: 'connect',
      result: 'pending',
      fields: _sessionFields('【会话清理】用户主动断开设备，开始释放会话资源', {
        'connection_attempt': connectionAttempt,
        if (session != null)
          'device_suffix': _redactDeviceId(session.candidate.connectionId),
        'state': _state.phase.name,
      }),
    );
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
    _logger.info(
      'disconnect_completed',
      operation: 'device_connect',
      stage: 'connect',
      result: 'success',
      fields: _sessionFields('【会话清理】设备会话已断开，本地资源已清理', {
        'connection_attempt': connectionAttempt,
        'state': _state.phase.name,
      }),
    );
  }

  void _onNotification(Uint8List bytes) {
    final result = _codec.decode(bytes);
    if (!result.isSuccess) {
      _state = _state.copyWith(failure: result.failure);
      notifyListeners();
      _logger.info(
        'notification_decode_failure',
        operation: 'device_connect',
        stage: 'response',
        result: 'failed',
        fields: _sessionFields('【会话通知】收到无法解析的设备通知帧，完整原始字节请查看前置 BLE 接收日志', {
          'bytes': bytes.length,
          'failure_kind': result.failure?.kind.name ?? 'protocol',
        }),
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
      operation: 'device_connect',
      stage: 'response',
      result: 'success',
      fields: _sessionFields('【会话通知】已解析设备通知并更新会话状态快照', {
        'command': _hexCommand(frame.command),
        'bytes': bytes.length,
        'event_kind': event.kind.name,
      }),
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
      _logger.warning(
        'status_event_decode_failed',
        operation: 'device_connect',
        stage: 'response',
        result: 'failed',
        fields: {'error_type': error.runtimeType.toString()},
      );
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
      _logger.warning(
        'battery_event_decode_failed',
        operation: 'device_connect',
        stage: 'response',
        result: 'failed',
        fields: {'error_type': error.runtimeType.toString()},
      );
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
      _logger.warning(
        'storage_event_decode_failed',
        operation: 'device_connect',
        stage: 'response',
        result: 'failed',
        fields: {'error_type': error.runtimeType.toString()},
      );
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
        operation: 'device_connect',
        stage: 'response',
        result: 'failed',
        fields: {'error_type': error.runtimeType.toString()},
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
    // V1.6 assigns a fixed CCC mode to each response characteristic. FF13
    // streams file bytes through Notify; every other EVT response endpoint
    // uses Indicate. Do not infer the mode from a firmware that advertises
    // both properties, because the wrong CCC value suppresses its payload.
    final responseOperation = logicalEndpoint == BleLogicalEndpoint.ff10Ff13
        ? BleOperation.notify
        : BleOperation.indicate;
    final requestedMode = responseOperation.name;
    final expectedCommand = _evtResponseCommandByEndpoint[logicalEndpoint];
    if (!_state.supportsEndpoint(logicalEndpoint, responseOperation)) {
      if (critical) {
        throw StateError(
          '设备未提供 ${logicalEndpoint.name} 协议要求的 $requestedMode 能力。',
        );
      }
      _logger.info(
        'notification_subscription_skipped',
        operation: 'device_connect',
        stage: 'connect',
        result: 'cancelled',
        fields: _sessionFields('【会话订阅】设备未提供协议要求的可选响应能力，跳过订阅', {
          'endpoint': logicalEndpoint.name,
          'status': 'unsupported',
          'critical': critical,
          'mode': requestedMode,
        }),
      );
      return;
    }
    final endpoint = _profile.endpoint(logicalEndpoint);
    final key = '${endpoint.serviceUuid}|${endpoint.characteristicUuid}';
    final existingReadiness = _subscriptionReadiness[key];
    if (existingReadiness != null) {
      _logger.info(
        'notification_subscription_reuse_wait',
        operation: 'device_connect',
        stage: 'connect',
        result: 'pending',
        fields: _sessionFields('【会话订阅】相同特征正在配置，等待已有系统订阅结果', {
          'endpoint': logicalEndpoint.name,
          'command': _hexCommand(expectedCommand),
          'critical': critical,
          'mode': requestedMode,
        }),
      );
      await _awaitResponseSubscriptionReadiness(
        existingReadiness,
        logicalEndpoint: logicalEndpoint,
        critical: critical,
        connectionAttempt: connectionAttempt,
      );
      return;
    }
    if (_subscribedEndpointKeys.contains(key)) {
      _logger.info(
        'notification_subscription_already_active',
        operation: 'device_connect',
        stage: 'connect',
        result: 'success',
        fields: _sessionFields('【会话订阅】特征订阅已处于活动状态，无需重复配置', {
          'endpoint': logicalEndpoint.name,
          'command': _hexCommand(expectedCommand),
          'critical': critical,
          'mode': requestedMode,
        }),
      );
      return;
    }
    final subscriptionStartedAt = DateTime.now();
    _logger.info(
      'notification_subscription_requested',
      operation: 'device_connect',
      stage: 'connect',
      result: 'pending',
      fields: _sessionFields('【会话订阅】开始配置单个 EVT 响应特征的系统订阅', {
        'endpoint': logicalEndpoint.name,
        'command': _hexCommand(expectedCommand),
        'critical': critical,
        'mode': requestedMode,
        'supports_indicate': supportsIndication,
        'supports_notify': supportsNotification,
      }),
    );
    _subscribedEndpointKeys.add(key);
    // Native BLE values may split or coalesce EVT business frames. Keep one
    // assembler per characteristic so bytes from separate endpoints can
    // never be joined into a false frame.
    final frameAssembler = EvtFrameAssembler(
      maxLengthField: EvtProtocolContract.maxResponseLengthField,
    );
    _notificationFrameAssemblers[key.toUpperCase()] = frameAssembler;
    late final StreamSubscription<Uint8List> subscription;
    subscription = _transport
        .subscribe(_characteristic(session.candidate.connectionId, endpoint))
        .listen(
          (bytes) {
            if (!_isCurrentConnectionAttempt(connectionAttempt) ||
                responseController.isClosed) {
              return;
            }
            final assembled = frameAssembler.add(bytes);
            _logger.info(
              'notification_value_received',
              operation: 'device_connect',
              stage: 'response',
              result: 'pending',
              fields: _sessionFields('【会话接收】原生 BLE value 已进入 EVT 组帧器', {
                'endpoint': logicalEndpoint.name,
                'bytes': bytes.length,
                'count': assembled.frames.length,
                'length': assembled.bufferedByteCount,
                'discarded_bytes': assembled.discardedByteCount,
              }),
            );
            for (final rejected in assembled.rejectedFrames) {
              _logger.warning(
                'notification_frame_assembly_rejected',
                operation: 'device_connect',
                stage: 'response',
                result: 'failed',
                fields: _sessionFields('【会话接收】EVT 帧组装后 CRC 或长度校验失败，继续寻找下一帧', {
                  'endpoint': logicalEndpoint.name,
                  'bytes': rejected.length,
                  'reason': 'frame_assembly_rejected',
                }),
              );
            }
            for (final frameBytes in assembled.frames) {
              final decoded = _codec.decode(frameBytes);
              if (!decoded.isSuccess) {
                _logger.warning(
                  'notification_frame_decode_failed',
                  operation: 'device_connect',
                  stage: 'response',
                  result: 'failed',
                  fields: _sessionFields('【会话订阅】完整 EVT 通知帧无法解析，已丢弃并继续监听', {
                    'endpoint': logicalEndpoint.name,
                    'bytes': frameBytes.length,
                    'failure_kind': decoded.failure?.kind.name ?? 'protocol',
                  }),
                );
                continue;
              }
              final frame = decoded.value!;
              if (!_isExpectedResponseForEndpoint(logicalEndpoint, frame)) {
                _logger.info(
                  'notification_endpoint_mismatch',
                  fields: _sessionFields('【会话订阅】收到不属于当前特征的响应帧，已隔离不转发', {
                    'endpoint': logicalEndpoint.name,
                    'command': _hexCommand(frame.command),
                    'expected_command': _hexCommand(expectedCommand),
                    'content_length': frame.content.length,
                  }),
                );
                continue;
              }
              if (logicalEndpoint != BleLogicalEndpoint.ff10Ff13) {
                _logger.info(
                  'notification_frame_forwarded',
                  operation: 'device_connect',
                  stage: 'response',
                  fields: _sessionFields('【会话订阅】已转发匹配的 EVT 响应帧到命令队列', {
                    'endpoint': logicalEndpoint.name,
                    'command': _hexCommand(frame.command),
                    'content_length': frame.content.length,
                    'bytes': frameBytes.length,
                  }),
                );
              }
              responseController.add(frameBytes);
              if (logicalEndpoint == BleLogicalEndpoint.ff10Ff13) {
                // File payloads are consumed by the active 0x23 transfer only.
                // Retaining every chunk as a session event would duplicate audio
                // bytes, rebuild listeners per packet, and grow memory with the
                // full device file.
                continue;
              }
              _onNotification(frameBytes);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!_isCurrentConnectionAttempt(connectionAttempt)) {
              return;
            }
            _subscribedEndpointKeys.remove(key);
            _subscriptionReadiness.remove(key);
            _notificationFrameAssemblers.remove(key.toUpperCase());
            _notificationSubscriptions.remove(subscription);
            _logger.info(
              'notification_subscription_failed',
              operation: 'device_connect',
              stage: 'connect',
              result: 'failed',
              fields: _sessionFields('【会话订阅】系统通知流报错，关键特征将中断会话', {
                'endpoint': logicalEndpoint.name,
                'command': _hexCommand(expectedCommand),
                'critical': critical,
                'error_type': error.runtimeType.toString(),
                'elapsed_ms': DateTime.now()
                    .difference(subscriptionStartedAt)
                    .inMilliseconds,
              }),
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
            _notificationFrameAssemblers.remove(key.toUpperCase());
            _notificationSubscriptions.remove(subscription);
            _logger.info(
              'notification_subscription_closed',
              operation: 'device_connect',
              stage: 'connect',
              fields: _sessionFields('【会话订阅】系统通知流关闭，关键特征将中断会话', {
                'endpoint': logicalEndpoint.name,
                'command': _hexCommand(expectedCommand),
                'critical': critical,
                'elapsed_ms': DateTime.now()
                    .difference(subscriptionStartedAt)
                    .inMilliseconds,
              }),
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
      operation: 'device_connect',
      stage: 'connect',
      result: 'pending',
      fields: _sessionFields('【会话订阅】系统订阅请求已发出，等待原生 CCC 配置确认', {
        'endpoint': logicalEndpoint.name,
        'command': _hexCommand(expectedCommand),
        // This is the mode requested by Dart from the native BLE plugin.
        // It is not a raw CCCD readback, which platform APIs do not expose
        // consistently across Android and iOS.
        'mode': requestedMode,
        'critical': critical,
        'state': 'os_setup_pending',
      }),
    );
    await _awaitResponseSubscriptionReadiness(
      readiness,
      logicalEndpoint: logicalEndpoint,
      critical: critical,
      subscription: subscription,
      key: key,
      connectionAttempt: connectionAttempt,
      subscriptionStartedAt: subscriptionStartedAt,
    );
  }

  Future<void> _awaitResponseSubscriptionReadiness(
    Future<void> readiness, {
    required BleLogicalEndpoint logicalEndpoint,
    required bool critical,
    required int connectionAttempt,
    StreamSubscription<Uint8List>? subscription,
    String? key,
    DateTime? subscriptionStartedAt,
  }) async {
    try {
      await readiness;
      if (!_isCurrentConnectionAttempt(connectionAttempt)) {
        throw StateError('蓝牙连接已切换，通知订阅结果已失效。');
      }
      _logger.info(
        'notification_subscription_confirmed',
        operation: 'device_connect',
        stage: 'connect',
        result: 'success',
        elapsed: subscriptionStartedAt == null
            ? null
            : DateTime.now().difference(subscriptionStartedAt),
        fields: _sessionFields('【会话订阅】系统已确认 CCC 配置，特征可安全接收响应', {
          'endpoint': logicalEndpoint.name,
          'critical': critical,
          // The platform accepted notification setup. Do not label this as a
          // raw CCCD readback because iOS does not expose that value.
          'state': 'os_ack',
        }),
      );
    } catch (error, stackTrace) {
      if (!_isCurrentConnectionAttempt(connectionAttempt)) {
        Error.throwWithStackTrace(StateError('蓝牙连接已切换，通知订阅结果已失效。'), stackTrace);
      }
      if (key != null && identical(_subscriptionReadiness[key], readiness)) {
        _subscriptionReadiness.remove(key);
        _notificationFrameAssemblers.remove(key.toUpperCase());
        _subscribedEndpointKeys.remove(key);
      }
      if (subscription != null) {
        _notificationSubscriptions.remove(subscription);
        await subscription.cancel();
      }
      _logger.info(
        'notification_subscription_confirmation_failed',
        operation: 'device_connect',
        stage: 'connect',
        result: 'failed',
        elapsed: subscriptionStartedAt == null
            ? null
            : DateTime.now().difference(subscriptionStartedAt),
        fields: _sessionFields('【会话订阅】系统未确认 CCC 配置，关键特征将阻止后续命令', {
          'endpoint': logicalEndpoint.name,
          'critical': critical,
          'error_type': error.runtimeType.toString(),
        }),
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

  static String _hexCommand(int? command) => command == null
      ? '-'
      : '0x${command.toRadixString(16).padLeft(2, '0').toUpperCase()}';

  /// Establishes only the two V1.6 CCCs that are legal before authentication.
  /// FA11 carries the redacted identity response and FA19 carries the 0x09
  /// exchange. Opening any other business CCC here would expose a protected
  /// stream before the current connection has completed Action=00.
  Future<void> _subscribeEvtEndpointsBeforeAuthentication() async {
    for (final endpoint
        in EvtProtocolContract.preAuthenticationSubscriptionOrder) {
      await _ensureResponseSubscription(endpoint, critical: true);
    }
  }

  /// Enables the remaining protected EVT response channels after the current
  /// connection has completed Action=00. FF11/0x21 is a compatibility-only
  /// summary and is therefore best-effort; the required file path is FF12/13.
  Future<void> _subscribeEvtEndpointsAfterAuthentication() async {
    for (final endpoint
        in EvtProtocolContract.postAuthenticationSubscriptionOrder) {
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
            operation: 'device_connect',
            stage: 'response',
            result: 'failed',
            fields: {'error_type': error.runtimeType.toString()},
          );
          return null;
        }
        return DeviceSnapshot(
          state: switch (frame.content.first) {
            0 => DeviceState.standby,
            1 => DeviceState.recording,
            2 => DeviceState.paused,
            _ => DeviceState.unknown,
          },
          observedAt: DateTime.now(),
          source: source,
        );
      default:
        return null;
    }
  }

  DeviceSnapshot _snapshotFromDeviceInfo(
    DeviceInfo info, {
    String source = '认证后设备信息',
  }) => DeviceSnapshot(
    state: switch (info.recordStatus) {
      0 => DeviceState.standby,
      1 => DeviceState.recording,
      2 => DeviceState.paused,
      _ => DeviceState.unknown,
    },
    observedAt: DateTime.now(),
    source: source,
    batteryPercent: info.batteryLevel,
    isCharging: info.charging != 0,
  );

  List<String> _missingRequiredEndpointOperations(List<BleService> services) {
    return [
      for (final entry
          in DeviceProfile.evtV16RequiredEndpointOperations.entries)
        for (final operation in entry.value)
          if (!_hasEndpoint(services, _profile.endpoint(entry.key), operation))
            '${entry.key.name}.${operation.name}',
    ];
  }

  /// CoreBluetooth exposes one `setNotifyValue` API for both CCC modes. When
  /// an EVT characteristic declares both flags, iOS cannot be told to choose
  /// the V1.6-required mode. Reject that ambiguous peripheral before a command
  /// can be sent; Android keeps its explicit native mode selection. FF11 is
  /// optional, but it still needs the same guard when it is present.
  List<String> _iosCccModeConflicts(List<BleService> services) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return const [];
    }
    final endpointOperations = <BleLogicalEndpoint, Set<BleOperation>>{
      ...DeviceProfile.evtV16RequiredEndpointOperations,
      ...DeviceProfile.evtV16OptionalEndpointOperations,
    };
    return [
      for (final entry in endpointOperations.entries)
        if (_isIosCccAmbiguous(
          _discoveredCharacteristic(services, _profile.endpoint(entry.key)),
        ))
          '${entry.key.name}.notify+indicate',
    ];
  }

  static bool _isIosCccAmbiguous(BleDiscoveredCharacteristic? characteristic) {
    final operations = characteristic?.operations;
    return operations != null &&
        operations.contains(BleOperation.notify) &&
        operations.contains(BleOperation.indicate);
  }

  String _gattContractFailureDetail({
    required List<String> missingEndpointOperations,
    required List<String> iosCccModeConflicts,
  }) {
    final details = <String>[
      if (missingEndpointOperations.isNotEmpty)
        '缺少或不支持：${missingEndpointOperations.join('、')}。',
      if (iosCccModeConflicts.isNotEmpty)
        'iOS 上必需 EVT 特征不得同时声明 Notify 和 Indicate；FA19/FA11/FA12/FA15/FA16/FA17/FB11/FF12 必须仅使用 Indicate，FF13 必须仅使用 Notify。冲突能力：${iosCccModeConflicts.join('、')}。',
    ];
    return details.join('');
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
      operation: 'device_connect',
      stage: 'connect',
      result: 'success',
      fields: _sessionFields('【会话阶段】会话状态已按 EVT 流程切换', {
        'phase_from': previous.name,
        'phase_to': next.name,
      }),
    );
  }

  void _interrupt(Object error) {
    _logger.warning(
      'session_interrupted',
      operation: 'device_connect',
      result: 'failed',
      fields: _sessionFields('【会话清理】会话因连接或协议异常被中断', {
        'state': _state.phase.name,
        'error_type': error.runtimeType.toString(),
      }),
    );
    _fail(_failureFor(error, fallback: '连接或服务发现中断。'), interrupt: true);
  }

  void _fail(EvtFailure failure, {bool interrupt = false}) {
    _logger.info(
      'session_failure',
      operation: 'device_connect',
      result: 'failed',
      fields: _sessionFields('【会话清理】已记录会话失败状态，等待资源释放', {
        'failure_kind': failure.kind.name,
        'state': _state.phase.name,
        'critical': interrupt,
      }),
    );
    _state = _state.copyWith(
      phase: interrupt ? SessionPhase.interrupted : _state.phase,
      failure: failure,
    );
    notifyListeners();
  }

  /// Clears a GATT session when V1.6 cannot correlate a delayed response or
  /// an old continuous file stream with a future request.
  Future<void> _invalidateSessionForAmbiguousProtocolResult({
    required int connectionAttempt,
    required String event,
    required String message,
    required Map<String, Object?> fields,
  }) async {
    if (!_isCurrentConnectionAttempt(connectionAttempt)) {
      _logger.info(
        'stale_session_cleanup_ignored',
        operation: 'device_connect',
        stage: 'connect',
        result: 'cancelled',
        fields: _sessionFields('【会话清理】旧请求已失效，跳过清理，不修改或断开当前连接', {
          'connection_attempt': connectionAttempt,
          'event_kind': event,
        }),
      );
      return;
    }
    final deviceId = _state.session?.candidate.connectionId;
    _logger.info(
      event,
      operation: 'device_connect',
      stage: 'connect',
      result: 'failed',
      fields: _sessionFields('【会话清理】响应无法关联当前请求，主动关闭连接避免迟到数据', fields),
    );
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
    _logger.info(
      'transport_cleanup_started',
      operation: 'device_connect',
      stage: 'connect',
      result: 'pending',
      fields: _sessionFields('【会话清理】开始取消订阅、关闭命令队列并断开系统连接', {
        'device_suffix': _redactDeviceId(deviceId),
        'subscription_count': _notificationSubscriptions.length,
      }),
    );
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
    _preAuthenticationInfoReadInProgress = false;
    final connectionSubscription = _connectionSubscription;
    _connectionSubscription = null;
    await connectionSubscription?.cancel();
    if (!_ownsConnectionForCleanup(expectedConnectionAttempt)) {
      return;
    }
    await _transport.disconnect(deviceId);
    _logger.info(
      'transport_closed',
      operation: 'device_connect',
      stage: 'connect',
      result: 'success',
      fields: _sessionFields('【会话清理】底层连接已断开，当前会话资源已释放', {
        'device_suffix': _redactDeviceId(deviceId),
      }),
    );
  }

  Future<void> _cancelNotificationSubscriptions() async {
    _notificationFrameAssemblers.clear();
    if (_notificationSubscriptions.isEmpty) {
      _subscribedEndpointKeys.clear();
      _subscriptionReadiness.clear();
      return;
    }
    final subscriptions = List<StreamSubscription<Uint8List>>.of(
      _notificationSubscriptions,
    );
    _logger.info(
      'notification_subscriptions_cancelling',
      operation: 'device_connect',
      stage: 'connect',
      fields: _sessionFields('【会话清理】开始取消所有 EVT 特征订阅', {
        'subscription_count': subscriptions.length,
      }),
    );
    _notificationSubscriptions.clear();
    _subscribedEndpointKeys.clear();
    _subscriptionReadiness.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    _logger.info(
      'notification_subscriptions_cancelled',
      operation: 'device_connect',
      stage: 'connect',
      result: 'success',
      fields: _sessionFields('【会话清理】所有 EVT 特征订阅已取消', {
        'subscription_count': subscriptions.length,
      }),
    );
  }

  bool _isCurrentConnectionAttempt(int connectionAttempt) =>
      !_isDisposed && connectionAttempt == _connectionAttempt;

  void _requireCurrentConnectionAttempt(int connectionAttempt) {
    if (!_isCurrentConnectionAttempt(connectionAttempt)) {
      throw StateError('设备连接已变更，旧请求已取消。');
    }
  }

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

  /// Rechecks connection-scoped V1.6 authorization when a queued EVT command
  /// reaches the head of the BLE write queue. Initial UI checks alone are not
  /// enough because a disconnect or explicit revoke can occur while a command
  /// waits behind another request. The firmware's 60-second value is only the
  /// deadline to complete AUTH after connection establishment, not a local
  /// permission lease after AUTH succeeds.
  void _admitEvtCommandWrite(EvtCommandRequest request) {
    final endpoint = EvtProtocolContract.writeEndpointForCommand(
      request.command,
    );
    if (endpoint == null) {
      // 0x11 is in the business allow-list, but V1.6 exposes it as a native
      // GATT Read. It must never be sent through the framed write queue.
      throw StateError('EVT 0x11 仅支持 GATT Read，不允许通过业务写入发送。');
    }
    _requireEvtCommandCharacteristic(request, endpoint);
    EvtProtocolContract.validateWritePayload(request.command, request.content);
    if (request.allowUnauthenticatedUnbindRecovery &&
        (request.command != 0x09 ||
            request.content.length != 7 ||
            request.content.first !=
                EvtLegacySecurityAction.unbind.wireValue)) {
      throw StateError('EVT 未绑定恢复标记只能用于 0x09 Action=2。');
    }
    switch (request.command) {
      case 0x01:
        // V1.6 permits exactly one unauthenticated command: the connection
        // admission identity read. All later 0x01 reads require Action=00.
        if (!_preAuthenticationInfoReadInProgress) {
          _requireDevicePermission(DevicePermission.status);
        }
        return;
      case 0x02:
      case 0x07:
        _requireDevicePermission(DevicePermission.configuration);
        return;
      case 0x05:
        _requireDevicePermission(DevicePermission.status);
        return;
      case 0x06:
        if (request.content.isEmpty) {
          throw StateError('EVT 设备状态命令缺少 SubCmd。');
        }
        switch (request.content.first) {
          case 0x01:
            _requireDevicePermission(DevicePermission.status);
            return;
          case 0x02:
          case 0x03:
          case 0x04:
            _requireDevicePermission(DevicePermission.configuration);
            return;
          default:
            throw StateError('EVT 阶段不允许发送未声明的 0x06 SubCmd。');
        }
      case 0x21:
        _requireDevicePermission(DevicePermission.files);
        return;
      case 0x22:
      case 0x23:
        _requireDevicePermission(DevicePermission.files);
        return;
      case 0x09:
        // V1.6 code authentication must remain callable before authentication
        // has granted any scoped permissions. The V2 envelope is DVT-only,
        // so keep its marker and variable-length payload out of EVT even if
        // a future caller bypasses the repository boundary.
        if (request.content.length != 7 || request.content.first > 2) {
          throw StateError('EVT 阶段只允许 V1.6 认证码格式的 0x09 命令。');
        }
        // Action=02 is destructive UNBIND. A normal unbind request is only
        // valid on a connection that has already completed Action=00. V1.6
        // explicitly allows a previously submitted UNBIND to be resumed on a
        // fresh connection; the explicit request marker is the sole bypass
        // and it grants no DevicePermission.
        if (request.content.first == EvtLegacySecurityAction.unbind.wireValue) {
          if (!request.allowUnauthenticatedUnbindRecovery) {
            final gate = _permissionGate;
            final pendingUnbindAllowed =
                gate is DeviceUnbindPermissionGate && gate.allowsPendingUnbind;
            if (!pendingUnbindAllowed) {
              _requireDevicePermission(DevicePermission.status);
            }
          }
        }
        return;
      default:
        throw StateError(
          'EVT 阶段不允许发送未声明授权范围的设备命令 '
          '0x${request.command.toRadixString(16).padLeft(2, '0').toUpperCase()}。',
        );
    }
  }

  /// Verifies the final write target against the V1.6 command-to-characteristic
  /// map immediately before native BLE I/O. Public operation methods already
  /// check discovery capabilities, but this second check closes queued-command
  /// races and prevents a malformed caller from writing a valid frame to a
  /// different characteristic.
  void _requireEvtCommandCharacteristic(
    EvtCommandRequest request,
    BleLogicalEndpoint endpoint,
  ) {
    final configured = _profile.endpoints[endpoint];
    if (configured == null || configured.characteristicUuid.isEmpty) {
      throw StateError(
        'EVT 命令 0x${request.command.toRadixString(16).padLeft(2, '0').toUpperCase()} '
        '对应的 GATT 特征未配置：${endpoint.name}。',
      );
    }
    final actualService = normalizeBleUuid(
      request.writeCharacteristic.serviceUuid,
    );
    final actualCharacteristic = normalizeBleUuid(
      request.writeCharacteristic.characteristicUuid,
    );
    final expectedService = normalizeBleUuid(configured.serviceUuid);
    final expectedCharacteristic = normalizeBleUuid(
      configured.characteristicUuid,
    );
    final activeDeviceId = _state.session?.candidate.connectionId;
    if (activeDeviceId != null &&
        request.writeCharacteristic.deviceId != activeDeviceId) {
      throw StateError('EVT 命令写入目标设备与当前连接不一致。');
    }
    if (actualService.toUpperCase() != expectedService.toUpperCase() ||
        actualCharacteristic.toUpperCase() !=
            expectedCharacteristic.toUpperCase()) {
      throw StateError(
        'EVT 命令 0x${request.command.toRadixString(16).padLeft(2, '0').toUpperCase()} '
        '必须写入 ${endpoint.name}（${expectedCharacteristic.toUpperCase()}），'
        '实际为 ${actualCharacteristic.toUpperCase()}。',
      );
    }
    if (!_profile.canOperate(endpoint, BleOperation.write) ||
        !_state.supportsEndpoint(endpoint, BleOperation.write)) {
      throw StateError('当前连接未提供 ${endpoint.name} 的 GATT Write 能力。');
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

  Future<int> _ensureAuthenticatedDeviceInfoAttMtu() async {
    try {
      return await _ensureAttMtu(_v16AuthenticatedInfoMinimumAttMtu);
    } on BleTransportException {
      rethrow;
    } on StateError catch (error) {
      throw BleTransportException(
        EvtFailure.transport(
          message: '设备蓝牙 MTU 不足，无法读取设备信息。',
          detail:
              'V3 设备信息最大 Indicate 需要 ATT MTU >= '
              '$_v16AuthenticatedInfoMinimumAttMtu。$error',
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
      _logger.info(
        'att_mtu_cache_reused',
        operation: 'device_connect',
        stage: 'connect',
        result: 'success',
        fields: _sessionFields('【会话MTU】复用已协商的 ATT MTU', {
          'mtu': cached,
          'required_mtu': requiredMtu,
        }),
      );
      return cached;
    }
    final deviceId = _state.session?.candidate.connectionId;
    if (deviceId == null || !_state.hasActiveBleConnection) {
      throw StateError('设备尚未完成连接，无法协商 ATT MTU。');
    }
    final startedAt = DateTime.now();
    _logger.info(
      'att_mtu_negotiation_requested',
      operation: 'device_connect',
      stage: 'connect',
      result: 'pending',
      fields: _sessionFields('【会话MTU】请求系统协商 ATT MTU，设备信息和文件流将据此准入', {
        'device_suffix': _redactDeviceId(deviceId),
        'mtu': 517,
        'required_mtu': requiredMtu,
      }),
    );
    final mtu = await _transport.requestMtu(deviceId, preferredMtu: 517);
    if (mtu < 23) {
      throw StateError('设备协商的 ATT MTU 小于 23。');
    }
    _attMtu = mtu;
    _logger.info(
      'att_mtu_ready',
      operation: 'device_connect',
      stage: 'connect',
      result: 'success',
      elapsed: DateTime.now().difference(startedAt),
      fields: _sessionFields('【会话MTU】系统已返回 ATT MTU，开始校验是否满足本次请求', {
        'mtu': mtu,
        'required_mtu': requiredMtu,
      }),
    );
    if (mtu < requiredMtu) {
      throw StateError('当前 ATT MTU 为 $mtu，无法发送需要 $requiredMtu 的设备协议帧。');
    }
    return mtu;
  }

  static int _requiredFileTransferMtu({
    required int startOffset,
    required int chunkSize,
  }) {
    if (startOffset < 0 || startOffset > 0xFFFFFFFF) {
      throw RangeError.range(startOffset, 0, 0xFFFFFFFF);
    }
    if (chunkSize < 0 || chunkSize > 480) {
      throw RangeError.range(chunkSize, 0, 480);
    }
    // FF13 responses reserve 32 bytes for the outer frame and protocol
    // fields. MTU 32 cannot carry even the smallest data response; explicit
    // chunks additionally require MTU >= ChunkSize + 32.
    return max(33, chunkSize + 32);
  }

  /// Returns the maximum number of pure FileData bytes that can fit in one
  /// V1.6 0xA3 Notify frame for [attMtu]. The protocol reserves 32 bytes for
  /// the outer frame and file-offset/length fields, and caps the payload at
  /// 480 bytes even when the negotiated MTU is larger.
  static int _effectiveFileChunkLimit(int attMtu) =>
      min(480, max(0, attMtu - 32));

  @visibleForTesting
  static int effectiveFileChunkLimitForTesting(int attMtu) =>
      _effectiveFileChunkLimit(attMtu);

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
      _logger.info(
        'session_close_reused',
        operation: 'device_connect',
        stage: 'idle',
        result: 'pending',
        fields: _sessionFields('【会话清理】会话关闭已在进行，复用当前清理任务', {
          'state': _state.phase.name,
        }),
      );
      return pending;
    }
    _isDisposed = true;
    final deviceId = _state.session?.candidate.connectionId;
    _logger.info(
      'session_close_requested',
      operation: 'device_connect',
      stage: 'idle',
      result: 'pending',
      fields: _sessionFields('【会话清理】控制器关闭，开始释放会话持有的资源', {
        'state': _state.phase.name,
        'configured': deviceId != null,
      }),
    );
    final closing = _closeResources(deviceId);
    _closeFuture = closing;
    return closing;
  }

  Future<void> _closeResources(String? deviceId) async {
    if (deviceId != null) {
      await _closeTransport(deviceId);
      return;
    }
    _logger.info(
      'session_resources_cleanup_requested',
      operation: 'device_connect',
      stage: 'idle',
      result: 'pending',
      fields: _sessionFields('【会话清理】没有活动设备连接，释放本地订阅和命令资源', {
        'subscription_count': _notificationSubscriptions.length,
      }),
    );
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    await _cancelNotificationSubscriptions();
    await _commandClient?.close();
    _commandClient = null;
    await _responseController?.close();
    _responseController = null;
    _protocolRepository = null;
    _attMtu = null;
    _preAuthenticationInfoReadInProgress = false;
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
    final hexadecimal = deviceId.replaceAll(RegExp(r'[^A-Fa-f0-9]'), '');
    final suffix = hexadecimal.length < 4
        ? '0000'
        : hexadecimal.substring(hexadecimal.length - 4);
    return '...$suffix';
  }

  static Map<String, Object?> _sessionFields(
    String reason, [
    Map<String, Object?> fields = const <String, Object?>{},
  ]) => <String, Object?>{'reason': reason, ...fields};
}
