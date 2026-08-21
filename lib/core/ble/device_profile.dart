import 'package:evt_ble_app/core/diagnostics/evt_failure.dart';

class DeviceProfile {
  const DeviceProfile({
    required this.namePrefix,
    required this.manufacturerPrefixHex,
    required this.serviceUuid,
    required this.gattServiceUuid,
    required this.readCharacteristicUuid,
    required this.notifyCharacteristicUuid,
    required this.writeCharacteristicUuid,
  });

  factory DeviceProfile.empty() => const DeviceProfile(
        namePrefix: 'AIPIN',
        manufacturerPrefixHex: 'A389',
        serviceUuid: '0000AF30-0000-1000-8000-00805F9B34FB',
        gattServiceUuid: '',
        readCharacteristicUuid: '',
        notifyCharacteristicUuid: '',
        writeCharacteristicUuid: '',
      );

  factory DeviceProfile.fromJson(Map<String, Object?> json) {
    String stringValue(String key) => json[key] as String? ?? '';

    return DeviceProfile(
      namePrefix: stringValue('namePrefix'),
      manufacturerPrefixHex: stringValue('manufacturerPrefixHex'),
      serviceUuid: stringValue('serviceUuid'),
      gattServiceUuid: stringValue('gattServiceUuid'),
      readCharacteristicUuid: stringValue('readCharacteristicUuid'),
      notifyCharacteristicUuid: stringValue('notifyCharacteristicUuid'),
      writeCharacteristicUuid: stringValue('writeCharacteristicUuid'),
    );
  }

  final String namePrefix;
  final String manufacturerPrefixHex;
  final String serviceUuid;
  final String gattServiceUuid;
  final String readCharacteristicUuid;
  final String notifyCharacteristicUuid;
  final String writeCharacteristicUuid;

  List<int> get manufacturerPrefixBytes {
    final normalized = manufacturerPrefixHex.replaceAll(RegExp(r'\s+'), '');
    if (normalized.length.isOdd || !RegExp(r'^[0-9A-Fa-f]+$').hasMatch(normalized)) {
      return const [];
    }
    return [
      for (var index = 0; index < normalized.length; index += 2)
        int.parse(normalized.substring(index, index + 2), radix: 16),
    ];
  }

  bool get isGattReady => [
        gattServiceUuid,
        readCharacteristicUuid,
        notifyCharacteristicUuid,
        writeCharacteristicUuid,
      ].every(_isUuid);

  EvtFailure? get validationFailure => isGattReady
      ? null
      : EvtFailure.access(
          message: 'GATT 配置未完成',
          detail: '请在 assets/config/device_profile.json 填写服务和特征 UUID。',
        );

  static bool _isUuid(String value) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
  }
}
