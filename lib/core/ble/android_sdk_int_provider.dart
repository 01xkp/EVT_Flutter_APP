import 'dart:io';

import 'package:flutter/services.dart';

abstract interface class AndroidSdkIntProvider {
  Future<int> get sdkInt;
}

class PlatformAndroidSdkIntProvider implements AndroidSdkIntProvider {
  const PlatformAndroidSdkIntProvider();

  static const _channel = MethodChannel('com.aigutta.aipin/bluetooth');

  @override
  Future<int> get sdkInt async {
    if (!Platform.isAndroid) {
      throw StateError('Android SDK version is unavailable on this platform.');
    }
    final value = await _channel.invokeMethod<int>('androidSdkInt');
    if (value == null || value < 1) {
      throw StateError('Android SDK version is unavailable.');
    }
    return value;
  }
}
