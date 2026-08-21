class DeviceCandidate {
  const DeviceCandidate({
    required this.id,
    required this.name,
    required this.manufacturerData,
    required this.serviceUuids,
    required this.rssi,
    required this.discoveredAt,
  });

  final String id;
  final String name;
  final List<int> manufacturerData;
  final List<String> serviceUuids;
  final int rssi;
  final DateTime discoveredAt;

  DeviceCandidate copyWith({
    String? id,
    String? name,
    List<int>? manufacturerData,
    List<String>? serviceUuids,
    int? rssi,
    DateTime? discoveredAt,
  }) {
    return DeviceCandidate(
      id: id ?? this.id,
      name: name ?? this.name,
      manufacturerData: manufacturerData ?? this.manufacturerData,
      serviceUuids: serviceUuids ?? this.serviceUuids,
      rssi: rssi ?? this.rssi,
      discoveredAt: discoveredAt ?? this.discoveredAt,
    );
  }
}
