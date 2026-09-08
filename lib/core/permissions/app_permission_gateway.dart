enum AppPermissionState { granted, denied, permanentlyDenied, unavailable }

abstract interface class AppPermissionGateway {
  Future<AppPermissionState> nearbyDevices();

  Future<bool> openSettings();
}
