import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/ble/ble_transport.dart';
import 'package:aipin/core/diagnostics/evt_failure.dart';
import 'package:aipin/features/device_discovery/domain/device_candidate.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart' as reactive;
import 'package:permission_handler/permission_handler.dart';

class ReactiveBleTransport implements BleTransport {
  ReactiveBleTransport({reactive.FlutterReactiveBle? ble}) : _client = ble;

  reactive.FlutterReactiveBle? _client;
  final Map<String, _ActiveConnection> _connections = {};

  reactive.FlutterReactiveBle get _ble =>
      _client ??= reactive.FlutterReactiveBle();

  @override
  Stream<DeviceCandidate> scan() async* {
    try {
      await _ensureScanPermission();
      final status = await _ble.statusStream.firstWhere(
        (status) => status != reactive.BleStatus.unknown,
      );
      if (status == reactive.BleStatus.poweredOff) {
        throw BleTransportException(
          EvtFailure.environment(message: '蓝牙未开启。'),
          issue: BleTransportIssue.bluetoothOff,
        );
      }
      await for (final device in _ble.scanForDevices(
        withServices: const [],
        scanMode: reactive.ScanMode.lowLatency,
        requireLocationServicesEnabled: false,
      )) {
        yield DeviceCandidate(
          id: device.id,
          name: device.name,
          manufacturerData: List.unmodifiable(device.manufacturerData),
          serviceUuids: List.unmodifiable(
            device.serviceUuids.map((uuid) => uuid.toString()),
          ),
          rssi: device.rssi,
          discoveredAt: DateTime.now(),
        );
      }
    } on BleTransportException {
      rethrow;
    } catch (error, stackTrace) {
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
    final existing = _connections[deviceId];
    if (existing != null) {
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
            controller.addError(
              BleTransportException(
                EvtFailure.transport(message: '蓝牙连接异常。', detail: '$error'),
              ),
              stackTrace,
            );
          },
          onDone: () {
            _finishConnection(deviceId, controller);
          },
        );
    _connections[deviceId] = _ActiveConnection(controller, subscription);
    return controller.stream;
  }

  @override
  Future<List<BleService>> discoverServices(String deviceId) async {
    try {
      await _ble.discoverAllServices(deviceId);
      final services = await _ble.getDiscoveredServices(deviceId);
      return List.unmodifiable(
        services.map(
          (service) => BleService(
            uuid: service.id.toString(),
            characteristicUuids: List.unmodifiable(
              service.characteristics.map(
                (characteristic) => characteristic.id.toString(),
              ),
            ),
          ),
        ),
      );
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        BleTransportException(
          EvtFailure.transport(message: '服务发现失败。', detail: '$error'),
        ),
        stackTrace,
      );
    }
  }

  @override
  Stream<Uint8List> subscribe(BleCharacteristic characteristic) async* {
    try {
      await for (final bytes in _ble.subscribeToCharacteristic(
        _qualifiedCharacteristic(characteristic),
      )) {
        yield Uint8List.fromList(bytes);
      }
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        BleTransportException(
          EvtFailure.transport(message: '状态订阅失败。', detail: '$error'),
        ),
        stackTrace,
      );
    }
  }

  @override
  Future<Uint8List> read(BleCharacteristic characteristic) async {
    try {
      return Uint8List.fromList(
        await _ble.readCharacteristic(_qualifiedCharacteristic(characteristic)),
      );
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        BleTransportException(
          EvtFailure.transport(message: '状态读取失败。', detail: '$error'),
        ),
        stackTrace,
      );
    }
  }

  @override
  Future<void> disconnect(String deviceId) async {
    final active = _connections.remove(deviceId);
    if (active == null) {
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

  Future<void> _ensureScanPermission() async {
    if (Platform.isAndroid) {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();
      if (statuses.values.any((status) => !status.isGranted)) {
        throw BleTransportException(
          EvtFailure.environment(message: '需要蓝牙扫描和连接权限才能开始联调。'),
        );
      }
      return;
    }
    if (Platform.isIOS) {
      final status = await Permission.bluetooth.request();
      if (!status.isGranted) {
        throw BleTransportException(
          EvtFailure.environment(message: '需要蓝牙权限才能开始联调。'),
        );
      }
    }
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
