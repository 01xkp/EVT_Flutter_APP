import 'dart:io';

import 'package:aipin/core/ble/android_ble_scan_permission_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Android 12+ manifest supports the nearby-only runtime permission policy',
    () {
      final permissions = AndroidBleScanPermissionPolicy.forSdkInt(31);
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync().replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
      final scanDeclaration = RegExp(r'<uses-permission\s[^>]*>')
          .allMatches(manifest)
          .map((match) => match.group(0)!)
          .singleWhere(
            (element) =>
                element.contains('"android.permission.BLUETOOTH_SCAN"'),
          );

      // Without this flag RxAndroidBle also requires fine location on API 31+,
      // which the nearby-only policy does not request. Test the native/Dart
      // contract together so a manifest-only change cannot silently break scans.
      final flags =
          RegExp(
            r'android:usesPermissionFlags="([^"]*)"',
          ).firstMatch(scanDeclaration)?.group(1)?.split('|') ??
          const <String>[];
      final requiredByNativeScanner = {
        AndroidBleScanPermission.bluetoothScan,
        AndroidBleScanPermission.bluetoothConnect,
        if (!flags.contains('neverForLocation'))
          AndroidBleScanPermission.locationWhenInUse,
      };
      expect(
        requiredByNativeScanner.difference(permissions.toSet()),
        isEmpty,
        reason:
            'All permissions required by the Android scanner must be requested before scanning.',
      );
    },
  );

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
