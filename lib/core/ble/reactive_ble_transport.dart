import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:aipin/core/ble/android_ble_scan_permission_policy.dart';
import 'package:aipin/core/ble/android_sdk_int_provider.dart';
import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/ble/ble_transport.dart';
import 'package:aipin/core/diagnostics/evt_failure.dart';
import 'package:aipin/core/diagnostics/evt_packet_log_summary.dart';
import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/features/device_discovery/domain/device_candidate.dart';
import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:flutter/services.dart' show EventChannel;
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart' as reactive;
import 'package:permission_handler/permission_handler.dart';
import 'package:reactive_ble_mobile/reactive_ble_mobile.dart' as mobile;

class ReactiveBleTransport implements BleTransport {
  static const _pairingRequiredMessage = '设备需要完成系统配对。';
  // flutter_reactive_ble installs its Dart value listener from the
  // readNotifications method-result continuation. Native code releases the
  // CCC barrier on the following platform event-loop turn; one short Dart
  // turn closes the remaining cross-thread handoff before an EVT command is
  // allowed to provoke an immediate Indicate response.
  static const _notificationListenerSettleDelay = Duration(milliseconds: 16);
  static const _iosMtuReportRetryDelay = Duration(milliseconds: 250);
  static const _iosMtuReportAttempts = 4;
  static const _nativeBleLogChannel = EventChannel('aipin/native_ble_logs');

  ReactiveBleTransport({
    reactive.FlutterReactiveBle? ble,
    SafeAppLogger? logger,
    AndroidSdkIntProvider? androidSdkIntProvider,
    this.nativeBleLogStream,
    bool? enableNativeBleLogBridge,
  }) : _client = ble,
       _logger = logger ?? const DebugSafeAppLogger(scope: 'BLE'),
       _androidSdkIntProvider =
           androidSdkIntProvider ?? const PlatformAndroidSdkIntProvider(),
       _enableNativeBleLogBridge =
           enableNativeBleLogBridge ?? (kDebugMode && Platform.isAndroid);

  reactive.FlutterReactiveBle? _client;
  final Map<String, _ActiveConnection> _connections = {};
  final SafeAppLogger _logger;
  final AndroidSdkIntProvider _androidSdkIntProvider;

  /// Optional injected native diagnostics source used by focused tests.
  @visibleForTesting
  final Stream<dynamic>? nativeBleLogStream;
  final bool _enableNativeBleLogBridge;
  StreamSubscription<dynamic>? _nativeBleLogSubscription;
  var _nativeBleLogBridgeFailed = false;
  var _disposed = false;

  String get _platformLabel {
    if (Platform.isAndroid) {
      return 'android';
    }
    if (Platform.isIOS) {
      return 'ios';
    }
    return 'other';
  }

  reactive.FlutterReactiveBle get _ble =>
      _client ??= reactive.FlutterReactiveBle();

  void _logInfo(
    String event, {
    required String operation,
    required String stage,
    required String result,
    required String reason,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  }) {
    try {
      _logger.info(
        event,
        operation: operation,
        stage: stage,
        result: result,
        elapsed: elapsed,
        fields: {'reason': reason, ...fields},
      );
    } on Object {
      // Diagnostic output must not affect BLE transport behavior.
    }
  }

  void _logError(
    String event, {
    required String operation,
    required String stage,
    required String result,
    required String reason,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  }) {
    try {
      _logger.error(
        event,
        operation: operation,
        stage: stage,
        result: result,
        elapsed: elapsed,
        fields: {'reason': reason, ...fields},
      );
    } on Object {
      // Diagnostic output must not affect BLE transport behavior.
    }
  }

  void _logWarning(
    String event, {
    required String operation,
    required String stage,
    required String result,
    required String reason,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  }) {
    try {
      _logger.warning(
        event,
        operation: operation,
        stage: stage,
        result: result,
        elapsed: elapsed,
        fields: {'reason': reason, ...fields},
      );
    } on Object {
      // Diagnostic output must not affect BLE transport behavior.
    }
  }

  void _ensureNativeBleLogBridge() {
    if (_disposed ||
        !_enableNativeBleLogBridge ||
        _nativeBleLogBridgeFailed ||
        _nativeBleLogSubscription != null) {
      return;
    }
    try {
      final stream =
          nativeBleLogStream ?? _nativeBleLogChannel.receiveBroadcastStream();
      _nativeBleLogSubscription = stream.listen(
        _onNativeBleLogEvent,
        onError: _onNativeBleLogError,
        onDone: _onNativeBleLogDone,
      );
    } on Object catch (error) {
      _nativeBleLogBridgeFailed = true;
      _logWarning(
        'native_ble_log_bridge_unavailable',
        operation: 'device_connect',
        stage: 'initialization',
        result: 'failed',
        reason: '【原生BLE日志】无法建立原生诊断事件通道，仍可使用 Dart 层日志联调',
        fields: _safeFailureFields(error),
      );
    }
  }

  void _onNativeBleLogEvent(dynamic payload) {
    if (_disposed) {
      return;
    }
    if (payload is! Map) {
      _logWarning(
        'native_ble_log_payload_invalid',
        operation: 'device_connect',
        stage: 'response',
        result: 'failed',
        reason: '【原生BLE日志】收到无法解析的原生诊断事件，已忽略',
        fields: {'type': payload.runtimeType.toString(), 'platform': 'android'},
      );
      return;
    }
    final event = _nativeDiagnosticEventName(payload['event']);
    final fields = nativeDiagnosticFieldsFor(payload);
    final level = payload['level']?.toString().toUpperCase();
    final stage = fields.containsKey('raw_packet_hex')
        ? 'response'
        : 'connected';
    switch (level) {
      case 'E':
        _logError(
          event,
          operation: 'device_connect',
          stage: stage,
          result: 'failed',
          reason: fields['reason'] as String? ?? '【原生BLE日志】设备联调原生层报告异常',
          fields: fields,
        );
      case 'W':
        _logWarning(
          event,
          operation: 'device_connect',
          stage: stage,
          result: 'failed',
          reason: fields['reason'] as String? ?? '【原生BLE日志】设备联调原生层报告警告',
          fields: fields,
        );
      default:
        _logInfo(
          event,
          operation: 'device_connect',
          stage: stage,
          result: 'success',
          reason: fields['reason'] as String? ?? '【原生BLE日志】已收到原生 BLE 诊断事件',
          fields: fields,
        );
    }
  }

  void _onNativeBleLogError(Object error, StackTrace stackTrace) {
    if (_disposed) {
      return;
    }
    _nativeBleLogBridgeFailed = true;
    _logWarning(
      'native_ble_log_bridge_failed',
      operation: 'device_connect',
      stage: 'response',
      result: 'failed',
      reason: '【原生BLE日志】原生诊断事件通道已中断，继续保留 Dart 层日志',
      fields: _safeFailureFields(error),
    );
  }

  void _onNativeBleLogDone() {
    _nativeBleLogSubscription = null;
    if (_disposed) {
      return;
    }
    _nativeBleLogBridgeFailed = true;
    _logWarning(
      'native_ble_log_bridge_closed',
      operation: 'device_connect',
      stage: 'response',
      result: 'failed',
      reason: '【原生BLE日志】原生诊断事件通道已关闭，继续保留 Dart 层日志',
    );
  }

  /// Makes native-only events safe for the same persistent Debug log used by
  /// the Dart transport. Full MAC addresses and UUIDs are reduced before they
  /// reach the shared diagnostic store; packet hex remains available only in
  /// Debug through [DiagnosticSanitizer].
  @visibleForTesting
  static Map<String, Object?> nativeDiagnosticFieldsFor(
    Map<dynamic, dynamic> payload,
  ) {
    final nativeFields = payload['fields'];
    final fields = nativeFields is Map
        ? nativeFields
        : const <dynamic, dynamic>{};
    final output = <String, Object?>{
      'platform': 'android',
      'event_kind': 'native_ble',
    };
    final message = _nativeString(payload['message']);
    if (message != null) {
      output['reason'] = message;
    }
    final timestamp = payload['timestamp_ms'];
    if (timestamp is num) {
      output['occurred_at'] = timestamp;
    }
    final deviceId = _nativeString(fields['device_id']);
    if (deviceId != null) {
      output['device_suffix'] = _safeDeviceReference(deviceId);
    }
    final characteristic = _nativeString(fields['characteristic_uuid']);
    if (characteristic != null) {
      output['characteristic'] = _safeCharacteristicReference(characteristic);
    }
    final instanceId = int.tryParse('${fields['instance_id']}');
    if (instanceId != null && instanceId >= 0) {
      output['instance_id'] = instanceId;
    }
    final setupCompleted = fields['setup_completed'];
    if (setupCompleted is bool) {
      output['setup_completed'] = setupCompleted;
    }
    final rawPacketHex = _normalizedNativeRawPacketHex(
      payload['raw_packet_hex'],
    );
    if (rawPacketHex != null) {
      output['raw_packet_hex'] = rawPacketHex;
      output['bytes'] = rawPacketHex.split(' ').length;
    }
    final packetCount = fields['packet_count'];
    if (packetCount is num) {
      output['count'] = packetCount;
    }
    final cccdPresent = fields['cccd_present'];
    if (cccdPresent is bool) {
      output['configured'] = cccdPresent;
    }
    final cccdRequired = fields['cccd_required'];
    if (cccdRequired is bool) {
      output['required'] = cccdRequired;
    }
    final responseMode = _nativeString(
      fields['response_mode'] ??
          fields['expected_evt_mode'] ??
          fields['expected_mode'],
    );
    if (responseMode != null) {
      output['requested_mode'] = responseMode;
    }
    final setupMode = _nativeString(fields['setup_mode']);
    if (setupMode != null) {
      output['setup_mode'] = setupMode;
    }
    final properties = _nativeString(
      fields['properties_hex'] ?? fields['properties'],
    );
    if (properties != null) {
      output['gatt_status'] = properties;
    }
    final byteCount = fields['bytes'];
    if (byteCount is num && !output.containsKey('bytes')) {
      output['bytes'] = byteCount;
    }
    final fileTransfer = fields['file_transfer'];
    if (fileTransfer is bool) {
      output['file_transfer'] = fileTransfer;
    }
    final rawPacketHexOmitted = fields['raw_packet_hex_omitted'];
    if (rawPacketHexOmitted is bool) {
      output['raw_packet_hex_omitted'] = rawPacketHexOmitted;
    }
    final errorType = _nativeString(fields['error_type']);
    if (errorType != null) {
      output['error_type'] = errorType;
    }
    return output;
  }

  static String _nativeDiagnosticEventName(Object? value) {
    final candidate = _nativeString(value);
    if (candidate != null &&
        RegExp(r'^[a-z][a-z0-9]*(?:_[a-z0-9]+)*$').hasMatch(candidate)) {
      return candidate;
    }
    return 'native_ble_diagnostic';
  }

  static String? _nativeString(Object? value) {
    if (value is! String) {
      return null;
    }
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  static String? _normalizedNativeRawPacketHex(Object? value) {
    final candidate = _nativeString(value)?.toUpperCase();
    if (candidate == null ||
        !RegExp(r'^(?:[0-9A-F]{2})(?: [0-9A-F]{2})*$').hasMatch(candidate)) {
      return null;
    }
    return candidate;
  }

  /// Starts the injected native event stream in a focused transport test.
  ///
  /// Production call sites initialize the bridge before a scan, connection,
  /// notification subscription, read, or write reaches the platform channel.
  @visibleForTesting
  void startNativeBleLogBridgeForTesting() => _ensureNativeBleLogBridge();

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final subscription = _nativeBleLogSubscription;
    _nativeBleLogSubscription = null;
    if (subscription != null) {
      try {
        await subscription.cancel();
      } on Object {
        // Provider disposal must not leak an asynchronous EventChannel error.
      }
    }
  }

  @override
  Stream<DeviceCandidate> scan() async* {
    _ensureNativeBleLogBridge();
    final stopwatch = Stopwatch()..start();
    var result = 'cancelled';
    var namedDiscoveryCount = 0;
    var repeatedNamedAdvertisementCount = 0;
    var unnamedDiscoveryCount = 0;
    final namedDeviceIds = <String>{};
    _logInfo(
      'scan_requested',
      operation: 'device_scan',
      stage: 'scanning',
      result: 'pending',
      reason: '【蓝牙扫描】收到扫描请求，开始检查权限和系统蓝牙状态',
      fields: {'platform': _platformLabel},
    );
    try {
      _logInfo(
        'scan_permission_check_started',
        operation: 'device_scan',
        stage: 'scanning',
        result: 'pending',
        reason: '【蓝牙扫描】开始检查运行时权限',
        fields: {'platform': _platformLabel},
      );
      final requireLocationServicesEnabled = await _ensureScanPermission();
      _logInfo(
        'scan_permission_check_completed',
        operation: 'device_scan',
        stage: 'scanning',
        result: 'success',
        elapsed: stopwatch.elapsed,
        reason: '【蓝牙扫描】运行时权限已满足，准备读取系统蓝牙状态',
        fields: {
          'platform': _platformLabel,
          'configured': requireLocationServicesEnabled,
        },
      );
      _logInfo(
        'scan_status_wait_started',
        operation: 'device_scan',
        stage: 'scanning',
        result: 'pending',
        elapsed: stopwatch.elapsed,
        reason: '【蓝牙扫描】等待系统返回蓝牙可用状态',
        fields: {'platform': _platformLabel},
      );
      final status = await _ble.statusStream
          .firstWhere((status) => status != reactive.BleStatus.unknown)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw BleTransportException(
              EvtFailure.environment(message: '蓝牙状态暂时不可用，请检查系统蓝牙后重试。'),
            ),
          );
      _logInfo(
        'bluetooth_status_received',
        operation: 'device_scan',
        stage: 'scanning',
        result: 'success',
        elapsed: stopwatch.elapsed,
        reason: '【蓝牙扫描】已获取系统蓝牙状态',
        fields: {'platform': _platformLabel, 'status': status.name},
      );
      final statusFailure = scanFailureForStatus(status);
      if (statusFailure != null) {
        _logError(
          'scan_status_rejected',
          operation: 'device_scan',
          stage: 'scanning',
          result: 'failed',
          elapsed: stopwatch.elapsed,
          reason: '【蓝牙扫描】系统蓝牙状态不满足扫描条件',
          fields: {
            'platform': _platformLabel,
            'status': status.name,
            'failure_kind': statusFailure.failure.kind.name,
          },
        );
        throw statusFailure;
      }
      _logInfo(
        'scan_native_started',
        operation: 'device_scan',
        stage: 'scanning',
        result: 'pending',
        elapsed: stopwatch.elapsed,
        reason: '【蓝牙扫描】已调用系统低延迟扫描，当前未启用严格 EVT 广播过滤',
        fields: {
          'platform': _platformLabel,
          'variant': 'low_latency_unfiltered',
          'configured': requireLocationServicesEnabled,
        },
      );
      await for (final device in _ble.scanForDevices(
        withServices: const [],
        scanMode: reactive.ScanMode.lowLatency,
        requireLocationServicesEnabled: requireLocationServicesEnabled,
      )) {
        if (device.name.trim().isNotEmpty) {
          final deviceReference = _safeDeviceReference(device.id);
          if (namedDeviceIds.add(device.id)) {
            namedDiscoveryCount += 1;
            _logInfo(
              'scan_named_device_discovered',
              operation: 'device_scan',
              stage: 'scanning',
              result: 'success',
              elapsed: stopwatch.elapsed,
              reason: '【蓝牙扫描】收到新的有名称设备广播，已生成候选设备',
              fields: {
                'device_suffix': deviceReference,
                'has_name': true,
                'rssi': device.rssi,
                'manufacturer_data_length': device.manufacturerData.length,
                'manufacturer_prefix': _manufacturerPrefix(
                  device.manufacturerData,
                ),
                'service_uuid_present': _hasEvtAdvertisementService(
                  device.serviceUuids,
                ),
                'name_format_valid': _hasEvtAdvertisementName(device.name),
                'subscription_count': namedDiscoveryCount,
              },
            );
          } else {
            repeatedNamedAdvertisementCount += 1;
            if (repeatedNamedAdvertisementCount == 1 ||
                repeatedNamedAdvertisementCount % 25 == 0) {
              _logInfo(
                'scan_named_device_aggregate',
                operation: 'device_scan',
                stage: 'scanning',
                result: 'success',
                elapsed: stopwatch.elapsed,
                reason: '【蓝牙扫描】重复设备广播已按批次汇总记录',
                fields: {
                  'subscription_count': repeatedNamedAdvertisementCount,
                  'length': namedDiscoveryCount,
                },
              );
            }
          }
        } else {
          unnamedDiscoveryCount += 1;
          // Android can surface a large number of anonymous advertisements in
          // a short interval. Record only periodic aggregate evidence so a
          // scan does not exhaust the persistent debug log before connection.
          if (unnamedDiscoveryCount == 1 || unnamedDiscoveryCount % 25 == 0) {
            _logInfo(
              'scan_unnamed_device_aggregate',
              operation: 'device_scan',
              stage: 'scanning',
              result: 'success',
              elapsed: stopwatch.elapsed,
              reason: '【蓝牙扫描】收到无名称设备广播，已按批次汇总记录',
              fields: {
                'has_name': false,
                'subscription_count': unnamedDiscoveryCount,
              },
            );
          }
        }
        // Do not drop an anonymous primary advertisement here. Android can
        // deliver the manufacturer payload (A3 89 + address) first and the
        // named scan response later. DiscoveryController owns the UI rule
        // that unnamed devices are hidden and can therefore merge both
        // fragments before deciding whether to display a row.
        yield DeviceCandidate(
          connectionId: device.id,
          name: device.name,
          manufacturerData: List.unmodifiable(device.manufacturerData),
          serviceUuids: List.unmodifiable(
            device.serviceUuids.map((uuid) => uuid.toString()),
          ),
          rssi: device.rssi,
          discoveredAt: DateTime.now(),
        );
      }
      result = 'completed';
      _logInfo(
        'scan_stream_completed',
        operation: 'device_scan',
        stage: 'scanning',
        result: result,
        elapsed: stopwatch.elapsed,
        reason: '【蓝牙扫描】系统扫描流已正常结束',
        fields: {
          'subscription_count': namedDiscoveryCount,
          'length': unnamedDiscoveryCount,
        },
      );
    } on BleTransportException catch (error) {
      result = 'failed';
      _logError(
        'scan_failed',
        operation: 'device_scan',
        stage: 'scanning',
        result: result,
        elapsed: stopwatch.elapsed,
        reason: '【蓝牙扫描】扫描终止，已返回可处理的蓝牙错误',
        fields: {
          'failure_kind': error.failure.kind.name,
          'status': error.issue?.name ?? 'none',
        },
      );
      rethrow;
    } catch (error, stackTrace) {
      result = 'failed';
      _logError(
        'scan_failed',
        operation: 'device_scan',
        stage: 'scanning',
        result: result,
        elapsed: stopwatch.elapsed,
        reason: '【蓝牙扫描】系统扫描发生未分类异常',
        fields: _safeFailureFields(error),
      );
      Error.throwWithStackTrace(
        BleTransportException(
          EvtFailure.environment(message: '蓝牙扫描不可用。', detail: '$error'),
        ),
        stackTrace,
      );
    } finally {
      stopwatch.stop();
      _logInfo(
        'scan_stream_closed',
        operation: 'device_scan',
        stage: 'scanning',
        result: result,
        elapsed: stopwatch.elapsed,
        reason: '【蓝牙扫描】扫描流已关闭',
        fields: {
          'subscription_count': namedDiscoveryCount,
          'length': unnamedDiscoveryCount,
        },
      );
    }
  }

  @override
  Stream<BleConnectionState> connect(String deviceId) {
    _ensureNativeBleLogBridge();
    final stopwatch = Stopwatch()..start();
    _logInfo(
      'connection_requested',
      operation: 'device_connect',
      stage: 'connecting',
      result: 'pending',
      reason: '【蓝牙连接】收到连接请求，准备调用系统 GATT 连接',
      fields: {
        'device_suffix': _safeDeviceReference(deviceId),
        'platform': _platformLabel,
      },
    );
    final existing = _connections[deviceId];
    if (existing != null) {
      _logInfo(
        'connection_reused',
        operation: 'device_connect',
        stage: 'connecting',
        result: 'accepted',
        elapsed: stopwatch.elapsed,
        reason: '【蓝牙连接】复用现有连接流，不重复发起 GATT 连接',
        fields: {'device_suffix': _safeDeviceReference(deviceId)},
      );
      return existing.controller.stream;
    }

    final controller = StreamController<BleConnectionState>.broadcast();
    late final StreamSubscription<reactive.ConnectionStateUpdate> subscription;
    _logInfo(
      'connection_native_started',
      operation: 'device_connect',
      stage: 'connecting',
      result: 'pending',
      elapsed: stopwatch.elapsed,
      reason: '【蓝牙连接】已调用系统 GATT 连接，等待连接状态回调',
      fields: {
        'device_suffix': _safeDeviceReference(deviceId),
        'platform': _platformLabel,
        'duration_ms': 12000,
      },
    );
    subscription = _ble
        .connectToDevice(
          id: deviceId,
          // The App performs one explicit full discovery immediately after
          // the connected event.  Passing an empty (but non-null) map keeps
          // the iOS native plugin from starting its optional implicit
          // discovery at the same time; two in-flight discovery tasks for
          // one peripheral are not safely multiplexed by CoreBluetooth's
          // task registry. Android ignores this optimization because it
          // cannot perform partial discovery.
          servicesWithCharacteristicsToDiscover:
              const <reactive.Uuid, List<reactive.Uuid>>{},
          connectionTimeout: const Duration(seconds: 12),
        )
        .listen(
          (update) {
            _logInfo(
              'connection_state_received',
              operation: 'device_connect',
              stage:
                  update.connectionState ==
                      reactive.DeviceConnectionState.connected
                  ? 'connected'
                  : 'connecting',
              result: _connectionUpdateResult(update),
              elapsed: stopwatch.elapsed,
              reason: update.failure == null
                  ? '【蓝牙连接】收到系统连接状态更新'
                  : '【蓝牙连接】收到系统连接失败状态',
              fields: {
                'device_suffix': _safeDeviceReference(deviceId),
                'state': update.connectionState.name,
                if (update.failure != null)
                  ..._safeFailureFields(update.failure!),
              },
            );
            if (update.failure != null) {
              _logError(
                'connection_state_failed',
                operation: 'device_connect',
                stage: 'connecting',
                result: 'failed',
                elapsed: stopwatch.elapsed,
                reason: '【蓝牙连接】系统报告连接失败，已向上层返回错误',
                fields: {
                  'device_suffix': _safeDeviceReference(deviceId),
                  'state': update.connectionState.name,
                  ..._safeFailureFields(update.failure!),
                },
              );
              controller.addError(
                BleTransportException(
                  EvtFailure.transport(
                    message: '蓝牙连接失败。',
                    detail: update.failure.toString(),
                  ),
                ),
              );
            }
            controller.add(_mapConnectionState(update.connectionState));
          },
          onError: (Object error, StackTrace stackTrace) {
            _logError(
              'connection_stream_failed',
              operation: 'device_connect',
              stage: 'connecting',
              result: 'failed',
              elapsed: stopwatch.elapsed,
              reason: '【蓝牙连接】系统连接流发生异常，已向上层返回错误',
              fields: {
                'device_suffix': _safeDeviceReference(deviceId),
                ..._safeFailureFields(error),
              },
            );
            controller.addError(
              BleTransportException(
                EvtFailure.transport(message: '蓝牙连接异常。', detail: '$error'),
              ),
              stackTrace,
            );
          },
          onDone: () {
            stopwatch.stop();
            _logInfo(
              'connection_stream_closed',
              operation: 'device_connect',
              stage: 'connected',
              result: 'completed',
              elapsed: stopwatch.elapsed,
              reason: '【蓝牙连接】系统连接流已结束，清理本地连接引用',
              fields: {'device_suffix': _safeDeviceReference(deviceId)},
            );
            _finishConnection(deviceId, controller);
          },
        );
    _connections[deviceId] = _ActiveConnection(controller, subscription);
    return controller.stream;
  }

  @override
  Future<List<BleService>> discoverServices(String deviceId) async {
    final stopwatch = Stopwatch()..start();
    try {
      _logInfo(
        'service_discovery_requested',
        operation: 'device_connect',
        stage: 'connected',
        result: 'pending',
        reason: '【服务发现】开始读取已连接设备的 GATT 服务与特征值',
        fields: {'device_suffix': _safeDeviceReference(deviceId)},
      );
      _logInfo(
        'service_discovery_native_started',
        operation: 'device_connect',
        stage: 'connected',
        result: 'pending',
        elapsed: stopwatch.elapsed,
        reason: '【服务发现】已调用系统服务发现接口',
        fields: {'device_suffix': _safeDeviceReference(deviceId)},
      );
      await _ble.discoverAllServices(deviceId);
      _logInfo(
        'service_discovery_native_completed',
        operation: 'device_connect',
        stage: 'connected',
        result: 'success',
        elapsed: stopwatch.elapsed,
        reason: '【服务发现】系统服务发现完成，开始读取发现结果',
        fields: {'device_suffix': _safeDeviceReference(deviceId)},
      );
      final services = await _ble.getDiscoveredServices(deviceId);
      final discoveredServices = services
          .map(
            (service) => BleService(
              uuid: service.id.toString(),
              characteristicUuids: List.unmodifiable(
                service.characteristics.map(
                  (characteristic) => characteristic.id.toString(),
                ),
              ),
              characteristics: List.unmodifiable(
                service.characteristics
                    .map(
                      (characteristic) => BleDiscoveredCharacteristic(
                        uuid: characteristic.id.toString(),
                        operations: {
                          if (characteristic.isReadable) BleOperation.read,
                          if (characteristic.isWritableWithResponse)
                            BleOperation.write,
                          if (characteristic.isWritableWithoutResponse)
                            BleOperation.writeWithoutResponse,
                          if (characteristic.isNotifiable) BleOperation.notify,
                          if (characteristic.isIndicatable)
                            BleOperation.indicate,
                        },
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          )
          .toList(growable: false);
      stopwatch.stop();
      _logInfo(
        'service_discovery_success',
        operation: 'device_connect',
        stage: 'connected',
        result: 'success',
        elapsed: stopwatch.elapsed,
        reason: '【服务发现】已读取 GATT 结果并生成服务能力清单',
        fields: {
          'device_suffix': _safeDeviceReference(deviceId),
          // UUIDs are not retained in diagnostics. Counts prove that service
          // discovery completed while keeping the debug log non-identifying.
          'service_count': discoveredServices.length,
          'characteristic_count': discoveredServices.fold<int>(
            0,
            (total, service) => total + service.characteristics.length,
          ),
        },
      );
      return List.unmodifiable(discoveredServices);
    } catch (error, stackTrace) {
      stopwatch.stop();
      _logError(
        'service_discovery_failed',
        operation: 'device_connect',
        stage: 'connected',
        result: 'failed',
        elapsed: stopwatch.elapsed,
        reason: '【服务发现】服务或特征值读取失败',
        fields: {
          'device_suffix': _safeDeviceReference(deviceId),
          ..._safeFailureFields(error),
        },
      );
      Error.throwWithStackTrace(
        BleTransportException(
          EvtFailure.transport(message: '服务发现失败。', detail: '$error'),
        ),
        stackTrace,
      );
    }
  }

  @override
  Future<BleGattCacheClearResult> clearGattCache(String deviceId) async {
    final stopwatch = Stopwatch()..start();
    final deviceReference = _safeDeviceReference(deviceId);
    if (!Platform.isAndroid) {
      stopwatch.stop();
      _logInfo(
        'gatt_cache_refresh_skipped',
        operation: 'device_connect',
        stage: 'connected',
        result: 'cancelled',
        elapsed: stopwatch.elapsed,
        reason: '【GATT恢复】当前平台不支持清理 GATT 缓存，后续将重新连接并发现服务',
        fields: {
          'device_suffix': deviceReference,
          'platform': _platformLabel,
          'gatt_cache_refresh_supported': false,
          'gatt_cache_refresh_attempted': false,
          'next_action': 'reconnect',
        },
      );
      return BleGattCacheClearResult.unsupported;
    }

    try {
      _logInfo(
        'gatt_cache_refresh_requested',
        operation: 'device_connect',
        stage: 'connected',
        result: 'pending',
        elapsed: stopwatch.elapsed,
        reason: '【GATT恢复】认证回包超时后请求系统刷新当前连接的 GATT 缓存',
        fields: {
          'device_suffix': deviceReference,
          'platform': _platformLabel,
          'gatt_cache_refresh_supported': true,
          'gatt_cache_refresh_attempted': true,
        },
      );
      await _ble.clearGattCache(deviceId).timeout(const Duration(seconds: 3));
      stopwatch.stop();
      _logInfo(
        'gatt_cache_refresh_completed',
        operation: 'device_connect',
        stage: 'connected',
        result: 'success',
        elapsed: stopwatch.elapsed,
        reason: '【GATT恢复】系统已接受 GATT 缓存刷新请求，当前会话仍需断开后重新连接',
        fields: {
          'device_suffix': deviceReference,
          'platform': _platformLabel,
          'gatt_cache_refresh_supported': true,
          'gatt_cache_refresh_attempted': true,
          'gatt_cache_refresh_result': 'cleared',
          'next_action': 'reconnect',
        },
      );
      return BleGattCacheClearResult.cleared;
    } catch (error) {
      stopwatch.stop();
      _logError(
        'gatt_cache_refresh_failed',
        operation: 'device_connect',
        stage: 'connected',
        result: 'failed',
        elapsed: stopwatch.elapsed,
        reason: '【GATT恢复】系统未能刷新 GATT 缓存，保留原认证超时结果并继续安全断开',
        fields: {
          'device_suffix': deviceReference,
          'platform': _platformLabel,
          'gatt_cache_refresh_supported': true,
          'gatt_cache_refresh_attempted': true,
          'gatt_cache_refresh_result': 'failed',
          'error_type': error.runtimeType.toString(),
          'next_action': 'reconnect',
        },
      );
      return BleGattCacheClearResult.failed;
    }
  }

  @override
  Future<int> requestMtu(String deviceId, {required int preferredMtu}) async {
    final stopwatch = Stopwatch()..start();
    if (preferredMtu < 23) {
      stopwatch.stop();
      _logError(
        'mtu_request_rejected',
        operation: 'device_connect',
        stage: 'connected',
        result: 'failed',
        elapsed: stopwatch.elapsed,
        reason: '【MTU协商】请求值小于 BLE 最小 ATT MTU，未调用系统接口',
        fields: {
          'device_suffix': _safeDeviceReference(deviceId),
          'required_mtu': preferredMtu,
          'failure_kind': 'invalid_argument',
        },
      );
      throw RangeError.range(preferredMtu, 23, null, 'preferredMtu');
    }
    try {
      _logInfo(
        'mtu_request_started',
        operation: 'device_connect',
        stage: 'connected',
        result: 'pending',
        reason: '【MTU协商】已请求系统协商 ATT MTU',
        fields: {
          'device_suffix': _safeDeviceReference(deviceId),
          'required_mtu': preferredMtu,
          'platform': _platformLabel,
        },
      );
      final isIOS = Platform.isIOS;
      final maximumAttempts = isIOS ? _iosMtuReportAttempts : 1;
      var attempt = 0;
      var reported = 0;
      while (attempt < maximumAttempts) {
        attempt += 1;
        reported = await _ble
            .requestMtu(deviceId: deviceId, mtu: preferredMtu)
            .timeout(const Duration(seconds: 12));
        if (!shouldRetryIosMtuReport(reported, isIOS: isIOS) ||
            attempt == maximumAttempts) {
          break;
        }
        _logInfo(
          'mtu_report_retry_scheduled',
          operation: 'device_connect',
          stage: 'connected',
          result: 'pending',
          elapsed: stopwatch.elapsed,
          reason: '【MTU协商】iOS 尚未报告协商后的写入容量，短暂等待后再次读取系统值',
          fields: {
            'device_suffix': _safeDeviceReference(deviceId),
            'attempt': attempt,
            'reported_write_payload': reported,
            'platform': _platformLabel,
          },
        );
        await Future<void>.delayed(_iosMtuReportRetryDelay);
      }
      final mtu = attMtuFromPlugin(reported, reportedAsWritePayload: isIOS);
      stopwatch.stop();
      _logInfo(
        'mtu_negotiated',
        operation: 'device_connect',
        stage: 'connected',
        result: 'success',
        elapsed: stopwatch.elapsed,
        reason: '【MTU协商】系统已返回可用 ATT MTU',
        fields: {
          'device_suffix': _safeDeviceReference(deviceId),
          'mtu': mtu,
          'required_mtu': preferredMtu,
          'platform': _platformLabel,
          'attempt': attempt,
        },
      );
      return mtu;
    } catch (error, stackTrace) {
      stopwatch.stop();
      _logError(
        'mtu_negotiation_failed',
        operation: 'device_connect',
        stage: 'connected',
        result: 'failed',
        elapsed: stopwatch.elapsed,
        reason: '【MTU协商】系统未能完成 ATT MTU 协商',
        fields: {
          'device_suffix': _safeDeviceReference(deviceId),
          'required_mtu': preferredMtu,
          ..._safeFailureFields(error),
        },
      );
      Error.throwWithStackTrace(
        BleTransportException(
          EvtFailure.transport(message: '蓝牙 MTU 协商失败。', detail: '$error'),
        ),
        stackTrace,
      );
    }
  }

  @override
  Stream<Uint8List> subscribe(BleCharacteristic characteristic) async* {
    _ensureNativeBleLogBridge();
    final stopwatch = Stopwatch()..start();
    var notificationCount = 0;
    var result = 'cancelled';
    final characteristicFields = _safeCharacteristicFields(characteristic);
    BleTransportException receiveFailure(Object error) {
      final failure = gattOperationFailure(error, fallbackMessage: '状态订阅失败。');
      result = 'failed';
      _logError(
        'notification_subscription_failed',
        operation: 'device_connect',
        stage: 'connected',
        result: result,
        elapsed: stopwatch.elapsed,
        reason: '【通知订阅】通知订阅失败，已向上层返回可处理错误',
        fields: {
          ...characteristicFields,
          'pairing_required': failure.message == _pairingRequiredMessage,
          ..._safeFailureFields(error),
        },
      );
      return BleTransportException(failure);
    }

    try {
      _logInfo(
        'notification_subscription_requested',
        operation: 'device_connect',
        stage: 'connected',
        result: 'pending',
        reason: '【通知订阅】开始订阅设备状态通知或指示',
        fields: characteristicFields,
      );
      _logInfo(
        'notification_stream_opening',
        operation: 'device_connect',
        stage: 'connected',
        result: 'pending',
        elapsed: stopwatch.elapsed,
        reason: '【通知订阅】已调用系统通知订阅接口，等待首个数据包',
        fields: characteristicFields,
      );
      // Forward cancellation even while the peripheral is silent. An await-for
      // wrapper can wait for another packet before cancelling its subscription.
      yield* _ble
          .subscribeToCharacteristic(_qualifiedCharacteristic(characteristic))
          .map((bytes) {
            notificationCount += 1;
            _logInfo(
              'notification_received',
              operation: 'device_connect',
              stage: 'connected',
              result: 'success',
              elapsed: stopwatch.elapsed,
              reason: '【通知订阅】收到设备通知数据，完整原始十六进制已写入 Debug 日志',
              fields: {
                ...characteristicFields,
                ...safeByteSummaryForDiagnostics(bytes),
                'subscription_count': notificationCount,
              },
            );
            return Uint8List.fromList(bytes);
          })
          .transform(
            StreamTransformer<Uint8List, Uint8List>.fromHandlers(
              handleError: (error, stackTrace, sink) {
                sink.addError(receiveFailure(error), stackTrace);
                sink.close();
              },
            ),
          );
      if (result != 'failed') result = 'completed';
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(receiveFailure(error), stackTrace);
    } finally {
      stopwatch.stop();
      _logInfo(
        'notification_stream_closed',
        operation: 'device_connect',
        stage: 'connected',
        result: result,
        elapsed: stopwatch.elapsed,
        reason: '【通知订阅】通知流已关闭',
        fields: {
          ...characteristicFields,
          'subscription_count': notificationCount,
        },
      );
    }
  }

  @override
  Future<void> awaitSubscriptionReady(BleCharacteristic characteristic) async {
    final stopwatch = Stopwatch()..start();
    final characteristicFields = _safeCharacteristicFields(characteristic);
    try {
      _logInfo(
        'notification_ccc_wait_started',
        operation: 'device_connect',
        stage: 'connected',
        result: 'pending',
        reason: '【通知订阅】等待系统完成 CCC 配置并确认原生监听器就绪',
        fields: {
          ...characteristicFields,
          'duration_ms': 8000,
          'platform': _platformLabel,
        },
      );
      await const mobile.ReactiveBleNotificationSetup()
          .awaitNotificationSetup(
            deviceId: characteristic.deviceId,
            characteristicUuid: characteristic.characteristicUuid,
          )
          .timeout(const Duration(seconds: 8));
      _logInfo(
        'notification_ccc_confirmed',
        operation: 'device_connect',
        stage: 'connected',
        result: 'pending',
        elapsed: stopwatch.elapsed,
        reason: '【通知订阅】系统已确认 CCC 配置，等待监听器跨线程稳定',
        fields: characteristicFields,
      );
      await Future<void>.delayed(_notificationListenerSettleDelay);
      stopwatch.stop();
      _logInfo(
        'notification_subscription_ready',
        operation: 'device_connect',
        stage: 'connected',
        result: 'success',
        elapsed: stopwatch.elapsed,
        reason: '【通知订阅】CCC 和 Dart 监听器均已就绪，可以下发指令',
        fields: {
          ...characteristicFields,
          'duration_ms': _notificationListenerSettleDelay.inMilliseconds,
        },
      );
    } on mobile.ReactiveBleNotificationSetupException catch (
      error,
      stackTrace
    ) {
      stopwatch.stop();
      _logError(
        'notification_ccc_failed',
        operation: 'device_connect',
        stage: 'connected',
        result: 'failed',
        elapsed: stopwatch.elapsed,
        reason: '【通知订阅】系统未能完成 CCC 配置',
        fields: {
          ...characteristicFields,
          'error_code': error.code,
          'failure_kind': 'notification_setup',
        },
      );
      Error.throwWithStackTrace(
        BleTransportException(
          EvtFailure.transport(
            message: '设备通知订阅未就绪。',
            detail: '${error.code}: ${error.message}',
          ),
        ),
        stackTrace,
      );
    } on TimeoutException catch (error, stackTrace) {
      stopwatch.stop();
      _logError(
        'notification_ccc_timeout',
        operation: 'device_connect',
        stage: 'connected',
        result: 'failed',
        elapsed: stopwatch.elapsed,
        reason: '【通知订阅】等待 CCC 配置超时',
        fields: {
          ...characteristicFields,
          'failure_kind': 'timeout',
          'error_type': error.runtimeType.toString(),
        },
      );
      Error.throwWithStackTrace(
        BleTransportException(
          EvtFailure.transport(message: '设备通知订阅超时。', detail: '$error'),
        ),
        stackTrace,
      );
    } catch (error, stackTrace) {
      stopwatch.stop();
      _logError(
        'notification_ccc_failed',
        operation: 'device_connect',
        stage: 'connected',
        result: 'failed',
        elapsed: stopwatch.elapsed,
        reason: '【通知订阅】等待 CCC 配置发生未分类异常',
        fields: {...characteristicFields, ..._safeFailureFields(error)},
      );
      Error.throwWithStackTrace(
        BleTransportException(
          EvtFailure.transport(message: '设备通知订阅失败。', detail: '$error'),
        ),
        stackTrace,
      );
    }
  }

  @override
  Future<Uint8List> read(BleCharacteristic characteristic) async {
    _ensureNativeBleLogBridge();
    final stopwatch = Stopwatch()..start();
    final characteristicFields = _safeCharacteristicFields(characteristic);
    try {
      _logInfo(
        'read_requested',
        operation: 'device_connect',
        stage: 'read',
        result: 'pending',
        reason: '【GATT读取】开始读取设备特征值',
        fields: characteristicFields,
      );
      final bytes = Uint8List.fromList(
        await _ble.readCharacteristic(_qualifiedCharacteristic(characteristic)),
      );
      stopwatch.stop();
      _logInfo(
        'read_completed',
        operation: 'device_connect',
        stage: 'read',
        result: 'success',
        elapsed: stopwatch.elapsed,
        reason: '【GATT读取】已收到设备特征值，完整原始十六进制已写入 Debug 日志',
        fields: {
          ...characteristicFields,
          ...safeByteSummaryForDiagnostics(bytes),
        },
      );
      return bytes;
    } catch (error, stackTrace) {
      final failure = gattOperationFailure(error, fallbackMessage: '状态读取失败。');
      stopwatch.stop();
      _logError(
        'read_failed',
        operation: 'device_connect',
        stage: 'read',
        result: 'failed',
        elapsed: stopwatch.elapsed,
        reason: '【GATT读取】读取特征值失败，已向上层返回可处理错误',
        fields: {
          ...characteristicFields,
          'pairing_required': failure.message == _pairingRequiredMessage,
          ..._safeFailureFields(error),
        },
      );
      Error.throwWithStackTrace(BleTransportException(failure), stackTrace);
    }
  }

  @override
  Future<void> write(BleCharacteristic characteristic, Uint8List bytes) =>
      _write(characteristic, bytes, withoutResponse: false);

  @override
  Future<void> writeWithoutResponse(
    BleCharacteristic characteristic,
    Uint8List bytes,
  ) => _write(characteristic, bytes, withoutResponse: true);

  Future<void> _write(
    BleCharacteristic characteristic,
    Uint8List bytes, {
    required bool withoutResponse,
  }) async {
    _ensureNativeBleLogBridge();
    final operation = withoutResponse ? 'write_without_response' : 'write';
    final stopwatch = Stopwatch()..start();
    final characteristicFields = _safeCharacteristicFields(characteristic);
    try {
      _logInfo(
        '${operation}_requested',
        operation: 'device_connect',
        stage: 'write',
        result: 'pending',
        reason: withoutResponse
            ? '【GATT写入】开始无响应写入设备特征值'
            : '【GATT写入】开始带响应写入设备特征值',
        fields: {
          ...characteristicFields,
          ...safeByteSummaryForDiagnostics(bytes),
          'variant': withoutResponse ? 'without_response' : 'with_response',
        },
      );
      final qualified = _qualifiedCharacteristic(characteristic);
      final future = withoutResponse
          ? _ble.writeCharacteristicWithoutResponse(qualified, value: bytes)
          : _ble.writeCharacteristicWithResponse(qualified, value: bytes);
      _logInfo(
        '${operation}_native_invoked',
        operation: 'device_connect',
        stage: 'write',
        result: 'pending',
        elapsed: stopwatch.elapsed,
        reason: '【GATT写入】已调用系统写入接口，等待平台完成回调',
        fields: {
          ...characteristicFields,
          ...safeByteSummaryForDiagnostics(bytes, includeRawPacketHex: false),
          'variant': withoutResponse ? 'without_response' : 'with_response',
          'duration_ms': 12000,
        },
      );
      await future.timeout(const Duration(seconds: 12));
      stopwatch.stop();
      _logInfo(
        '${operation}_completed',
        operation: 'device_connect',
        stage: 'write',
        result: 'success',
        elapsed: stopwatch.elapsed,
        reason: withoutResponse
            ? '【GATT写入】无响应写入已被系统接受'
            : '【GATT写入】带响应写入已收到系统完成回调',
        fields: {
          ...characteristicFields,
          ...safeByteSummaryForDiagnostics(bytes, includeRawPacketHex: false),
          'variant': withoutResponse ? 'without_response' : 'with_response',
        },
      );
    } catch (error, stackTrace) {
      final failure = gattOperationFailure(error, fallbackMessage: '蓝牙写入失败。');
      stopwatch.stop();
      _logError(
        '${operation}_failed',
        operation: 'device_connect',
        stage: 'write',
        result: 'failed',
        elapsed: stopwatch.elapsed,
        reason: withoutResponse
            ? '【GATT写入】无响应写入失败，已向上层返回可处理错误'
            : '【GATT写入】带响应写入失败，已向上层返回可处理错误',
        fields: {
          ...characteristicFields,
          ...safeByteSummaryForDiagnostics(bytes, includeRawPacketHex: false),
          'variant': withoutResponse ? 'without_response' : 'with_response',
          'pairing_required': failure.message == _pairingRequiredMessage,
          ..._safeFailureFields(error),
        },
      );
      Error.throwWithStackTrace(BleTransportException(failure), stackTrace);
    }
  }

  @override
  Future<void> disconnect(String deviceId) async {
    final stopwatch = Stopwatch()..start();
    _logInfo(
      'disconnect_requested',
      operation: 'device_connect',
      stage: 'connected',
      result: 'pending',
      reason: '【蓝牙断开】收到断开请求，开始取消系统连接流',
      fields: {'device_suffix': _safeDeviceReference(deviceId)},
    );
    final active = _connections.remove(deviceId);
    if (active == null) {
      stopwatch.stop();
      _logInfo(
        'disconnect_skipped',
        operation: 'device_connect',
        stage: 'connected',
        result: 'completed',
        elapsed: stopwatch.elapsed,
        reason: '【蓝牙断开】未找到活动连接，无需重复断开',
        fields: {'device_suffix': _safeDeviceReference(deviceId)},
      );
      return;
    }
    _logInfo(
      'disconnect_subscription_cancel_started',
      operation: 'device_connect',
      stage: 'connected',
      result: 'pending',
      elapsed: stopwatch.elapsed,
      reason: '【蓝牙断开】开始取消系统连接订阅',
      fields: {'device_suffix': _safeDeviceReference(deviceId)},
    );
    await active.subscription.cancel();
    _logInfo(
      'disconnect_controller_close_started',
      operation: 'device_connect',
      stage: 'connected',
      result: 'pending',
      elapsed: stopwatch.elapsed,
      reason: '【蓝牙断开】系统连接订阅已取消，开始关闭本地连接流',
      fields: {'device_suffix': _safeDeviceReference(deviceId)},
    );
    await active.controller.close();
    stopwatch.stop();
    _logInfo(
      'disconnect_completed',
      operation: 'device_connect',
      stage: 'connected',
      result: 'success',
      elapsed: stopwatch.elapsed,
      reason: '【蓝牙断开】本地连接流已关闭',
      fields: {'device_suffix': _safeDeviceReference(deviceId)},
    );
  }

  reactive.QualifiedCharacteristic _qualifiedCharacteristic(
    BleCharacteristic characteristic,
  ) {
    return reactive.QualifiedCharacteristic(
      deviceId: characteristic.deviceId,
      serviceId: reactive.Uuid.parse(characteristic.serviceUuid),
      characteristicId: reactive.Uuid.parse(characteristic.characteristicUuid),
    );
  }

  static Map<String, Object?> _safeCharacteristicFields(
    BleCharacteristic characteristic,
  ) => <String, Object?>{
    'device_suffix': _safeDeviceReference(characteristic.deviceId),
    'characteristic': _safeCharacteristicReference(
      characteristic.characteristicUuid,
    ),
  };

  /// The physical GATT boundary is the single raw-packet source. This gives a
  /// Debug log one authoritative copy of each send/receive byte sequence.
  @visibleForTesting
  static Map<String, Object?> safeByteSummaryForDiagnostics(
    List<int> bytes, {
    bool includeRawPacketHex = kDebugMode,
  }) => <String, Object?>{
    'bytes': bytes.length,
    'type': bytes.isEmpty
        ? 'empty'
        : includeRawPacketHex
        ? 'binary_full'
        : 'binary_redacted',
    ...EvtPacketLogSummary.debugRawPacketFields(
      bytes,
      includeRawData: includeRawPacketHex,
    ),
  };

  static Map<String, Object?> _safeFailureFields(Object error) {
    try {
      return <String, Object?>{
        'error_type': error.runtimeType.toString(),
        'failure_kind': _failureKind(error),
      };
    } on Object {
      return const <String, Object?>{
        'error_type': 'unknown',
        'failure_kind': 'unclassified',
      };
    }
  }

  static String _failureKind(Object error) {
    final value = '$error'.toLowerCase();
    if (_isPairingRequiredGattError(value)) {
      return 'pairing_required';
    }
    if (value.contains('timeout')) {
      return 'timeout';
    }
    if (value.contains('permission') || value.contains('unauthor')) {
      return 'permission';
    }
    if (value.contains('disconnect') || value.contains('not connected')) {
      return 'disconnected';
    }
    if (value.contains('gatt')) {
      return 'gatt';
    }
    return 'platform_error';
  }

  void _finishConnection(
    String deviceId,
    StreamController<BleConnectionState> controller,
  ) {
    final active = _connections[deviceId];
    if (active?.controller == controller) {
      _connections.remove(deviceId);
    }
    if (!controller.isClosed) {
      unawaited(controller.close());
    }
  }

  /// A stable, partial reference lets an engineer correlate events in one
  /// log without retaining a complete platform device identifier or MAC.
  @visibleForTesting
  static String safeDeviceReferenceForDiagnostics(String deviceId) =>
      _safeDeviceReference(deviceId);

  @visibleForTesting
  static String safeCharacteristicReferenceForDiagnostics(
    String characteristicUuid,
  ) => _safeCharacteristicReference(characteristicUuid);

  static String _safeDeviceReference(String deviceId) {
    final normalized = deviceId.replaceAll(RegExp(r'[^a-fA-F0-9]'), '');
    if (normalized.length <= 4) {
      return '...0000';
    }
    return '...${normalized.substring(normalized.length - 4).toUpperCase()}';
  }

  static String _safeCharacteristicReference(String characteristicUuid) {
    return EvtPacketLogSummary.characteristicReference(characteristicUuid);
  }

  static String _manufacturerPrefix(List<int> data) {
    if (data.length < 2) {
      return 'none';
    }
    return data
        .take(2)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join();
  }

  static bool _hasEvtAdvertisementService(List<reactive.Uuid> serviceUuids) =>
      serviceUuids.any((uuid) {
        final value = uuid.toString().toUpperCase();
        return value == '0000AF30-0000-1000-8000-00805F9B34FB' ||
            value == 'AF30' ||
            value == '0XAF30';
      });

  static bool _hasEvtAdvertisementName(String name) =>
      RegExp(r'^AIPIN_[0-9A-F]{4}$').hasMatch(name.trim().toUpperCase());

  /// Android reports ATT MTU directly. On iOS the plugin reports CoreBluetooth's
  /// maximum Write Without Response value length, which excludes the ATT header.
  @visibleForTesting
  static int attMtuFromPlugin(
    int reportedMtu, {
    bool reportedAsWritePayload = false,
  }) => reportedAsWritePayload ? reportedMtu + 3 : reportedMtu;

  /// CoreBluetooth can briefly expose the pre-exchange 20-byte write payload
  /// immediately after connecting. A bounded retry avoids rejecting a V1.6
  /// device before iOS has published its negotiated ATT capacity.
  @visibleForTesting
  static bool shouldRetryIosMtuReport(
    int reportedWritePayload, {
    required bool isIOS,
  }) => isIOS && reportedWritePayload <= 20;

  /// The Reactive BLE API leaves bonding to the operating system, so a
  /// protected-GATT error is the only portable signal available to the app.
  @visibleForTesting
  static EvtFailure gattOperationFailure(
    Object error, {
    required String fallbackMessage,
  }) {
    final detail = '$error';
    if (_isPairingRequiredGattError(detail)) {
      return EvtFailure.transport(
        message: _pairingRequiredMessage,
        detail: '请在系统弹窗完成设备配对后重试。原始 GATT 错误：$detail',
      );
    }
    return EvtFailure.transport(message: fallbackMessage, detail: detail);
  }

  static bool _isPairingRequiredGattError(String error) {
    final value = error.toLowerCase();
    const phrases = <String>[
      'insufficient authentication',
      'insufficient_authentication',
      'insufficient encryption',
      'insufficient_encryption',
      'authentication required',
      'encryption required',
      'requires authentication',
      'requires encryption',
      'authentication before',
      'not bonded',
      'bond required',
      'gatt_insufficient_authentication',
      'gatt_insufficient_encryption',
    ];
    if (phrases.any(value.contains)) {
      return true;
    }
    return RegExp(r'\b(?:gatt\s*)?status\s*[=:]\s*(?:5|15)\b').hasMatch(value);
  }

  @visibleForTesting
  static BleTransportException? scanFailureForStatus(
    reactive.BleStatus status,
  ) => switch (status) {
    reactive.BleStatus.poweredOff => BleTransportException(
      EvtFailure.environment(message: '蓝牙未开启。'),
      issue: BleTransportIssue.bluetoothOff,
    ),
    reactive.BleStatus.unsupported => BleTransportException(
      EvtFailure.environment(message: '当前设备不支持低功耗蓝牙。'),
    ),
    reactive.BleStatus.unauthorized => BleTransportException(
      EvtFailure.environment(message: '请在系统设置中允许本应用使用蓝牙。'),
    ),
    reactive.BleStatus.locationServicesDisabled => BleTransportException(
      EvtFailure.environment(message: '请开启系统定位服务后重新查找设备。'),
    ),
    reactive.BleStatus.unknown || reactive.BleStatus.ready => null,
  };

  /// iOS grants Bluetooth access when CoreBluetooth initializes. Do not use
  /// PermissionHandler as a scan gate there: Swift Package builds launched by
  /// Xcode can compile that optional permission module out before runtime.
  @visibleForTesting
  static bool requiresPermissionHandlerScanRequest({
    required bool isAndroid,
    required bool isIOS,
  }) {
    if (isIOS) {
      return false;
    }
    return isAndroid;
  }

  Future<bool> _ensureScanPermission() async {
    final stopwatch = Stopwatch()..start();
    if (!requiresPermissionHandlerScanRequest(
      isAndroid: Platform.isAndroid,
      isIOS: Platform.isIOS,
    )) {
      stopwatch.stop();
      _logInfo(
        'scan_permission_request_skipped',
        operation: 'device_scan',
        stage: 'scanning',
        result: 'accepted',
        elapsed: stopwatch.elapsed,
        reason: '【蓝牙扫描】当前平台由系统蓝牙初始化流程处理授权，不调用权限插件',
        fields: {'platform': _platformLabel},
      );
      return false;
    }

    final sdkInt = await _androidSdkIntProvider.sdkInt;
    final permissions =
        AndroidBleScanPermissionPolicy.platformPermissionsForSdkInt(sdkInt);
    _logInfo(
      'scan_permission_request_started',
      operation: 'device_scan',
      stage: 'scanning',
      result: 'pending',
      elapsed: stopwatch.elapsed,
      reason: '【蓝牙扫描】已向 Android 系统请求扫描所需权限',
      fields: {
        'platform': _platformLabel,
        'variant': 'android_api_$sdkInt',
        'length': permissions.length,
      },
    );
    final statuses = await permissions.request();
    if (statuses.values.any((status) => !status.isGranted)) {
      stopwatch.stop();
      _logError(
        'scan_permission_request_denied',
        operation: 'device_scan',
        stage: 'scanning',
        result: 'failed',
        elapsed: stopwatch.elapsed,
        reason: '【蓝牙扫描】Android 系统未授予全部扫描权限',
        fields: {
          'platform': _platformLabel,
          'variant': 'android_api_$sdkInt',
          'length': permissions.length,
          'failure_kind': 'permission',
        },
      );
      throw BleTransportException(
        EvtFailure.environment(
          message: sdkInt >= 31 ? '需要附近设备权限才能开始扫描。' : '需要定位权限才能开始扫描。',
        ),
      );
    }
    final requiresLocationServices =
        AndroidBleScanPermissionPolicy.requiresLocationServicesForScan(sdkInt);
    stopwatch.stop();
    _logInfo(
      'scan_permission_request_granted',
      operation: 'device_scan',
      stage: 'scanning',
      result: 'success',
      elapsed: stopwatch.elapsed,
      reason: '【蓝牙扫描】Android 系统已授予扫描权限',
      fields: {
        'platform': _platformLabel,
        'variant': 'android_api_$sdkInt',
        'length': permissions.length,
        'configured': requiresLocationServices,
      },
    );
    return requiresLocationServices;
  }

  static BleConnectionState _mapConnectionState(
    reactive.DeviceConnectionState state,
  ) => switch (state) {
    reactive.DeviceConnectionState.connecting => BleConnectionState.connecting,
    reactive.DeviceConnectionState.connected => BleConnectionState.connected,
    reactive.DeviceConnectionState.disconnecting =>
      BleConnectionState.disconnecting,
    reactive.DeviceConnectionState.disconnected =>
      BleConnectionState.disconnected,
  };

  static String _connectionUpdateResult(reactive.ConnectionStateUpdate update) {
    if (update.failure != null) {
      return 'failed';
    }
    return switch (update.connectionState) {
      reactive.DeviceConnectionState.connecting => 'pending',
      reactive.DeviceConnectionState.connected => 'success',
      reactive.DeviceConnectionState.disconnecting => 'pending',
      reactive.DeviceConnectionState.disconnected => 'completed',
    };
  }
}

class _ActiveConnection {
  const _ActiveConnection(this.controller, this.subscription);

  final StreamController<BleConnectionState> controller;
  final StreamSubscription<reactive.ConnectionStateUpdate> subscription;
}
