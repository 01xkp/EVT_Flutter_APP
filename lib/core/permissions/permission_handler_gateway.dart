import 'dart:io';

import 'package:aipin/core/ble/android_ble_scan_permission_policy.dart';
import 'package:aipin/core/ble/android_sdk_int_provider.dart';
import 'package:aipin/core/permissions/app_permission_gateway.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionHandlerGateway implements AppPermissionGateway {
  PermissionHandlerGateway({AndroidSdkIntProvider? androidSdkIntProvider})
    : _androidSdkIntProvider =
          androidSdkIntProvider ?? const PlatformAndroidSdkIntProvider();

  final AndroidSdkIntProvider _androidSdkIntProvider;

  @override
  Future<AppPermissionState> nearbyDevices() async {
    if (Platform.isIOS) {
      return _map(await Permission.bluetooth.status);
    }
    if (Platform.isAndroid) {
      final permissions =
          AndroidBleScanPermissionPolicy.platformPermissionsForSdkInt(
            await _androidSdkIntProvider.sdkInt,
          );
      final statuses = await Future.wait(
        permissions.map((permission) => permission.status),
      );
      return _mapAll(statuses);
    }
    return _map(await Permission.bluetoothScan.status);
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

  AppPermissionState _mapAll(List<PermissionStatus> statuses) {
    if (statuses.every((status) => status.isGranted)) {
      return AppPermissionState.granted;
    }
    if (statuses.any((status) => status.isPermanentlyDenied)) {
      return AppPermissionState.permanentlyDenied;
    }
    if (statuses.any((status) => status.isRestricted)) {
      return AppPermissionState.unavailable;
    }
    return AppPermissionState.denied;
  }
}
