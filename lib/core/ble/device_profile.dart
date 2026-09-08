import 'package:aipin/core/diagnostics/evt_failure.dart';
import 'package:aipin/core/ble/ble_models.dart';

class DeviceProfile {
  static const _evtV15NamePrefix = 'AIPIN';
  static const _evtV15ManufacturerPrefix = <int>[0xA3, 0x89];
  static const _evtV15AdvertisementServiceUuid =
      '0000AF30-0000-1000-8000-00805F9B34FB';
  static const _evtV15Fa10ServiceUuid = '0000FA10-1212-EFDE-1523-785FEABCD123';
  static const _evtV15Fb10ServiceUuid = '0000FB10-1212-EFDE-1523-785FEABCD123';
  static const _evtV15Ff10ServiceUuid = '0000FF10-1212-EFDE-1523-785FEABCD123';

  /// The endpoints that every EVT V1.5 peripheral must expose.
  ///
  /// This intentionally lives in the BLE profile layer instead of importing
  /// the protocol contract, so the configuration is validated before a
  /// session or protocol client exists.
  ///
  /// `FF11 / 0x21` is intentionally absent here. The V1.5 protocol calls it a
  /// compatibility-only file-count summary; file listing through `FF12 / 0x22`
  /// remains the required sync path.
  static const evtV15RequiredEndpointOperations =
      <BleLogicalEndpoint, Set<BleOperation>>{
        BleLogicalEndpoint.fa10Fa11: <BleOperation>{
          BleOperation.write,
          BleOperation.indicate,
        },
        BleLogicalEndpoint.fa10Fa12: <BleOperation>{
          BleOperation.read,
          BleOperation.write,
          BleOperation.indicate,
        },
        BleLogicalEndpoint.fa10Fa15: <BleOperation>{
          BleOperation.read,
          BleOperation.indicate,
        },
        BleLogicalEndpoint.fa10Fa16: <BleOperation>{
          BleOperation.write,
          BleOperation.indicate,
        },
        BleLogicalEndpoint.fa10Fa17: <BleOperation>{
          BleOperation.write,
          BleOperation.indicate,
        },
        BleLogicalEndpoint.fa10Fa19: <BleOperation>{
          BleOperation.write,
          BleOperation.indicate,
        },
        BleLogicalEndpoint.fb10Fb11: <BleOperation>{
          BleOperation.read,
          BleOperation.indicate,
        },
        BleLogicalEndpoint.ff10Ff12: <BleOperation>{
          BleOperation.write,
          BleOperation.indicate,
        },
        BleLogicalEndpoint.ff10Ff13: <BleOperation>{
          BleOperation.write,
          BleOperation.notify,
        },
      };

  /// Optional backwards-compatible capabilities declared by EVT V1.5.
  static const evtV15OptionalEndpointOperations =
      <BleLogicalEndpoint, Set<BleOperation>>{
        BleLogicalEndpoint.ff10Ff11: <BleOperation>{
          BleOperation.read,
          BleOperation.indicate,
        },
      };

  /// Every endpoint understood by this EVT build, including optional ones.
  ///
  /// This map validates the bundled profile and rejects later-stage UUIDs. It
  /// is not the real-device admission gate; use
  /// [evtV15RequiredEndpointOperations] for that purpose.
  static const evtV15EndpointOperations =
      <BleLogicalEndpoint, Set<BleOperation>>{
        ...evtV15RequiredEndpointOperations,
        ...evtV15OptionalEndpointOperations,
      };

  /// Exact service/characteristic identities defined by the V1.5 EVT table.
  ///
  /// The profile is bundled with this build rather than supplied by a user at
  /// runtime, so accepting a merely well-formed but different UUID would hide
  /// a packaging or protocol-drift error until a command is sent to hardware.
  static const evtV15EndpointIdentities = <BleLogicalEndpoint, BleEndpoint>{
    BleLogicalEndpoint.fa10Fa11: BleEndpoint(
      serviceUuid: _evtV15Fa10ServiceUuid,
      characteristicUuid: '0000FA11-1212-EFDE-1523-785FEABCD123',
    ),
    BleLogicalEndpoint.fa10Fa12: BleEndpoint(
      serviceUuid: _evtV15Fa10ServiceUuid,
      characteristicUuid: '0000FA12-1212-EFDE-1523-785FEABCD123',
    ),
    BleLogicalEndpoint.fa10Fa15: BleEndpoint(
      serviceUuid: _evtV15Fa10ServiceUuid,
      characteristicUuid: '0000FA15-1212-EFDE-1523-785FEABCD123',
    ),
    BleLogicalEndpoint.fa10Fa16: BleEndpoint(
      serviceUuid: _evtV15Fa10ServiceUuid,
      characteristicUuid: '0000FA16-1212-EFDE-1523-785FEABCD123',
    ),
    BleLogicalEndpoint.fa10Fa17: BleEndpoint(
      serviceUuid: _evtV15Fa10ServiceUuid,
      characteristicUuid: '0000FA17-1212-EFDE-1523-785FEABCD123',
    ),
    BleLogicalEndpoint.fa10Fa19: BleEndpoint(
      serviceUuid: _evtV15Fa10ServiceUuid,
      characteristicUuid: '0000FA19-1212-EFDE-1523-785FEABCD123',
    ),
    BleLogicalEndpoint.fb10Fb11: BleEndpoint(
      serviceUuid: _evtV15Fb10ServiceUuid,
      characteristicUuid: '0000FB11-1212-EFDE-1523-785FEABCD123',
    ),
    BleLogicalEndpoint.ff10Ff11: BleEndpoint(
      serviceUuid: _evtV15Ff10ServiceUuid,
      characteristicUuid: '0000FF11-1212-EFDE-1523-785FEABCD123',
    ),
    BleLogicalEndpoint.ff10Ff12: BleEndpoint(
      serviceUuid: _evtV15Ff10ServiceUuid,
      characteristicUuid: '0000FF12-1212-EFDE-1523-785FEABCD123',
    ),
    BleLogicalEndpoint.ff10Ff13: BleEndpoint(
      serviceUuid: _evtV15Ff10ServiceUuid,
      characteristicUuid: '0000FF13-1212-EFDE-1523-785FEABCD123',
    ),
  };

  const DeviceProfile({
    required this.namePrefix,
    required this.manufacturerPrefixHex,
    required this.serviceUuid,
    required this.gattServiceUuid,
    this.endpoints = const {},
    this.hasUnsupportedEndpointDeclaration = false,
  });

  /// The fixed profile shipped by the EVT build.
  ///
  /// EVT joint testing must not wait for an asynchronously loaded asset before
  /// it can connect to a peripheral. The protocol table is intentionally
  /// compiled into this build, so this factory is synchronous and immutable.
  factory DeviceProfile.evtV15() => _evtV15Profile;

  factory DeviceProfile.empty() => const DeviceProfile(
    namePrefix: 'AIPIN',
    manufacturerPrefixHex: 'A389',
    serviceUuid: '0000AF30-0000-1000-8000-00805F9B34FB',
    gattServiceUuid: '',
  );

  factory DeviceProfile.fromJson(Map<String, Object?> json) {
    String stringValue(String key) => json[key] as String? ?? '';
    String uuidValue(String key) => normalizeBleUuid(stringValue(key));
    final endpoints = <BleLogicalEndpoint, BleEndpoint>{};
    var hasUnsupportedEndpointDeclaration = false;
    final endpointJson = json['endpoints'];
    if (endpointJson is Map) {
      for (final serviceEntry in endpointJson.entries) {
        if (serviceEntry.value is! Map) {
          hasUnsupportedEndpointDeclaration = true;
          continue;
        }
        final service = serviceEntry.key.toString().toLowerCase();
        for (final characteristicEntry in (serviceEntry.value as Map).entries) {
          final key = _logicalEndpoint('$service${characteristicEntry.key}');
          if (key == null ||
              !evtV15EndpointOperations.containsKey(key) ||
              characteristicEntry.value is! Map) {
            hasUnsupportedEndpointDeclaration = true;
            continue;
          }
          final value = characteristicEntry.value as Map;
          endpoints[key] = BleEndpoint(
            serviceUuid: _endpointServiceUuid(
              service,
              value['serviceUuid'] as String?,
              gattServiceUuid: uuidValue('gattServiceUuid'),
            ),
            characteristicUuid: normalizeBleUuid(
              value['uuid'] as String? ?? '',
            ),
            operations: {
              for (final operation
                  in (value['operations'] as List? ?? const []))
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
      endpoints: endpoints,
      hasUnsupportedEndpointDeclaration: hasUnsupportedEndpointDeclaration,
    );
  }

  final String namePrefix;
  final String manufacturerPrefixHex;
  final String serviceUuid;
  final String gattServiceUuid;
  final Map<BleLogicalEndpoint, BleEndpoint> endpoints;
  final bool hasUnsupportedEndpointDeclaration;

  BleEndpoint endpoint(BleLogicalEndpoint key) =>
      endpoints[key] ??
      (throw StateError('BLE endpoint is not configured: $key'));

  bool canOperate(BleLogicalEndpoint key, BleOperation operation) =>
      endpoints[key]?.operations.contains(operation) ?? false;

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

  bool get isGattReady {
    if (!_matchesEvtV15DiscoveryContract || !_matchesEvtV15LegacyAnchors) {
      return false;
    }
    if (!_isUuid(gattServiceUuid)) {
      return false;
    }
    if (hasUnsupportedEndpointDeclaration ||
        endpoints.length != evtV15EndpointOperations.length) {
      return false;
    }
    for (final entry in evtV15EndpointOperations.entries) {
      final endpoint = endpoints[entry.key];
      final identity = evtV15EndpointIdentities[entry.key]!;
      if (endpoint == null ||
          !_isUuid(endpoint.serviceUuid) ||
          !_isUuid(endpoint.characteristicUuid) ||
          !_sameUuid(endpoint.serviceUuid, identity.serviceUuid) ||
          !_sameUuid(
            endpoint.characteristicUuid,
            identity.characteristicUuid,
          ) ||
          !endpoint.operations.containsAll(entry.value)) {
        return false;
      }
    }
    return endpoints.keys.every(evtV15EndpointOperations.containsKey);
  }

  EvtFailure? get validationFailure => isGattReady
      ? null
      : EvtFailure.access(
          message: 'GATT 配置未完成',
          detail: '当前 EVT V1.5 内置协议配置不完整，请重新安装匹配的 App 构建。',
        );

  bool get _matchesEvtV15DiscoveryContract {
    final prefix = manufacturerPrefixBytes;
    return namePrefix.trim().toUpperCase() == _evtV15NamePrefix &&
        _sameUuid(serviceUuid, _evtV15AdvertisementServiceUuid) &&
        prefix.length == _evtV15ManufacturerPrefix.length &&
        Iterable<int>.generate(
          prefix.length,
        ).every((index) => prefix[index] == _evtV15ManufacturerPrefix[index]);
  }

  bool get _matchesEvtV15LegacyAnchors =>
      _sameUuid(gattServiceUuid, _evtV15Fa10ServiceUuid);

  static bool _isUuid(String value) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
  }

  static bool _sameUuid(String actual, String expected) =>
      actual.trim().toUpperCase() == expected;

  static String _endpointServiceUuid(
    String service,
    String? configured, {
    required String gattServiceUuid,
  }) {
    if (configured != null && configured.trim().isNotEmpty) {
      return normalizeBleUuid(configured);
    }
    switch (service) {
      case 'fa10':
        return gattServiceUuid.isNotEmpty
            ? gattServiceUuid
            : normalizeBleUuid(service);
      case 'fb10':
        return _evtV15Fb10ServiceUuid;
      case 'ff10':
        return '0000FF10-1212-EFDE-1523-785FEABCD123';
      default:
        return normalizeBleUuid(service);
    }
  }
}

final DeviceProfile _evtV15Profile = DeviceProfile(
  namePrefix: DeviceProfile._evtV15NamePrefix,
  manufacturerPrefixHex: 'A389',
  serviceUuid: DeviceProfile._evtV15AdvertisementServiceUuid,
  gattServiceUuid: DeviceProfile._evtV15Fa10ServiceUuid,
  endpoints: Map<BleLogicalEndpoint, BleEndpoint>.unmodifiable({
    for (final entry in DeviceProfile.evtV15EndpointIdentities.entries)
      entry.key: BleEndpoint(
        serviceUuid: entry.value.serviceUuid,
        characteristicUuid: entry.value.characteristicUuid,
        operations: Set<BleOperation>.unmodifiable(
          DeviceProfile.evtV15EndpointOperations[entry.key]!,
        ),
      ),
  }),
);

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
