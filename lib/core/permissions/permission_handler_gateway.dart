import 'dart:io';

import 'package:aipin/core/ble/android_ble_scan_permission_policy.dart';
import 'package:aipin/core/ble/android_sdk_int_provider.dart';
import 'package:aipin/core/permissions/app_permission_gateway.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart' as reactive;
import 'package:permission_handler/permission_handler.dart';

class PermissionHandlerGateway implements AppPermissionGateway {
  PermissionHandlerGateway({AndroidSdkIntProvider? androidSdkIntProvider})
    : _androidSdkIntProvider =
          androidSdkIntProvider ?? const PlatformAndroidSdkIntProvider();

  final AndroidSdkIntProvider _androidSdkIntProvider;
  reactive.FlutterReactiveBle? _ble;

  reactive.FlutterReactiveBle get _reactiveBle =>
      _ble ??= reactive.FlutterReactiveBle();

  @override
  Future<AppPermissionState> nearbyDevices() async {
    if (Platform.isIOS) {
      try {
        final status = await _reactiveBle.statusStream
            .firstWhere((status) => status != reactive.BleStatus.unknown)
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () => reactive.BleStatus.unknown,
            );
        return nearbyDevicesStateForIosBleStatus(status);
      } catch (_) {
        return AppPermissionState.unavailable;
      }
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

  /// CoreBluetooth includes both authorization and adapter availability in its
  /// state. A disabled adapter does not revoke the app's Bluetooth permission.
  @visibleForTesting
  static AppPermissionState nearbyDevicesStateForIosBleStatus(
    reactive.BleStatus status,
  ) => switch (status) {
    reactive.BleStatus.ready ||
    reactive.BleStatus.poweredOff => AppPermissionState.granted,
    reactive.BleStatus.unauthorized => AppPermissionState.permanentlyDenied,
    reactive.BleStatus.unsupported ||
    reactive.BleStatus.unknown => AppPermissionState.unavailable,
    reactive.BleStatus.locationServicesDisabled => AppPermissionState.granted,
  };

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
