import 'package:permission_handler/permission_handler.dart';

enum AndroidBleScanPermission {
  locationWhenInUse,
  bluetoothScan,
  bluetoothConnect,
}

class AndroidBleScanPermissionPolicy {
  const AndroidBleScanPermissionPolicy._();

  static List<AndroidBleScanPermission> forSdkInt(int sdkInt) {
    if (sdkInt < 23) {
      return const [];
    }
    if (sdkInt < 31) {
      return const [AndroidBleScanPermission.locationWhenInUse];
    }
    return const [
      AndroidBleScanPermission.bluetoothScan,
      AndroidBleScanPermission.bluetoothConnect,
    ];
  }

  /// Android 6 through 11 require both location permission and an enabled
  /// system location service before BLE scan results can be delivered.
  static bool requiresLocationServicesForScan(int sdkInt) =>
      sdkInt >= 23 && sdkInt < 31;

  static List<Permission> platformPermissionsForSdkInt(int sdkInt) => [
    for (final requirement in forSdkInt(sdkInt))
      switch (requirement) {
        AndroidBleScanPermission.locationWhenInUse =>
          Permission.locationWhenInUse,
        AndroidBleScanPermission.bluetoothScan => Permission.bluetoothScan,
        AndroidBleScanPermission.bluetoothConnect =>
          Permission.bluetoothConnect,
      },
  ];
}
