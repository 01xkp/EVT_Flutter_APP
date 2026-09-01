import 'device_capabilities.dart';

class DeviceInfo {
  const DeviceInfo({
    required this.capabilities,
    required this.deviceCode,
    required this.softwareVersion,
    required this.hardwareVersion,
    required this.deviceName,
    required this.totalDiskSpaceMb,
    required this.remainDiskSpaceMb,
    required this.recordStatus,
    required this.batteryLevel,
    required this.charging,
    required this.audioStreamEnabled,
  });

  final DeviceCapabilities capabilities;
  final String deviceCode;
  final String softwareVersion;
  final String hardwareVersion;
  final String deviceName;
  final int totalDiskSpaceMb;
  final int remainDiskSpaceMb;
  final int recordStatus;
  final int batteryLevel;
  final int charging;
  final bool audioStreamEnabled;
}

