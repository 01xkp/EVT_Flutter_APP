enum DevicePermission {
  status(1 << 0),
  configuration(1 << 1),
  files(1 << 2);

  const DevicePermission(this.bit);

  final int bit;
}

/// Supplies the currently valid device permissions for one BLE session.
///
/// The EVT V1 authentication window is time-limited. Keeping this boundary at
/// the session layer prevents an already-open page from issuing a BLE command
/// after that window has expired.
abstract interface class DevicePermissionGate {
  bool allows(DevicePermission permission);
}
