import 'dart:typed_data';

import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/diagnostics/evt_failure.dart';
import 'package:aipin/features/device_discovery/domain/device_candidate.dart';

abstract interface class BleTransport {
  Stream<DeviceCandidate> scan();
  Stream<BleConnectionState> connect(String deviceId);
  Future<List<BleService>> discoverServices(String deviceId);
  Future<int> requestMtu(String deviceId, {required int preferredMtu});
  Stream<Uint8List> subscribe(BleCharacteristic characteristic);

  /// Completes after the platform has enabled this characteristic's CCC.
  ///
  /// Receiving a stream subscription alone is insufficient on Android and iOS:
  /// the device can indicate a response before the system finishes applying
  /// the notify/indicate descriptor write.
  Future<void> awaitSubscriptionReady(BleCharacteristic characteristic);
  Future<Uint8List> read(BleCharacteristic characteristic);
  Future<void> write(BleCharacteristic characteristic, Uint8List bytes);
  Future<void> writeWithoutResponse(
    BleCharacteristic characteristic,
    Uint8List bytes,
  );
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
