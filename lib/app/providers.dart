import 'package:evt_ble_app/core/ble/ble_transport.dart';
import 'package:evt_ble_app/core/ble/reactive_ble_transport.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final bleTransportProvider = Provider<BleTransport>((ref) {
  return ReactiveBleTransport();
});
