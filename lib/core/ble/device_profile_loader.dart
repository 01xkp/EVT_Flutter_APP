import 'dart:convert';

import 'package:aipin/core/ble/device_profile.dart';
import 'package:flutter/services.dart';

class DeviceProfileLoader {
  const DeviceProfileLoader({this.assetPath = defaultAssetPath});

  static const defaultAssetPath = 'assets/config/device_profile.json';

  final String assetPath;

  Future<DeviceProfile> load(AssetBundle bundle) async {
    final decoded = jsonDecode(await bundle.loadString(assetPath));
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('设备 Profile 必须是 JSON 对象。');
    }
    return DeviceProfile.fromJson(decoded);
  }
}
