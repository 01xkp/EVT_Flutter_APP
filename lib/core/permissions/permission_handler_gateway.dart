import 'dart:io';

import 'package:evt_ble_app/core/permissions/app_permission_gateway.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionHandlerGateway implements AppPermissionGateway {
  @override
  Future<AppPermissionState> nearbyDevices() async {
    final status = await (Platform.isIOS
        ? Permission.bluetooth.status
        : Permission.bluetoothScan.status);
    return _map(status);
  }

  @override
  Future<AppPermissionState> microphone() async =>
      _map(await Permission.microphone.status);

  @override
  Future<bool> openSettings() => openAppSettings();

  AppPermissionState _map(PermissionStatus status) => switch (status) {
    PermissionStatus.granted ||
    PermissionStatus.limited => AppPermissionState.granted,
    PermissionStatus.permanentlyDenied => AppPermissionState.permanentlyDenied,
    PermissionStatus.restricted => AppPermissionState.unavailable,
    _ => AppPermissionState.denied,
  };
}
