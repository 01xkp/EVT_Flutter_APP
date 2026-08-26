import 'dart:typed_data';

import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/diagnostics/evt_failure.dart';
import 'package:aipin/features/device_discovery/domain/device_candidate.dart';

abstract interface class BleTransport {
  Stream<DeviceCandidate> scan();
  Stream<BleConnectionState> connect(String deviceId);
  Future<List<BleService>> discoverServices(String deviceId);
  Stream<Uint8List> subscribe(BleCharacteristic characteristic);
  Future<Uint8List> read(BleCharacteristic characteristic);
  Future<void> disconnect(String deviceId);
}

enum BleTransportIssue { bluetoothOff }

class BleTransportException implements Exception {
  const BleTransportException(this.failure, {this.issue});

  final EvtFailure failure;
  final BleTransportIssue? issue;

  @override
  String toString() => 'BleTransportException(${failure.message})';
}
