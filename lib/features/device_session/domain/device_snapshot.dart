enum DeviceState {
  factoryMode,
  ship,
  unbound,
  standby,
  recording,
  paused,
  privacy,
  ota,
  safeOff,
  charging,
  unknown,
}

class DeviceSnapshot {
  const DeviceSnapshot({
    required this.state,
    required this.observedAt,
    required this.source,
    this.batteryPercent,
    this.isCharging,
    this.standbyPowerMilliwatts,
  });

  final DeviceState state;
  final DateTime observedAt;
  final String source;
  final int? batteryPercent;
  final bool? isCharging;
  final double? standbyPowerMilliwatts;
}
