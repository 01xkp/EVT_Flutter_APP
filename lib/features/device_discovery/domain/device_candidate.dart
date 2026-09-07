class DeviceCandidate {
  const DeviceCandidate({
    required this.connectionId,
    required this.name,
    required this.manufacturerData,
    required this.serviceUuids,
    required this.rssi,
    required this.discoveredAt,
  });

  /// Platform-scoped identifier used exclusively for BLE operations.
  ///
  /// Android commonly reports a MAC address; iOS reports a CoreBluetooth UUID.
  final String connectionId;
  final String name;
  final List<int> manufacturerData;
  final List<String> serviceUuids;
  final int rssi;
  final DateTime discoveredAt;

  /// Stable hardware identity encoded by V1.5 in `A3 89 + BtAddressRaw[6]`.
  ///
  /// [connectionId] must only be used by the BLE transport. iOS supplies a
  /// CoreBluetooth UUID rather than a MAC.
  String? get physicalDeviceId {
    if (manufacturerData.length != 8) {
      return null;
    }
    return manufacturerData
        .sublist(2)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(':');
  }

  DeviceCandidate copyWith({
    String? connectionId,
    String? name,
    List<int>? manufacturerData,
    List<String>? serviceUuids,
    int? rssi,
    DateTime? discoveredAt,
  }) {
    return DeviceCandidate(
      connectionId: connectionId ?? this.connectionId,
      name: name ?? this.name,
      manufacturerData: manufacturerData ?? this.manufacturerData,
      serviceUuids: serviceUuids ?? this.serviceUuids,
      rssi: rssi ?? this.rssi,
      discoveredAt: discoveredAt ?? this.discoveredAt,
    );
  }
}
