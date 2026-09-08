import 'dart:async';

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
  }) : _authenticationExpiryTimerFactory =
           authenticationExpiryTimer ?? Timer.new;

  final Duration authenticationWindow;
  final Timer Function(Duration delay, void Function() callback)
  _authenticationExpiryTimerFactory;
  DeviceAuthState _state = DeviceAuthState.unknown;
  Object? _error;
  Timer? _authenticationExpiryTimer;

  DeviceAuthState get state => _state;
  Object? get error => _error;
  bool get isAuthenticated => _state == DeviceAuthState.authenticated;

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
    if (_state == DeviceAuthState.authenticating) {
      throw const EvtLegacyAuthenticationException('认证操作正在进行。');
    }
    _cancelAuthenticationExpiryTimer();
    _state = DeviceAuthState.authenticating;
    _error = null;
    notifyListeners();
    try {
      final succeeded = await gateway.executeEvtLegacySecurity(
        EvtLegacySecurityRequest(action: action, securityCode: securityCode),
      );
      if (!succeeded) {
        throw const EvtLegacyAuthenticationException('设备拒绝认证码。');
      }
      if (completesAuthenticated) {
        _markAuthenticated();
      } else {
        _state = DeviceAuthState.unbound;
      }
      notifyListeners();
    } catch (error) {
      _cancelAuthenticationExpiryTimer();
      _state = DeviceAuthState.failed;
      _error = error;
      notifyListeners();
      rethrow;
    }
  }

  void revokeForConnectionLoss() {
    _cancelAuthenticationExpiryTimer();
    if (_state == DeviceAuthState.unbound) {
      return;
    }
    _state = DeviceAuthState.unbound;
    _error = null;
    notifyListeners();
  }

  void _markAuthenticated() {
    _state = DeviceAuthState.authenticated;
    if (authenticationWindow <= Duration.zero) {
      _expireAuthentication();
      return;
    }
    _authenticationExpiryTimer = _authenticationExpiryTimerFactory(
      authenticationWindow,
      _expireAuthentication,
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
  }

  void _cancelAuthenticationExpiryTimer() {
    _authenticationExpiryTimer?.cancel();
    _authenticationExpiryTimer = null;
  }

  @override
  void dispose() {
    _cancelAuthenticationExpiryTimer();
    super.dispose();
  }
}

class EvtLegacyAuthenticationException implements Exception {
  const EvtLegacyAuthenticationException(this.message);

  final String message;

  @override
  String toString() => message;
}
