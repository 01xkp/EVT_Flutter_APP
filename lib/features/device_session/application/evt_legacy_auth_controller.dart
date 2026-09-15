import 'dart:async';

import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/features/device_session/domain/device_auth_state.dart';
import 'package:aipin/features/device_session/domain/device_permission.dart';
import 'package:aipin/features/device_session/domain/evt_legacy_security_gateway.dart';
import 'package:flutter/foundation.dart';

/// Owns the EVT-only V1.6 0x09 authentication state.
///
/// V1.6 uses the fixed six-byte security-code envelope and grants the App the
/// fixed EVT surface after a successful code exchange. The `Legacy` portion
/// of this source name is retained only for compatibility with the earlier
/// EVT prototype; this controller does not execute the retired V1.5/V2 flow.
class EvtLegacyAuthController extends ChangeNotifier
    implements DevicePermissionGate {
  EvtLegacyAuthController({
    // Kept as source-compatible constructor parameters for integrations that
    // still supplied the old local permission-TTL settings. V1.6 defines the
    // 60-second value as the firmware's *pre-authentication deadline* from
    // connection establishment; it is not a post-authentication lease. The
    // App therefore does not start a timer after a successful AUTH.
    @Deprecated('V1.6 AUTH remains valid until BLE disconnect or restart')
    this.authenticationWindow = const Duration(seconds: 60),
    @Deprecated('V1.6 AUTH remains valid until BLE disconnect or restart')
    Timer Function(Duration delay, void Function() callback)?
    authenticationExpiryTimer,
    bool unbindRecoveryPending = false,
    SafeAppLogger? logger,
  }) : _logger = logger ?? const DebugSafeAppLogger(scope: 'AUTH'),
       _unbindRecoveryPending = unbindRecoveryPending,
       _state = unbindRecoveryPending
           ? DeviceAuthState.unbindPending
           : DeviceAuthState.unknown;

  /// Firmware's connection-time AUTH deadline, retained for API compatibility.
  /// It must not be used as a local post-authentication expiry.
  final Duration authenticationWindow;
  final SafeAppLogger _logger;
  DeviceAuthState _state;
  Object? _error;
  EvtLegacySecurityAction? _activeAction;
  bool _unbindRecoveryPending;
  int _operation = 0;
  bool _isDisposed = false;

  DeviceAuthState get state => _state;
  Object? get error => _error;

  /// The V1.6 0x09 action currently awaiting a terminal device result.
  ///
  /// This is intentionally exposed only as transient UI state. It never
  /// contains the security code, and lets the binding screen distinguish the
  /// firmware's physical-button confirmation window from an AUTH exchange.
  EvtLegacySecurityAction? get activeAction =>
      _state == DeviceAuthState.authenticating ? _activeAction : null;

  /// Whether a dispatched Action=2 still needs an explicit recovery attempt.
  ///
  /// This marker contains no credential. The caller must obtain the current
  /// six-byte code again through the approved channel after reconnecting.
  bool get hasUnbindRecoveryPending => _unbindRecoveryPending;
  bool get isAuthenticated =>
      !_isDisposed && _state == DeviceAuthState.authenticated;

  @override
  bool allows(DevicePermission permission) {
    if (!isAuthenticated) {
      return false;
    }
    return true;
  }

  Set<DevicePermission> get grantedPermissions => isAuthenticated
      ? <DevicePermission>{
          DevicePermission.status,
          DevicePermission.configuration,
          DevicePermission.files,
        }
      : const <DevicePermission>{};

  Future<void> authenticate(
    EvtLegacySecurityGateway gateway, {
    required String securityCode,
  }) => _execute(
    gateway,
    action: EvtLegacySecurityAction.authenticate,
    securityCode: securityCode,
    completesAuthenticated: true,
  );

  Future<void> bind(
    EvtLegacySecurityGateway gateway, {
    required String securityCode,
  }) => _execute(
    gateway,
    action: EvtLegacySecurityAction.bind,
    securityCode: securityCode,
    completesAuthenticated: true,
  );

  Future<void> unbind(
    EvtLegacySecurityGateway gateway, {
    required String securityCode,
  }) => _execute(
    gateway,
    action: EvtLegacySecurityAction.unbind,
    securityCode: securityCode,
    completesAuthenticated: false,
  );

  /// Retries a previously submitted V1.6 Action=2 after a disconnect or
  /// response timeout. The session admission gate allows this one explicit
  /// exchange before Action=00, but successful recovery deliberately leaves
  /// all ordinary permissions denied.
  Future<void> unbindRecovery(
    EvtLegacySecurityGateway gateway, {
    required String securityCode,
  }) {
    if (!_unbindRecoveryPending) {
      throw const EvtLegacyAuthenticationException('当前没有待恢复的解绑操作。');
    }
    return _execute(
      gateway,
      action: EvtLegacySecurityAction.unbind,
      securityCode: securityCode,
      completesAuthenticated: false,
      recovery: true,
    );
  }

  /// Alias used by reconnect flows that call this operation a retry.
  Future<void> recoverUnbind(
    EvtLegacySecurityGateway gateway, {
    required String securityCode,
  }) => unbindRecovery(gateway, securityCode: securityCode);

  /// Marks the local recovery intent when the app learns that a prior
  /// Action=2 was submitted before this controller was recreated. No secret
  /// value is accepted or stored.
  void markUnbindRecoveryPending() {
    if (_isDisposed || _unbindRecoveryPending) {
      return;
    }
    _unbindRecoveryPending = true;
    _error = null;
    _state = DeviceAuthState.unbindPending;
    notifyListeners();
    _logInfo(
      'legacy_unbind_recovery_marked_pending',
      action: EvtLegacySecurityAction.unbind,
      result: 'pending',
      fields: const {'reason': 'caller_restored_pending_unbind_intent'},
    );
  }

  /// Clears a pending marker when the recovery workflow is conclusively ended
  /// without granting this connection ordinary permissions.
  void clearUnbindRecoveryPending() {
    if (_isDisposed || !_unbindRecoveryPending) {
      return;
    }
    _unbindRecoveryPending = false;
    if (_state == DeviceAuthState.unbindPending) {
      _state = DeviceAuthState.unbound;
      _error = null;
      notifyListeners();
    }
    _logInfo(
      'legacy_unbind_recovery_cleared',
      action: EvtLegacySecurityAction.unbind,
      result: 'cancelled',
    );
  }

  /// @deprecated V1.6 calls action 0x02 "unbind". Keep this forwarding
  /// method for integrations compiled against the earlier EVT prototype.
  @Deprecated('Use unbind()')
  Future<void> reset(
    EvtLegacySecurityGateway gateway, {
    required String securityCode,
  }) => unbind(gateway, securityCode: securityCode);

  Future<void> _execute(
    EvtLegacySecurityGateway gateway, {
    required EvtLegacySecurityAction action,
    required String securityCode,
    required bool completesAuthenticated,
    bool recovery = false,
  }) async {
    if (_isDisposed) {
      throw StateError('设备认证控制器已关闭。');
    }
    if (_state == DeviceAuthState.authenticating) {
      _logWarning(
        'legacy_authentication_rejected_busy',
        action: action,
        result: 'failed',
      );
      throw const EvtLegacyAuthenticationException('认证操作正在进行。');
    }
    if (_unbindRecoveryPending && !recovery) {
      _logWarning(
        'legacy_authentication_rejected_unbind_pending',
        action: action,
        result: 'failed',
        fields: const {'reason': 'V1.6 UNBIND_PENDING 仅允许 Action=2 recovery'},
      );
      throw const EvtLegacyAuthenticationException('设备仍有待恢复的解绑操作，请先完成解绑恢复。');
    }
    if (recovery && action != EvtLegacySecurityAction.unbind) {
      throw const EvtLegacyAuthenticationException('只有 Action=2 支持解绑恢复。');
    }
    if (recovery && !_unbindRecoveryPending) {
      throw const EvtLegacyAuthenticationException('当前没有待恢复的解绑操作。');
    }
    final operation = ++_operation;
    _logInfo(
      'legacy_authentication_requested',
      action: action,
      result: 'pending',
      fields: {
        'attempt': operation,
        'length': securityCode.length,
        'state': _state.name,
        'recovery': recovery,
      },
    );
    _activeAction = action;
    _state = DeviceAuthState.authenticating;
    _error = null;
    notifyListeners();
    _logInfo(
      'legacy_authentication_started',
      action: action,
      result: 'pending',
      fields: {'state': _state.name, 'recovery': recovery},
    );
    var gatewayDispatched = false;
    try {
      _requireCurrentOperation(operation);
      _logInfo(
        'legacy_authentication_protocol_dispatch',
        action: action,
        result: 'pending',
        fields: {'recovery': recovery},
      );
      gatewayDispatched = true;
      if (action == EvtLegacySecurityAction.unbind) {
        // From this point the device may already have committed UNBINDING;
        // a disconnect cannot safely be interpreted as a rollback.
        _unbindRecoveryPending = true;
      }
      var succeeded = await gateway.executeEvtLegacySecurity(
        EvtLegacySecurityRequest(
          action: action,
          securityCode: securityCode,
          recovery: recovery,
        ),
      );
      _requireCurrentOperation(operation);
      if (!succeeded) {
        _logWarning(
          'legacy_authentication_device_rejected',
          action: action,
          result: 'failed',
        );
        throw const EvtLegacyAuthenticationException('设备拒绝认证码。');
      }
      // V1.6 deliberately separates BIND from connection authentication:
      // Action=1 only persists the candidate code after the device-side
      // button confirmation. It does not set ConnectionAuthState. The App
      // must immediately submit Action=0 on the same BLE connection before
      // any protected synchronization command is allowed.
      if (action == EvtLegacySecurityAction.bind) {
        _logInfo(
          'legacy_authentication_bind_followup_requested',
          action: action,
          result: 'pending',
          fields: const {
            'follow_up_action': 'authenticate',
            'reason': 'V1.6 BIND success requires same-connection AUTH',
          },
        );
        _activeAction = EvtLegacySecurityAction.authenticate;
        notifyListeners();
        succeeded = await gateway.executeEvtLegacySecurity(
          EvtLegacySecurityRequest(
            action: EvtLegacySecurityAction.authenticate,
            securityCode: securityCode,
          ),
        );
        _requireCurrentOperation(operation);
        _logInfo(
          'legacy_authentication_bind_followup_result',
          action: action,
          result: succeeded ? 'success' : 'failed',
          fields: const {'follow_up_action': 'authenticate'},
        );
        if (!succeeded) {
          throw const EvtLegacyAuthenticationException('绑定已提交，但设备连接认证失败。');
        }
      }
      if (completesAuthenticated) {
        _unbindRecoveryPending = false;
        _markAuthenticated(action, operation);
      } else {
        _unbindRecoveryPending = false;
        _state = DeviceAuthState.unbound;
      }
      notifyListeners();
      _logInfo(
        'legacy_authentication_completed',
        action: action,
        result: 'success',
        fields: {'state': _state.name},
      );
    } catch (error) {
      if (!_isCurrentOperation(operation)) {
        _logInfo(
          'legacy_authentication_stale_result_ignored',
          action: action,
          result: 'cancelled',
          fields: {
            'reason': '【认证回调】请求已因断连、重新认证或释放失效，忽略旧结果，不修改当前认证状态',
            'attempt': operation,
            'current_operation': _operation,
            'error_type': error.runtimeType.toString(),
          },
        );
        rethrow;
      }
      if (action == EvtLegacySecurityAction.unbind && gatewayDispatched) {
        // V1.6 explicitly says a failed/timeout Action=2 cannot be treated as
        // a rollback. Keep only the intent, never the code, so a reconnect can
        // issue the documented recovery request.
        _unbindRecoveryPending = true;
        _state = DeviceAuthState.unbindPending;
      } else {
        _state = DeviceAuthState.failed;
      }
      _error = error;
      notifyListeners();
      _logWarning(
        'legacy_authentication_failed',
        action: action,
        result: 'failed',
        fields: {
          'error_type': error.runtimeType.toString(),
          'state': _state.name,
          'recovery': recovery,
          'unbind_recovery_pending': _unbindRecoveryPending,
        },
      );
      rethrow;
    }
  }

  bool _isCurrentOperation(int operation) =>
      !_isDisposed && operation == _operation;

  void _requireCurrentOperation(int operation) {
    if (!_isCurrentOperation(operation)) {
      // Do not report a stale success to the caller and start post-auth sync.
      throw StateError('设备认证请求已失效，请在当前连接重新认证。');
    }
  }

  void revokeForConnectionLoss() {
    if (_isDisposed) {
      return;
    }
    _operation++;
    if (_unbindRecoveryPending || _state == DeviceAuthState.unbindPending) {
      _state = DeviceAuthState.unbindPending;
      _error = null;
      notifyListeners();
      _logInfo(
        'legacy_unbind_recovery_preserved_connection_loss',
        action: EvtLegacySecurityAction.unbind,
        result: 'pending',
        fields: const {
          'reason': '连接断开不能证明设备已回滚，保留 Action=2 恢复意图',
          'permissions_granted': false,
        },
      );
      _activeAction = null;
      return;
    }
    if (_state == DeviceAuthState.unbound) {
      return;
    }
    _state = DeviceAuthState.unbound;
    _error = null;
    notifyListeners();
    _logInfo(
      'legacy_authentication_revoked_connection_loss',
      action: _activeAction,
      result: 'cancelled',
      fields: {'state': _state.name},
    );
    _activeAction = null;
  }

  void _markAuthenticated(EvtLegacySecurityAction action, int operation) {
    _state = DeviceAuthState.authenticated;
    _logInfo(
      'legacy_authentication_connection_scope_started',
      action: action,
      result: 'success',
      fields: {
        'state': _state.name,
        'scope': 'until_ble_disconnect_or_restart',
        'firmware_auth_deadline_ms': authenticationWindow.inMilliseconds,
        'local_expiry_timer': false,
      },
    );
  }

  void _logInfo(
    String event, {
    EvtLegacySecurityAction? action,
    String? result,
    Map<String, Object?> fields = const {},
  }) {
    _log(
      event,
      level: _AuthLogLevel.info,
      action: action,
      result: result,
      fields: fields,
    );
  }

  void _logWarning(
    String event, {
    EvtLegacySecurityAction? action,
    String? result,
    Map<String, Object?> fields = const {},
  }) {
    _log(
      event,
      level: _AuthLogLevel.warning,
      action: action,
      result: result,
      fields: fields,
    );
  }

  void _log(
    String event, {
    required _AuthLogLevel level,
    EvtLegacySecurityAction? action,
    String? result,
    required Map<String, Object?> fields,
  }) {
    final actionFields = <String, Object?>{
      if (action != null) 'action': action.name,
      ...fields,
    };
    final operation = switch (action) {
      EvtLegacySecurityAction.bind => 'device_bind',
      EvtLegacySecurityAction.unbind => 'device_unbind',
      EvtLegacySecurityAction.authenticate => 'device_authenticate',
      null => 'device_authenticate',
    };
    try {
      switch (level) {
        case _AuthLogLevel.info:
          _logger.info(
            event,
            operation: operation,
            stage: 'challenge',
            result: result,
            fields: actionFields,
          );
        case _AuthLogLevel.warning:
          _logger.warning(
            event,
            operation: operation,
            stage: 'challenge',
            result: result,
            fields: actionFields,
          );
      }
    } catch (_) {
      // Diagnostics must never interrupt an authentication exchange.
    }
  }

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _operation++;
    super.dispose();
  }
}

enum _AuthLogLevel { info, warning }

class EvtLegacyAuthenticationException implements Exception {
  const EvtLegacyAuthenticationException(this.message);

  final String message;

  @override
  String toString() => message;
}
