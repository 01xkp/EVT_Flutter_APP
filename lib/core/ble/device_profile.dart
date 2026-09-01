import 'package:aipin/core/diagnostics/evt_failure.dart';
import 'package:aipin/core/ble/ble_models.dart';

class DeviceProfile {
  const DeviceProfile({
    required this.namePrefix,
    required this.manufacturerPrefixHex,
    required this.serviceUuid,
    required this.gattServiceUuid,
    required this.readCharacteristicUuid,
    required this.notifyCharacteristicUuid,
    required this.writeCharacteristicUuid,
    this.readServiceUuid,
    this.notifyServiceUuid,
    this.writeServiceUuid,
    this.endpoints = const {},
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
    String uuidValue(String key) => normalizeBleUuid(stringValue(key));
    final endpoints = <BleLogicalEndpoint, BleEndpoint>{};
    final endpointJson = json['endpoints'];
    if (endpointJson is Map) {
      for (final serviceEntry in endpointJson.entries) {
        if (serviceEntry.value is! Map) continue;
        final service = serviceEntry.key.toString().toLowerCase();
        for (final characteristicEntry in (serviceEntry.value as Map).entries) {
          final key = _logicalEndpoint('$service${characteristicEntry.key}');
          if (key == null || characteristicEntry.value is! Map) continue;
          final value = characteristicEntry.value as Map;
          endpoints[key] = BleEndpoint(
            serviceUuid: normalizeBleUuid(value['serviceUuid'] as String? ?? service),
            characteristicUuid: normalizeBleUuid(value['uuid'] as String? ?? ''),
            operations: {
              for (final operation in (value['operations'] as List? ?? const []))
                ..._parseOperation(operation.toString()),
            },
          );
        }
      }
    }

    return DeviceProfile(
      namePrefix: stringValue('namePrefix'),
      manufacturerPrefixHex: stringValue('manufacturerPrefixHex'),
      serviceUuid: uuidValue('serviceUuid'),
      gattServiceUuid: uuidValue('gattServiceUuid'),
      readCharacteristicUuid: uuidValue('readCharacteristicUuid'),
      notifyCharacteristicUuid: uuidValue('notifyCharacteristicUuid'),
      writeCharacteristicUuid: uuidValue('writeCharacteristicUuid'),
      readServiceUuid: uuidValue('readServiceUuid'),
      notifyServiceUuid: uuidValue('notifyServiceUuid'),
      writeServiceUuid: uuidValue('writeServiceUuid'),
      endpoints: endpoints,
    );
  }

  final String namePrefix;
  final String manufacturerPrefixHex;
  final String serviceUuid;
  final String gattServiceUuid;
  final String readCharacteristicUuid;
  final String notifyCharacteristicUuid;
  final String writeCharacteristicUuid;
  final String? readServiceUuid;
  final String? notifyServiceUuid;
  final String? writeServiceUuid;
  final Map<BleLogicalEndpoint, BleEndpoint> endpoints;

  BleEndpoint endpoint(BleLogicalEndpoint key) => endpoints[key] ??
      (throw StateError('BLE endpoint is not configured: $key'));

  bool canOperate(BleLogicalEndpoint key, BleOperation operation) =>
      endpoints[key]?.operations.contains(operation) ?? false;

  BleEndpoint get readEndpoint => BleEndpoint(
    serviceUuid: _endpointService(readServiceUuid),
    characteristicUuid: readCharacteristicUuid,
  );

  BleEndpoint get notifyEndpoint => BleEndpoint(
    serviceUuid: _endpointService(notifyServiceUuid),
    characteristicUuid: notifyCharacteristicUuid,
  );

  BleEndpoint get writeEndpoint => BleEndpoint(
    serviceUuid: _endpointService(writeServiceUuid),
    characteristicUuid: writeCharacteristicUuid,
  );

  List<int> get manufacturerPrefixBytes {
    final normalized = manufacturerPrefixHex.replaceAll(RegExp(r'\s+'), '');
    if (normalized.length.isOdd ||
        !RegExp(r'^[0-9A-Fa-f]+$').hasMatch(normalized)) {
      return const [];
    }
    return [
      for (var index = 0; index < normalized.length; index += 2)
        int.parse(normalized.substring(index, index + 2), radix: 16),
    ];
  }

  bool get isGattReady => [
    gattServiceUuid,
    _endpointService(readServiceUuid),
    _endpointService(notifyServiceUuid),
    _endpointService(writeServiceUuid),
    readCharacteristicUuid,
    notifyCharacteristicUuid,
    writeCharacteristicUuid,
  ].every(_isUuid) && endpoints.values.every(
    (endpoint) => _isUuid(endpoint.serviceUuid) &&
        _isUuid(endpoint.characteristicUuid) && endpoint.operations.isNotEmpty,
  );

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

  String _endpointService(String? value) {
    return value != null && value.isNotEmpty ? value : gattServiceUuid;
  }
}

class BleEndpoint {
  const BleEndpoint({
    required this.serviceUuid,
    required this.characteristicUuid,
    this.operations = const {},
  });

  final String serviceUuid;
  final String characteristicUuid;
  final Set<BleOperation> operations;
}

String normalizeBleUuid(String value) {
  final normalized = value.trim().toUpperCase();
  return RegExp(r'^[0-9A-F]{4}$').hasMatch(normalized)
      ? '0000$normalized-0000-1000-8000-00805F9B34FB'
      : normalized;
}

BleLogicalEndpoint? _logicalEndpoint(String value) {
  final normalized = value.toLowerCase().replaceAll('_', '');
  for (final endpoint in BleLogicalEndpoint.values) {
    if (endpoint.name.toLowerCase() == normalized) return endpoint;
  }
  return null;
}

Set<BleOperation> _parseOperation(String value) => {
  for (final operation in BleOperation.values)
    if (operation.name.toLowerCase() == value.toLowerCase()) operation,
};
