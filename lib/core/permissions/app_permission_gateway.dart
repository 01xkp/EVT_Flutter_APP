enum AppPermissionState { granted, denied, permanentlyDenied, unavailable }

abstract interface class AppPermissionGateway {
  Future<AppPermissionState> nearbyDevices();

  Future<AppPermissionState> microphone();

  Future<bool> openSettings();
}
