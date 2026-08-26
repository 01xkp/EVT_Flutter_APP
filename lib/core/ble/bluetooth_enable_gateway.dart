import 'dart:io';

import 'package:flutter/services.dart';

enum BluetoothEnableResult { enabled, cancelled, unavailable }

abstract interface class BluetoothEnableGateway {
  bool get canRequestEnable;

  Future<BluetoothEnableResult> requestEnable();
}

class PlatformBluetoothEnableGateway implements BluetoothEnableGateway {
  const PlatformBluetoothEnableGateway();

  static const _channel = MethodChannel('com.aigutta.aipin/bluetooth');

  @override
  bool get canRequestEnable => Platform.isAndroid;

  @override
  Future<BluetoothEnableResult> requestEnable() async {
    if (!canRequestEnable) {
      return BluetoothEnableResult.unavailable;
    }
    try {
      final result = await _channel.invokeMethod<String>('requestEnable');
      return switch (result) {
        'enabled' => BluetoothEnableResult.enabled,
        'cancelled' => BluetoothEnableResult.cancelled,
        _ => BluetoothEnableResult.unavailable,
      };
    } on PlatformException {
      return BluetoothEnableResult.unavailable;
    }
  }
}
