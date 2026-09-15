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
    required this.powerOff,
    required this.chargingMode,
    this.reservedFeatureStatus = 0,
    this.audioStream = 0,
    this.recordDurationSeconds,
    this.currentDurationSeconds,
    this.recordMode,
    this.recordType,
    this.denoise,
    this.errorCode,
    this.isRedacted = false,
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
  final int powerOff;
  final int chargingMode;

  /// ReservedFeatureStatus from the 0x81 response. A non-zero value means a
  /// 30-byte compatibility area was present before RecordStatus.
  final int reservedFeatureStatus;

  /// AudioStream is retained even though the EVT build does not expose the
  /// FA18 real-time audio capability. This keeps the 0x01 response lossless.
  final int audioStream;

  /// Conditional recording fields. They are present only for RecordStatus 1
  /// (recording) or 2 (paused), and remain null for stopped/error states.
  final int? recordDurationSeconds;
  final int? currentDurationSeconds;
  final int? recordMode;
  final int? recordType;
  final int? denoise;

  /// Reserved for a future device-information error field. V1.6 0x81 ERROR
  /// state is one byte and does not carry an ErrorCode; 0x87 error indications
  /// are validated separately and are not represented by this model.
  final int? errorCode;

  /// True only for the fixed 90-byte pre-authentication 0x81 response. Its
  /// capacity, battery and state fields are placeholders and must not be
  /// copied into the live device snapshot.
  final bool isRedacted;
}
