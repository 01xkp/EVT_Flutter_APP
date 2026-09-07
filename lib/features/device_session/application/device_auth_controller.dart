import 'dart:async';
import 'dart:math';

import 'package:aipin/features/device_session/domain/device_clear.dart';
import 'package:aipin/features/device_session/domain/device_clear_checkpoint.dart';
import 'package:aipin/features/device_session/domain/device_auth_protocol.dart';
import 'package:aipin/features/device_session/domain/device_auth_state.dart';
import 'package:aipin/features/device_session/domain/device_security_gateway.dart';
import 'package:aipin/features/device_session/domain/ticket_gateway.dart';
import 'package:flutter/foundation.dart';

class DeviceAuthController extends ChangeNotifier {
  DeviceAuthController({
    required this._ticketGateway,
    int Function()? transactionIdSource,
    List<int> Function()? nonceSource,
    this._onClearCompleted,
    Future<void> Function(Duration delay)? waitForPoll,
    this._clearCheckpoints,
    Timer Function(Duration delay, void Function() callback)? grantExpiryTimer,
  }) : _transactionIdSource = transactionIdSource ?? _secureTransactionId,
       _nonceSource = nonceSource ?? _secureNonce,
       _waitForPoll = waitForPoll ?? Future<void>.delayed,
       _grantExpiryTimerFactory = grantExpiryTimer ?? Timer.new;

  final TicketGateway _ticketGateway;
  final int Function() _transactionIdSource;
  final List<int> Function() _nonceSource;
  final Future<void> Function(String deviceId)? _onClearCompleted;
  final Future<void> Function(Duration delay) _waitForPoll;
  final DeviceClearCheckpointRepository? _clearCheckpoints;
  final Timer Function(Duration delay, void Function() callback)
  _grantExpiryTimerFactory;
  DeviceAuthState _state = DeviceAuthState.unknown;
  DeviceAuthGrant? _grant;
  Timer? _grantExpiryTimer;
  _PendingClear? _pendingClear;
  Object? _error;

  DeviceAuthState get state => _state;
  DeviceAuthGrant? get grant => _grant;
  Object? get error => _error;
  bool get isAuthenticated => _state == DeviceAuthState.authenticated;
  DeviceClearPreparation? get pendingClear => _pendingClear?.preparation;

  bool allows(DevicePermission permission) =>
      _grant?.allows(permission) ?? false;

  /// A BLE connection loss invalidates a session-scoped firmware grant.
  void revokeForConnectionLoss() {
    _cancelGrantExpiryTimer();
    _grant = null;
    if (_state != DeviceAuthState.clearing) {
      _pendingClear = null;
      _error = null;
      _state = DeviceAuthState.unbound;
    }
    notifyListeners();
  }

  Future<bool> restorePendingClear(String deviceId) async {
    if (_state != DeviceAuthState.unknown &&
        _state != DeviceAuthState.unbound) {
      return false;
    }
    final checkpoint = await _clearCheckpoints?.find(deviceId);
    if (checkpoint == null) {
      return false;
    }
    _cancelGrantExpiryTimer();
    _grant = null;
    _pendingClear = _PendingClear(
      deviceId: checkpoint.deviceId,
      transactionId: checkpoint.transactionId,
      expectedBindingGeneration: checkpoint.expectedBindingGeneration,
      preparation: DeviceClearPreparation(
        pendingFiles: 0,
        confirmNonce: checkpoint.confirmNonce,
        pendingBytes: 0,
        effectiveClearScope: checkpoint.clearScope,
        riskFlags: 0,
        prepareTtlSeconds: 0,
      ),
    );
    _error = null;
    _state = DeviceAuthState.clearing;
    notifyListeners();
    return true;
  }

  Future<void> bind(DeviceSecurityGateway channel, {required String deviceId}) {
    return _runHandshake(
      channel,
      deviceId: deviceId,
      beginAction: DeviceAuthAction.bindRequest,
      confirmAction: DeviceAuthAction.bindConfirm,
    );
  }

  Future<void> authenticate(
    DeviceSecurityGateway channel, {
    required String deviceId,
  }) {
    return _runHandshake(
      channel,
      deviceId: deviceId,
      beginAction: DeviceAuthAction.authenticate,
      confirmAction: DeviceAuthAction.authenticationResult,
    );
  }

  Future<void> _runHandshake(
    DeviceSecurityGateway channel, {
    required String deviceId,
    required DeviceAuthAction beginAction,
    required DeviceAuthAction confirmAction,
  }) async {
    if (_state == DeviceAuthState.authenticating) {
      throw StateError('认证正在进行。');
    }
    final transactionId = _transactionIdSource();
    final appNonce = _nonceSource();
    _state = DeviceAuthState.authenticating;
    _error = null;
    notifyListeners();
    try {
      final material = await _ticketGateway.issue(
        TicketRequest(
          deviceId: deviceId,
          action: beginAction,
          transactionId: transactionId,
        ),
      );
      final begin = await channel.execute(
        DeviceSecurityRequest(
          action: beginAction,
          transactionId: transactionId,
          data: DeviceAuthProtocol.beginData(
            appNonce: appNonce,
            ticket: material.ticket,
          ),
        ),
      );
      _ensureSucceeded(begin, beginAction);
      final challenge = DeviceAuthProtocol.parseBeginChallenge(begin.data);
      if (!DeviceAuthProtocol.verifyDeviceProof(
        action: beginAction,
        transactionId: transactionId,
        material: material,
        appNonce: appNonce,
        deviceNonce: challenge.deviceNonce,
        deviceProof: challenge.deviceProof,
      )) {
        throw const DeviceAuthenticationException('设备证明校验失败。');
      }
      final appProof = DeviceAuthProtocol.createAppProof(
        beginAction: beginAction,
        confirmAction: confirmAction,
        transactionId: transactionId,
        material: material,
        appNonce: appNonce,
        deviceNonce: challenge.deviceNonce,
        deviceProof: challenge.deviceProof,
      );
      final confirm = await channel.execute(
        DeviceSecurityRequest(
          action: confirmAction,
          transactionId: transactionId,
          data: DeviceAuthProtocol.confirmData(appProof),
        ),
      );
      _ensureSucceeded(confirm, confirmAction);
      _acceptGrant(DeviceAuthGrant.fromConfirmation(confirm.data));
      notifyListeners();
    } catch (error) {
      _cancelGrantExpiryTimer();
      _grant = null;
      _state = DeviceAuthState.failed;
      _error = error;
      notifyListeners();
      rethrow;
    }
  }

  Future<DeviceClearPreparation> prepareClear(
    DeviceSecurityGateway channel, {
    required String deviceId,
  }) async {
    final grant = _grant;
    if (_state != DeviceAuthState.authenticated || grant == null) {
      throw const DeviceAuthenticationException('请先完成设备认证。');
    }
    if (!grant.allows(DevicePermission.clear)) {
      throw const DeviceAuthenticationException('当前认证未授予设备清除权限。');
    }
    _state = DeviceAuthState.clearPreparing;
    _error = null;
    notifyListeners();
    final transactionId = _transactionIdSource();
    try {
      final response = await channel.execute(
        DeviceSecurityRequest(
          action: DeviceAuthAction.clearRequest,
          transactionId: transactionId,
          data: DeviceAuthProtocol.clearRequestData(
            expectedBindingGeneration: grant.bindingGeneration,
            requestedClearScope: fullUserClearScope,
          ),
        ),
      );
      _ensureSucceeded(response, DeviceAuthAction.clearRequest);
      final preparation = DeviceClearPreparation.fromResponse(response.data);
      if ((preparation.effectiveClearScope & fullUserClearScope) !=
          fullUserClearScope) {
        throw const DeviceAuthenticationException('设备拒绝完整用户数据清除范围。');
      }
      _pendingClear = _PendingClear(
        deviceId: deviceId,
        transactionId: transactionId,
        expectedBindingGeneration: grant.bindingGeneration,
        preparation: preparation,
      );
      _state = DeviceAuthState.clearConfirmationRequired;
      notifyListeners();
      return preparation;
    } catch (error) {
      _state = DeviceAuthState.authenticated;
      _error = error;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> confirmClear(
    DeviceSecurityGateway channel, {
    required String deviceId,
  }) async {
    final pending = _pendingClear;
    if (_state != DeviceAuthState.clearConfirmationRequired ||
        pending == null) {
      throw const DeviceAuthenticationException('请先完成设备清除预检查并确认风险。');
    }
    if (pending.deviceId != deviceId) {
      throw const DeviceAuthenticationException('设备清除事务与当前设备不一致。');
    }
    _state = DeviceAuthState.clearing;
    _error = null;
    notifyListeners();
    try {
      final material = await _ticketGateway.issue(
        TicketRequest(
          deviceId: deviceId,
          action: DeviceAuthAction.clearConfirm,
          transactionId: pending.transactionId,
          devicePayload: <int>[
            ...pending.preparation.confirmNonce,
            ..._u32Le(pending.expectedBindingGeneration),
            ..._u32Le(pending.preparation.effectiveClearScope),
          ],
        ),
      );
      final proof = DeviceAuthProtocol.createClearConfirmProof(
        transactionId: pending.transactionId,
        material: material,
        expectedBindingGeneration: pending.expectedBindingGeneration,
        confirmNonce: pending.preparation.confirmNonce,
        clearScope: pending.preparation.effectiveClearScope,
      );
      final confirm = await channel.execute(
        DeviceSecurityRequest(
          action: DeviceAuthAction.clearConfirm,
          transactionId: pending.transactionId,
          data: DeviceAuthProtocol.clearConfirmData(
            confirmNonce: pending.preparation.confirmNonce,
            clearScope: pending.preparation.effectiveClearScope,
            ticket: material.ticket,
            confirmProof: proof,
          ),
        ),
      );
      _ensureSucceeded(confirm, DeviceAuthAction.clearConfirm);
      if (confirm.data.length != 3 || confirm.data[0] != 2) {
        throw const DeviceAuthenticationException('设备未进入数据清除状态。');
      }
      await _saveClearCheckpoint(pending);
      await _pollClearStatus(
        channel,
        pending: pending,
        initialDelay: Duration(milliseconds: _u16Le(confirm.data, 1)),
      );
    } catch (error) {
      _error = error;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> resumeClearStatus(DeviceSecurityGateway channel) async {
    final pending = _pendingClear;
    if (_state != DeviceAuthState.clearing || pending == null) {
      throw const DeviceAuthenticationException('当前没有正在进行的设备清除。');
    }
    _error = null;
    notifyListeners();
    try {
      await _pollClearStatus(
        channel,
        pending: pending,
        initialDelay: Duration.zero,
      );
    } catch (error) {
      _error = error;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _pollClearStatus(
    DeviceSecurityGateway channel, {
    required _PendingClear pending,
    required Duration initialDelay,
  }) async {
    var delay = initialDelay;
    for (var attempt = 0; attempt < 120; attempt += 1) {
      if (delay > Duration.zero) {
        await _waitForPoll(delay);
      }
      final response = await channel.execute(
        DeviceSecurityRequest(
          action: DeviceAuthAction.clearStatus,
          transactionId: pending.transactionId,
          data: DeviceAuthProtocol.clearStatusData(
            pending.preparation.confirmNonce,
          ),
        ),
      );
      _ensureSucceeded(response, DeviceAuthAction.clearStatus);
      final status = DeviceClearStatus.fromResponse(response.data);
      if (status.state == DeviceClearProgressState.failed) {
        await _discardClearCheckpoint(pending.deviceId);
        _cancelGrantExpiryTimer();
        _grant = null;
        _pendingClear = null;
        _state = DeviceAuthState.failed;
        notifyListeners();
        throw const DeviceAuthenticationException('设备数据清除失败。');
      }
      if (status.state == DeviceClearProgressState.done) {
        if (status.finalResult != 0 ||
            status.finalMode != 0 ||
            (status.clearedScope & pending.preparation.effectiveClearScope) !=
                pending.preparation.effectiveClearScope) {
          throw const DeviceAuthenticationException('设备未完成完整的数据清除。');
        }
        _cancelGrantExpiryTimer();
        _grant = null;
        _pendingClear = null;
        _state = DeviceAuthState.unbound;
        await _discardClearCheckpoint(pending.deviceId);
        await _onClearCompleted?.call(pending.deviceId);
        notifyListeners();
        return;
      }
      delay = const Duration(milliseconds: 1000);
    }
    throw const DeviceAuthenticationException('设备数据清除状态查询超时。');
  }

  void clear() {
    _cancelGrantExpiryTimer();
    _grant = null;
    _pendingClear = null;
    _error = null;
    _state = DeviceAuthState.unbound;
    notifyListeners();
  }

  void _acceptGrant(DeviceAuthGrant grant) {
    _cancelGrantExpiryTimer();
    _grant = grant;
    _state = DeviceAuthState.authenticated;
    final ttl = Duration(seconds: grant.sessionTtlSeconds);
    if (ttl <= Duration.zero) {
      _expireGrant();
      return;
    }
    _grantExpiryTimer = _grantExpiryTimerFactory(ttl, _expireGrant);
  }

  void _expireGrant() {
    _grantExpiryTimer = null;
    _grant = null;
    if (_state == DeviceAuthState.authenticated) {
      _state = DeviceAuthState.unbound;
    }
    notifyListeners();
  }

  void _cancelGrantExpiryTimer() {
    _grantExpiryTimer?.cancel();
    _grantExpiryTimer = null;
  }

  @override
  void dispose() {
    _cancelGrantExpiryTimer();
    super.dispose();
  }

  Future<void> _saveClearCheckpoint(_PendingClear pending) async {
    final checkpoints = _clearCheckpoints;
    if (checkpoints == null) {
      return;
    }
    await checkpoints.save(
      DeviceClearCheckpoint(
        deviceId: pending.deviceId,
        transactionId: pending.transactionId,
        expectedBindingGeneration: pending.expectedBindingGeneration,
        confirmNonce: pending.preparation.confirmNonce,
        clearScope: pending.preparation.effectiveClearScope,
      ),
    );
  }

  Future<void> _discardClearCheckpoint(String deviceId) async {
    await _clearCheckpoints?.clear(deviceId);
  }

  static void _ensureSucceeded(
    DeviceSecurityResponse response,
    DeviceAuthAction action,
  ) {
    if (response.action != action || response.result != 0) {
      throw DeviceAuthenticationException('设备拒绝认证操作：${action.name}。');
    }
  }

  static int _secureTransactionId() {
    final random = Random.secure();
    return random.nextInt(0x7FFFFFFF) + 1;
  }

  static List<int> _secureNonce() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256));
  }
}

class _PendingClear {
  const _PendingClear({
    required this.deviceId,
    required this.transactionId,
    required this.expectedBindingGeneration,
    required this.preparation,
  });

  final String deviceId;
  final int transactionId;
  final int expectedBindingGeneration;
  final DeviceClearPreparation preparation;
}

class DeviceAuthGrant {
  const DeviceAuthGrant({
    required this.bindingGeneration,
    required this.sessionTtlSeconds,
    required this.sessionId,
    required this.grantedScope,
  });

  final int bindingGeneration;
  final int sessionTtlSeconds;
  final int sessionId;
  final int grantedScope;

  bool allows(DevicePermission permission) =>
      (grantedScope & permission.bit) != 0;

  factory DeviceAuthGrant.fromConfirmation(List<int> data) {
    if (data.length != 16) {
      throw const FormatException('认证确认响应长度无效。');
    }
    return DeviceAuthGrant(
      bindingGeneration: _u32Le(data, 0),
      sessionTtlSeconds: _u32Le(data, 4),
      sessionId: _u32Le(data, 8),
      grantedScope: _u32Le(data, 12),
    );
  }

  static int _u32Le(List<int> value, int offset) =>
      value[offset] |
      (value[offset + 1] << 8) |
      (value[offset + 2] << 16) |
      (value[offset + 3] << 24);
}

enum DevicePermission {
  status(1 << 0),
  configuration(1 << 1),
  files(1 << 2),
  realtimeAudio(1 << 3),
  ota(1 << 4),
  clear(1 << 5);

  const DevicePermission(this.bit);

  final int bit;
}

class DeviceAuthenticationException implements Exception {
  const DeviceAuthenticationException(this.message);

  final String message;

  @override
  String toString() => message;
}

List<int> _u32Le(int value) => <int>[
  value & 0xFF,
  (value >> 8) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 24) & 0xFF,
];

int _u16Le(List<int> value, int offset) =>
    value[offset] | (value[offset + 1] << 8);
