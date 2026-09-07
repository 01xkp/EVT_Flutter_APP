import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:aipin/core/ble/android_ble_scan_permission_policy.dart';
import 'package:aipin/core/ble/android_sdk_int_provider.dart';
import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/ble/ble_transport.dart';
import 'package:aipin/core/diagnostics/evt_failure.dart';
import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/features/device_discovery/domain/device_candidate.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart' as reactive;
import 'package:permission_handler/permission_handler.dart';

class ReactiveBleTransport implements BleTransport {
  static const _pairingRequiredMessage = '设备需要完成系统配对。';

  ReactiveBleTransport({
    reactive.FlutterReactiveBle? ble,
    SafeAppLogger? logger,
    AndroidSdkIntProvider? androidSdkIntProvider,
  }) : _client = ble,
       _logger = logger ?? const DebugSafeAppLogger(scope: 'BLE'),
       _androidSdkIntProvider =
           androidSdkIntProvider ?? const PlatformAndroidSdkIntProvider();

  reactive.FlutterReactiveBle? _client;
  final Map<String, _ActiveConnection> _connections = {};
  final SafeAppLogger _logger;
  final AndroidSdkIntProvider _androidSdkIntProvider;

  reactive.FlutterReactiveBle get _ble =>
      _client ??= reactive.FlutterReactiveBle();

  @override
  Stream<DeviceCandidate> scan() async* {
    try {
      _logger.info('scan_start');
      final requireLocationServicesEnabled = await _ensureScanPermission();
      final status = await _ble.statusStream
          .firstWhere((status) => status != reactive.BleStatus.unknown)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw BleTransportException(
              EvtFailure.environment(message: '蓝牙状态暂时不可用，请检查系统蓝牙后重试。'),
            ),
          );
      _logger.info('bluetooth_status', fields: {'status': status.name});
      final statusFailure = scanFailureForStatus(status);
      if (statusFailure != null) {
        throw statusFailure;
      }
      await for (final device in _ble.scanForDevices(
        withServices: const [],
        scanMode: reactive.ScanMode.lowLatency,
        requireLocationServicesEnabled: requireLocationServicesEnabled,
      )) {
        _logger.info(
          'scan_result',
          fields: {
            'device': _redactDeviceId(device.id),
            'hasName': device.name.trim().isNotEmpty,
            'rssi': device.rssi,
          },
        );
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
    } on BleTransportException catch (error) {
      _logger.info(
        'scan_failure',
        fields: {
          'issue': error.issue?.name ?? 'none',
          'message': error.failure.message,
          'detail': error.failure.detail ?? 'none',
        },
      );
      rethrow;
    } catch (error, stackTrace) {
      _logger.info('scan_failure', fields: {'error': '$error'});
      Error.throwWithStackTrace(
        BleTransportException(
          EvtFailure.environment(message: '蓝牙扫描不可用。', detail: '$error'),
        ),
        stackTrace,
      );
    }
  }

  @override
  Stream<BleConnectionState> connect(String deviceId) {
    _logger.info(
      'connect_request',
      fields: {'device': _redactDeviceId(deviceId)},
    );
    final existing = _connections[deviceId];
    if (existing != null) {
      _logger.info(
        'connect_reuse',
        fields: {'device': _redactDeviceId(deviceId)},
      );
      return existing.controller.stream;
    }

    final controller = StreamController<BleConnectionState>.broadcast();
    late final StreamSubscription<reactive.ConnectionStateUpdate> subscription;
    subscription = _ble
        .connectToDevice(
          id: deviceId,
          connectionTimeout: const Duration(seconds: 12),
        )
        .listen(
          (update) {
            _logger.info(
              'connection_update',
              fields: {
                'device': _redactDeviceId(deviceId),
                'state': update.connectionState.name,
                'failure': update.failure?.toString() ?? 'none',
              },
            );
            if (update.failure != null) {
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
            _logger.info(
              'connection_error',
              fields: {'device': _redactDeviceId(deviceId), 'error': '$error'},
            );
            controller.addError(
              BleTransportException(
                EvtFailure.transport(message: '蓝牙连接异常。', detail: '$error'),
              ),
              stackTrace,
            );
          },
          onDone: () {
            _logger.info(
              'connection_stream_done',
              fields: {'device': _redactDeviceId(deviceId)},
            );
            _finishConnection(deviceId, controller);
          },
        );
    _connections[deviceId] = _ActiveConnection(controller, subscription);
    return controller.stream;
  }

  @override
  Future<List<BleService>> discoverServices(String deviceId) async {
    try {
      _logger.info(
        'service_discovery_start',
        fields: {'device': _redactDeviceId(deviceId)},
      );
      await _ble.discoverAllServices(deviceId);
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
      _logger.info(
        'service_discovery_success',
        fields: {
          'device': _redactDeviceId(deviceId),
          'serviceCount': discoveredServices.length,
          'services': discoveredServices
              .map(
                (service) =>
                    '${service.uuid}[${service.characteristicUuids.join(',')}]',
              )
              .join(';'),
        },
      );
      return List.unmodifiable(discoveredServices);
    } catch (error, stackTrace) {
      _logger.info(
        'service_discovery_failure',
        fields: {'device': _redactDeviceId(deviceId), 'error': '$error'},
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
  Future<int> requestMtu(String deviceId, {required int preferredMtu}) async {
    if (preferredMtu < 23) {
      throw RangeError.range(preferredMtu, 23, null, 'preferredMtu');
    }
    try {
      final reported = await _ble
          .requestMtu(deviceId: deviceId, mtu: preferredMtu)
          .timeout(const Duration(seconds: 12));
      final mtu = attMtuFromPlugin(
        reported,
        reportedAsWritePayload: Platform.isIOS,
      );
      _logger.info(
        'mtu_negotiated',
        fields: {
          'device': _redactDeviceId(deviceId),
          'mtu': mtu,
          'platform': Platform.isIOS ? 'ios' : 'android',
        },
      );
      return mtu;
    } catch (error, stackTrace) {
      _logger.info(
        'mtu_negotiation_failure',
        fields: {'device': _redactDeviceId(deviceId), 'error': '$error'},
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
    try {
      _logger.info(
        'notification_subscribe_start',
        fields: {
          'device': _redactDeviceId(characteristic.deviceId),
          'characteristic': characteristic.characteristicUuid,
        },
      );
      await for (final bytes in _ble.subscribeToCharacteristic(
        _qualifiedCharacteristic(characteristic),
      )) {
        _logger.info(
          'notification_received',
          fields: {
            'device': _redactDeviceId(characteristic.deviceId),
            'bytes': bytes.length,
          },
        );
        yield Uint8List.fromList(bytes);
      }
    } catch (error, stackTrace) {
      final failure = gattOperationFailure(error, fallbackMessage: '状态订阅失败。');
      _logger.info(
        'notification_subscribe_failure',
        fields: {
          'device': _redactDeviceId(characteristic.deviceId),
          'error': '$error',
          'pairing_required': failure.message == _pairingRequiredMessage,
        },
      );
      Error.throwWithStackTrace(BleTransportException(failure), stackTrace);
    }
  }

  @override
  Future<Uint8List> read(BleCharacteristic characteristic) async {
    try {
      _logger.info(
        'read_start',
        fields: {
          'device': _redactDeviceId(characteristic.deviceId),
          'characteristic': characteristic.characteristicUuid,
        },
      );
      final bytes = Uint8List.fromList(
        await _ble.readCharacteristic(_qualifiedCharacteristic(characteristic)),
      );
      _logger.info(
        'read_success',
        fields: {
          'device': _redactDeviceId(characteristic.deviceId),
          'bytes': bytes.length,
        },
      );
      return bytes;
    } catch (error, stackTrace) {
      final failure = gattOperationFailure(error, fallbackMessage: '状态读取失败。');
      _logger.info(
        'read_failure',
        fields: {
          'device': _redactDeviceId(characteristic.deviceId),
          'error': '$error',
          'pairing_required': failure.message == _pairingRequiredMessage,
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
    final operation = withoutResponse ? 'write_without_response' : 'write';
    try {
      _logger.info(
        '${operation}_start',
        fields: {
          'device': _redactDeviceId(characteristic.deviceId),
          'characteristic': characteristic.characteristicUuid,
          'bytes': bytes.length,
        },
      );
      final qualified = _qualifiedCharacteristic(characteristic);
      final future = withoutResponse
          ? _ble.writeCharacteristicWithoutResponse(qualified, value: bytes)
          : _ble.writeCharacteristicWithResponse(qualified, value: bytes);
      await future.timeout(const Duration(seconds: 12));
      _logger.info(
        '${operation}_success',
        fields: {
          'device': _redactDeviceId(characteristic.deviceId),
          'bytes': bytes.length,
        },
      );
    } catch (error, stackTrace) {
      final failure = gattOperationFailure(error, fallbackMessage: '蓝牙写入失败。');
      _logger.info(
        '${operation}_failure',
        fields: {
          'device': _redactDeviceId(characteristic.deviceId),
          'characteristic': characteristic.characteristicUuid,
          'error': '$error',
          'pairing_required': failure.message == _pairingRequiredMessage,
        },
      );
      Error.throwWithStackTrace(BleTransportException(failure), stackTrace);
    }
  }

  @override
  Future<void> disconnect(String deviceId) async {
    _logger.info(
      'disconnect_request',
      fields: {'device': _redactDeviceId(deviceId)},
    );
    final active = _connections.remove(deviceId);
    if (active == null) {
      _logger.info(
        'disconnect_noop',
        fields: {'device': _redactDeviceId(deviceId)},
      );
      return;
    }
    await active.subscription.cancel();
    await active.controller.close();
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

  static String _redactDeviceId(String deviceId) {
    if (deviceId.length <= 4) {
      return deviceId;
    }
    return '...${deviceId.substring(deviceId.length - 4)}';
  }

  /// Android reports ATT MTU directly. On iOS the plugin reports CoreBluetooth's
  /// maximum Write Without Response value length, which excludes the ATT header.
  @visibleForTesting
  static int attMtuFromPlugin(
    int reportedMtu, {
    bool reportedAsWritePayload = false,
  }) => reportedAsWritePayload ? reportedMtu + 3 : reportedMtu;

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
    if (!requiresPermissionHandlerScanRequest(
      isAndroid: Platform.isAndroid,
      isIOS: Platform.isIOS,
    )) {
      return false;
    }

    final sdkInt = await _androidSdkIntProvider.sdkInt;
    final permissions =
        AndroidBleScanPermissionPolicy.platformPermissionsForSdkInt(sdkInt);
    final statuses = await permissions.request();
    if (statuses.values.any((status) => !status.isGranted)) {
      throw BleTransportException(
        EvtFailure.environment(
          message: sdkInt >= 31 ? '需要附近设备权限才能开始扫描。' : '需要定位权限才能开始扫描。',
        ),
      );
    }
    return AndroidBleScanPermissionPolicy.requiresLocationServicesForScan(
      sdkInt,
    );
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
}

class _ActiveConnection {
  const _ActiveConnection(this.controller, this.subscription);

  final StreamController<BleConnectionState> controller;
  final StreamSubscription<reactive.ConnectionStateUpdate> subscription;
}
