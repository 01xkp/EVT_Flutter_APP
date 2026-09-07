class DeviceConfiguration {
  const DeviceConfiguration({
    required this.systemTime,
    required this.recordDurationSeconds,
    required this.recordMode,
    required this.recordType,
    required this.denoise,
    required this.powerOff,
    required this.chargingMode,
    required this.audioStreamEnabled,
  });

  final DateTime systemTime;
  final int recordDurationSeconds;
  final int recordMode;
  final int recordType;
  final bool denoise;
  final int powerOff;
  final int chargingMode;
  final bool audioStreamEnabled;

  DeviceConfiguration copyWith({
    DateTime? systemTime,
    int? recordDurationSeconds,
    int? recordMode,
    int? recordType,
    bool? denoise,
    int? powerOff,
    int? chargingMode,
    bool? audioStreamEnabled,
  }) => DeviceConfiguration(
    systemTime: systemTime ?? this.systemTime,
    recordDurationSeconds: recordDurationSeconds ?? this.recordDurationSeconds,
    recordMode: recordMode ?? this.recordMode,
    recordType: recordType ?? this.recordType,
    denoise: denoise ?? this.denoise,
    powerOff: powerOff ?? this.powerOff,
    chargingMode: chargingMode ?? this.chargingMode,
    audioStreamEnabled: audioStreamEnabled ?? this.audioStreamEnabled,
  );
}

class DeviceStatus {
  const DeviceStatus({
    required this.privacy,
    required this.privacyRemainingMinutes,
    required this.recordConsent,
    required this.syncState,
  });

  final bool privacy;
  final int privacyRemainingMinutes;
  final bool recordConsent;
  final int syncState;
}

class DeviceBattery {
  const DeviceBattery({
    required this.percent,
    required this.isCharging,
    required this.chargingMode,
  });

  final int percent;
  final bool isCharging;
  final int chargingMode;
}

class DeviceStorage {
  const DeviceStorage({
    required this.totalMegabytes,
    required this.freeMegabytes,
  });

  final int totalMegabytes;
  final int freeMegabytes;
}
