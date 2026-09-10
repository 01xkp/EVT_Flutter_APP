import 'dart:async';

import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/features/device_session/domain/device_auth_state.dart';
import 'package:aipin/features/device_session/domain/device_permission.dart';
import 'package:aipin/features/device_session/domain/evt_legacy_security_gateway.dart';
import 'package:flutter/foundation.dart';

/// Owns the EVT-only V1 0x09 authentication state.
///
/// V1 grants the App the fixed EVT surface after a successful six-byte code
/// exchange. It has no external credential exchange or dynamic scope.
class EvtLegacyAuthController extends ChangeNotifier
    implements DevicePermissionGate {
  EvtLegacyAuthController({
    this.authenticationWindow = const Duration(seconds: 60),
    Timer Function(Duration delay, void Function() callback)?
    authenticationExpiryTimer,
    SafeAppLogger? logger,
  }) : _authenticationExpiryTimerFactory =
           authenticationExpiryTimer ?? Timer.new,
       _logger = logger ?? const DebugSafeAppLogger(scope: 'AUTH');

  final Duration authenticationWindow;
  final Timer Function(Duration delay, void Function() callback)
  _authenticationExpiryTimerFactory;
  final SafeAppLogger _logger;
  DeviceAuthState _state = DeviceAuthState.unknown;
  Object? _error;
  Timer? _authenticationExpiryTimer;
  EvtLegacySecurityAction? _activeAction;
  int _operation = 0;
  bool _isDisposed = false;

  DeviceAuthState get state => _state;
  Object? get error => _error;
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

  Future<void> reset(
    EvtLegacySecurityGateway gateway, {
    required String securityCode,
  }) => _execute(
    gateway,
    action: EvtLegacySecurityAction.reset,
    securityCode: securityCode,
    completesAuthenticated: false,
  );

  Future<void> _execute(
    EvtLegacySecurityGateway gateway, {
    required EvtLegacySecurityAction action,
    required String securityCode,
    required bool completesAuthenticated,
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
    final operation = ++_operation;
    _logInfo(
      'legacy_authentication_requested',
      action: action,
      result: 'pending',
      fields: {
        'attempt': operation,
        'length': securityCode.length,
        'state': _state.name,
      },
    );
    _cancelAuthenticationExpiryTimer();
    _activeAction = action;
    _state = DeviceAuthState.authenticating;
    _error = null;
    notifyListeners();
    _logInfo(
      'legacy_authentication_started',
      action: action,
      result: 'pending',
      fields: {'state': _state.name},
    );
    try {
      _requireCurrentOperation(operation);
      _logInfo(
        'legacy_authentication_protocol_dispatch',
        action: action,
        result: 'pending',
      );
      final succeeded = await gateway.executeEvtLegacySecurity(
        EvtLegacySecurityRequest(action: action, securityCode: securityCode),
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
      if (completesAuthenticated) {
        _markAuthenticated(action, operation);
      } else {
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
      _cancelAuthenticationExpiryTimer();
      _state = DeviceAuthState.failed;
      _error = error;
      notifyListeners();
      _logWarning(
        'legacy_authentication_failed',
        action: action,
        result: 'failed',
        fields: {
          'error_type': error.runtimeType.toString(),
          'state': _state.name,
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
    _cancelAuthenticationExpiryTimer();
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
    if (authenticationWindow <= Duration.zero) {
      _expireAuthentication();
      return;
    }
    _authenticationExpiryTimer = _authenticationExpiryTimerFactory(
      authenticationWindow,
      () {
        if (_isCurrentOperation(operation)) {
          _expireAuthentication();
        }
      },
    );
    _logInfo(
      'legacy_authentication_window_started',
      action: action,
      result: 'success',
      fields: {
        'state': _state.name,
        'duration_ms': authenticationWindow.inMilliseconds,
      },
    );
  }

  void _expireAuthentication() {
    _authenticationExpiryTimer = null;
    if (_state != DeviceAuthState.authenticated) {
      return;
    }
    _state = DeviceAuthState.unbound;
    _error = null;
    notifyListeners();
    _logWarning(
      'legacy_authentication_expired',
      action: _activeAction,
      result: 'cancelled',
      fields: {'state': _state.name},
    );
    _activeAction = null;
  }

  void _cancelAuthenticationExpiryTimer() {
    final activeTimer = _authenticationExpiryTimer;
    activeTimer?.cancel();
    _authenticationExpiryTimer = null;
    if (activeTimer != null) {
      _logInfo(
        'legacy_authentication_window_cancelled',
        action: _activeAction,
        result: 'cancelled',
        fields: {'state': _state.name},
      );
    }
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
    final operation = action == EvtLegacySecurityAction.bind
        ? 'device_bind'
        : 'device_authenticate';
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
    _cancelAuthenticationExpiryTimer();
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
