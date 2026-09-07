import 'package:aipin/core/ble/android_ble_scan_permission_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses location permission for Android API 23 through 30 scanning', () {
    expect(AndroidBleScanPermissionPolicy.forSdkInt(23), const [
      AndroidBleScanPermission.locationWhenInUse,
    ]);
    expect(AndroidBleScanPermissionPolicy.forSdkInt(30), const [
      AndroidBleScanPermission.locationWhenInUse,
    ]);
  });

  test('uses nearby-device permissions from Android API 31 onward', () {
    expect(AndroidBleScanPermissionPolicy.forSdkInt(31), const [
      AndroidBleScanPermission.bluetoothScan,
      AndroidBleScanPermission.bluetoothConnect,
    ]);
    expect(AndroidBleScanPermissionPolicy.forSdkInt(35), const [
      AndroidBleScanPermission.bluetoothScan,
      AndroidBleScanPermission.bluetoothConnect,
    ]);
  });

  test(
    'requires enabled system location services only on Android API 23 to 30',
    () {
      expect(
        AndroidBleScanPermissionPolicy.requiresLocationServicesForScan(22),
        isFalse,
      );
      expect(
        AndroidBleScanPermissionPolicy.requiresLocationServicesForScan(23),
        isTrue,
      );
      expect(
        AndroidBleScanPermissionPolicy.requiresLocationServicesForScan(30),
        isTrue,
      );
      expect(
        AndroidBleScanPermissionPolicy.requiresLocationServicesForScan(31),
        isFalse,
      );
    },
  );
}
