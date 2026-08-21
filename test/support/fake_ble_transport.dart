import 'dart:async';
import 'dart:typed_data';

import 'package:evt_ble_app/core/ble/ble_models.dart';
import 'package:evt_ble_app/core/ble/ble_transport.dart';
import 'package:evt_ble_app/features/device_discovery/domain/device_candidate.dart';

class FakeBleTransport implements BleTransport {
  FakeBleTransport();

  static final matchingCandidate = DeviceCandidate(
    id: '71:BF:E2:3B:84:23',
    name: 'AIPIN_8423',
    manufacturerData: const [0xA3, 0x89, 0x71, 0xBF, 0xE2, 0x3B, 0x84, 0x23],
    serviceUuids: const ['0000AF30-0000-1000-8000-00805F9B34FB'],
    rssi: -48,
    discoveredAt: DateTime(2026, 8, 21),
  );

  static final weakMatchingCandidate = matchingCandidate.copyWith(rssi: -76);

  final _scanController = StreamController<DeviceCandidate>.broadcast();
  final _connectionController = StreamController<BleConnectionState>.broadcast();
  final _subscriptionController = StreamController<Uint8List>.broadcast();
  final disconnectedDeviceIds = <String>[];
  List<BleService> services = const [];
  Uint8List readValue = Uint8List(0);

  void emitCandidate(DeviceCandidate candidate) => _scanController.add(candidate);

  void emitConnection(BleConnectionState state) => _connectionController.add(state);

  void emitSubscriptionBytes(List<int> bytes) {
    _subscriptionController.add(Uint8List.fromList(bytes));
  }

  @override
  Stream<DeviceCandidate> scan() => _scanController.stream;

  @override
  Stream<BleConnectionState> connect(String deviceId) => _connectionController.stream;

  @override
  Future<List<BleService>> discoverServices(String deviceId) async => services;

  @override
  Stream<Uint8List> subscribe(BleCharacteristic characteristic) =>
      _subscriptionController.stream;

  @override
  Future<Uint8List> read(BleCharacteristic characteristic) async => readValue;

  @override
  Future<void> disconnect(String deviceId) async {
    disconnectedDeviceIds.add(deviceId);
  }

  Future<void> dispose() async {
    await _scanController.close();
    await _connectionController.close();
    await _subscriptionController.close();
  }
}
