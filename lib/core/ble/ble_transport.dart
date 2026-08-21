import 'dart:typed_data';

import 'package:evt_ble_app/core/ble/ble_models.dart';
import 'package:evt_ble_app/core/diagnostics/evt_failure.dart';
import 'package:evt_ble_app/features/device_discovery/domain/device_candidate.dart';

abstract interface class BleTransport {
  Stream<DeviceCandidate> scan();
  Stream<BleConnectionState> connect(String deviceId);
  Future<List<BleService>> discoverServices(String deviceId);
  Stream<Uint8List> subscribe(BleCharacteristic characteristic);
  Future<Uint8List> read(BleCharacteristic characteristic);
  Future<void> disconnect(String deviceId);
}

class BleTransportException implements Exception {
  const BleTransportException(this.failure);

  final EvtFailure failure;

  @override
  String toString() => 'BleTransportException(${failure.message})';
}
