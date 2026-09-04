import 'package:aipin/features/device_discovery/domain/device_candidate.dart';

class RememberedDevice {
  RememberedDevice({
    required String connectionId,
    String? physicalMacAddress,
    required String displayName,
    required DateTime lastConnectedAt,
  }) : connectionId = _normalizeConnectionId(connectionId),
       physicalMacAddress = _normalizePhysicalMacAddress(physicalMacAddress),
       displayName = _normalizeDisplayName(displayName),
       lastConnectedAt = lastConnectedAt.toUtc();

  static const maxDisplayNameLength = 80;
  static final RegExp _macAddressPattern = RegExp(
    r'^(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$',
  );

  /// Identifier used by the current platform's BLE transport.
  ///
  /// On Android this is commonly a MAC address. On iOS it is a CoreBluetooth
  /// UUID and must not be treated as a MAC address.
  final String connectionId;

  /// Optional Bluetooth address supplied by the V1.5 manufacturer broadcast.
  final String? physicalMacAddress;

  /// Last user-visible device name, bounded for private local storage.
  final String displayName;

  /// UTC time of the last session that reached authentication readiness.
  final DateTime lastConnectedAt;

  bool matches(DeviceCandidate candidate) {
    final candidateMacAddress = _hasV15PhysicalMacAddress(candidate)
        ? candidate.physicalDeviceId
        : null;
    if (physicalMacAddress != null && candidateMacAddress != null) {
      return physicalMacAddress ==
          _normalizePhysicalMacAddress(candidateMacAddress);
    }
    return connectionId == candidate.connectionId;
  }

  static bool _hasV15PhysicalMacAddress(DeviceCandidate candidate) {
    final manufacturerData = candidate.manufacturerData;
    return manufacturerData.length == 8 &&
        manufacturerData[0] == 0xA3 &&
        manufacturerData[1] == 0x89;
  }

  static String normalizeConnectionId(String value) {
    return _normalizeConnectionId(value);
  }

  static String? normalizePhysicalMacAddress(String? value) {
    return _normalizePhysicalMacAddress(value);
  }

  static String _normalizeConnectionId(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw const FormatException('设备连接标识不能为空。');
    }
    return normalized;
  }

  static String? _normalizePhysicalMacAddress(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('设备物理蓝牙地址格式无效。');
    }
    if (!_macAddressPattern.hasMatch(trimmed)) {
      throw const FormatException('设备物理蓝牙地址格式无效。');
    }
    return trimmed
        .split(RegExp('[:-]'))
        .map((byte) => byte.toUpperCase())
        .join(':');
  }

  static String _normalizeDisplayName(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw const FormatException('设备名称不能为空。');
    }
    if (normalized.length <= maxDisplayNameLength) {
      return normalized;
    }
    return normalized.substring(0, maxDisplayNameLength);
  }
}
