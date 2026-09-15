enum DevicePermission {
  status(1 << 0),
  configuration(1 << 1),
  files(1 << 2);

  const DevicePermission(this.bit);

  final int bit;
}

/// Supplies the currently valid device permissions for one BLE session.
///
/// In EVT V1.6 the 60-second limit is the firmware deadline for completing
/// AUTH after a connection is established. Once AUTH succeeds, permissions
/// remain valid for that BLE connection and are revoked on disconnect/restart.
abstract interface class DevicePermissionGate {
  bool allows(DevicePermission permission);
}
