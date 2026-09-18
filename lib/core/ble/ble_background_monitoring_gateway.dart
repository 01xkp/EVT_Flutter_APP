import 'dart:async';
import 'dart:io';

import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:flutter/services.dart';

/// A non-sensitive description of the active BLE link that must remain
/// available while the application is backgrounded.
class BleBackgroundMonitoringRequest {
  const BleBackgroundMonitoringRequest({
    required this.deviceId,
    required this.deviceName,
  });

  final String deviceId;
  final String deviceName;

  Map<String, Object> toChannelArguments() => <String, Object>{
    'deviceId': deviceId,
    'deviceName': deviceName,
  };

  @override
  bool operator ==(Object other) =>
      other is BleBackgroundMonitoringRequest &&
      other.deviceId == deviceId &&
      other.deviceName == deviceName;

  @override
  int get hashCode => Object.hash(deviceId, deviceName);
}

/// Owns only the operating-system keep-alive facility.
///
/// The existing Flutter BLE transport remains the sole owner of the GATT
/// connection and all CCC subscriptions. Starting another native GATT client
/// here would create duplicate connections and can make the device drop an
/// indication channel.
abstract interface class BleBackgroundMonitoringGateway {
  Future<void> start(BleBackgroundMonitoringRequest request);

  Future<void> stop();
}

class BleBackgroundMonitoringException implements Exception {
  const BleBackgroundMonitoringException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Uses an Android connected-device foreground service. iOS keeps the active
/// CoreBluetooth central session through the `bluetooth-central` background
/// mode declared in Info.plist, so it does not need a second native service.
class PlatformBleBackgroundMonitoringGateway
    implements BleBackgroundMonitoringGateway {
  const PlatformBleBackgroundMonitoringGateway();

  static const _channel = MethodChannel(
    'com.aigutta.aipin/ble_background_monitoring',
  );
  static const _activationTimeout = Duration(seconds: 2);
  static const _statusPollInterval = Duration(milliseconds: 80);

  @override
  Future<void> start(BleBackgroundMonitoringRequest request) async {
    if (!Platform.isAndroid) {
      return;
    }
    await _channel.invokeMethod<void>(
      'startMonitoring',
      request.toChannelArguments(),
    );
    await _awaitNativeActivation();
  }

  @override
  Future<void> stop() async {
    if (!Platform.isAndroid) {
      return;
    }
    await _channel.invokeMethod<void>('stopMonitoring');
  }

  Future<void> _awaitNativeActivation() async {
    final deadline = DateTime.now().add(_activationTimeout);
    while (true) {
      final status = await _channel.invokeMapMethod<String, Object?>(
        'monitoringStatus',
      );
      final state = status?['state'] as String? ?? 'unknown';
      final failure = status?['failure'] as String?;
      if (state == 'active') {
        return;
      }
      if (state == 'failed') {
        throw BleBackgroundMonitoringException(
          'Android 后台 BLE 前台服务启动失败${failure == null ? '' : '：$failure'}。',
        );
      }
      if (DateTime.now().isAfter(deadline)) {
        throw BleBackgroundMonitoringException(
          'Android 后台 BLE 前台服务未在 ${_activationTimeout.inSeconds} 秒内进入活动状态（状态：$state）。',
        );
      }
      await Future<void>.delayed(_statusPollInterval);
    }
  }
}

/// Serializes start/stop transitions from the session lifecycle.
///
/// Android must start a foreground service while the app is still foreground.
/// Therefore the app activates this controller with the user-initiated GATT
/// connection flow, before a physical-button BIND response can arrive while
/// the app is backgrounded. It intentionally never starts background scanning
/// or a second connection.
class BleBackgroundMonitoringController {
  BleBackgroundMonitoringController(this._gateway, {SafeAppLogger? logger})
    : _logger = logger ?? const DebugSafeAppLogger(scope: 'APP_LIFECYCLE');

  final BleBackgroundMonitoringGateway _gateway;
  final SafeAppLogger _logger;

  BleBackgroundMonitoringRequest? _activeRequest;
  BleBackgroundMonitoringRequest? _desiredRequest;
  bool _canStart = true;
  Future<void> _serialOperation = Future<void>.value();

  bool get isActive => _activeRequest != null;

  /// Retains monitoring for a foreground-initiated V1.6 GATT connection
  /// attempt and its active session.
  Future<void> updateForSession({
    required bool shouldMonitor,
    String? deviceId,
    String? deviceName,
    bool canStart = true,
  }) {
    final request = shouldMonitor
        ? BleBackgroundMonitoringRequest(
            deviceId: _requireNonBlank(deviceId, 'deviceId'),
            deviceName: _requireNonBlank(deviceName, 'deviceName'),
          )
        : null;
    return _setDesiredRequest(request, canStart: canStart);
  }

  Future<void> deactivate() => _setDesiredRequest(null, canStart: true);

  Future<void> _setDesiredRequest(
    BleBackgroundMonitoringRequest? request, {
    required bool canStart,
  }) {
    final canStartChanged = _canStart != canStart;
    if (_desiredRequest == request &&
        !canStartChanged &&
        (request == null || _activeRequest == request || !canStart)) {
      return _serialOperation;
    }
    _desiredRequest = request;
    _canStart = canStart;
    final scheduledRequest = request;
    final scheduledCanStart = canStart;
    final operation = _serialOperation.then((_) async {
      // A newer session event superseded this transition while an earlier
      // native call was in progress. Let its queued transition own the final
      // service state instead.
      if (_desiredRequest != scheduledRequest ||
          _canStart != scheduledCanStart) {
        return;
      }
      if (scheduledRequest == null) {
        await _stopIfNeeded();
      } else if (scheduledCanStart) {
        await _startIfNeeded(scheduledRequest);
      }
    });
    _serialOperation = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _startIfNeeded(BleBackgroundMonitoringRequest request) async {
    if (_activeRequest == request) {
      return;
    }
    _logger.info(
      'background_ble_monitoring_start_requested',
      operation: 'background_ble_monitoring',
      stage: 'background_monitoring',
      result: 'pending',
      fields: <String, Object?>{
        'reason': '【后台BLE】前台已发起 GATT 连接，启动平台保活服务',
        'device_id': request.deviceId,
        'device_name': request.deviceName,
      },
    );
    try {
      await _gateway.start(request);
      _activeRequest = request;
      _logger.info(
        'background_ble_monitoring_started',
        operation: 'background_ble_monitoring',
        stage: 'background_monitoring',
        result: 'success',
        fields: <String, Object?>{
          'reason': '【后台BLE】平台保活已启用，现有 GATT 与 CCC 订阅继续由 Flutter 管理',
          'device_id': request.deviceId,
          'device_name': request.deviceName,
        },
      );
    } catch (error) {
      _activeRequest = null;
      _logger.warning(
        'background_ble_monitoring_start_failed',
        operation: 'background_ble_monitoring',
        stage: 'background_monitoring',
        result: 'failed',
        fields: <String, Object?>{
          'reason': '【后台BLE】平台保活未启动，前台会话仍可继续，但后台持续接收无法保证',
          'device_id': request.deviceId,
          'device_name': request.deviceName,
          'error_type': error.runtimeType.toString(),
        },
      );
    }
  }

  Future<void> _stopIfNeeded() async {
    if (_activeRequest == null) {
      return;
    }
    final request = _activeRequest!;
    _logger.info(
      'background_ble_monitoring_stop_requested',
      operation: 'background_ble_monitoring',
      stage: 'background_monitoring',
      result: 'pending',
      fields: <String, Object?>{
        'reason': '【后台BLE】会话已断开、解绑或关闭，停止平台保活服务',
        'device_id': request.deviceId,
        'device_name': request.deviceName,
      },
    );
    try {
      await _gateway.stop();
      _logger.info(
        'background_ble_monitoring_stopped',
        operation: 'background_ble_monitoring',
        stage: 'background_monitoring',
        result: 'success',
        fields: <String, Object?>{
          'reason': '【后台BLE】平台保活已停止',
          'device_id': request.deviceId,
          'device_name': request.deviceName,
        },
      );
    } catch (error) {
      _logger.warning(
        'background_ble_monitoring_stop_failed',
        operation: 'background_ble_monitoring',
        stage: 'background_monitoring',
        result: 'failed',
        fields: <String, Object?>{
          'reason': '【后台BLE】停止平台保活失败，下一次会话状态变化会再次同步',
          'device_id': request.deviceId,
          'device_name': request.deviceName,
          'error_type': error.runtimeType.toString(),
        },
      );
    } finally {
      _activeRequest = null;
    }
  }

  static String _requireNonBlank(String? value, String field) {
    final result = value?.trim() ?? '';
    if (result.isEmpty) {
      throw ArgumentError.value(value, field, 'must not be blank');
    }
    return result;
  }
}
