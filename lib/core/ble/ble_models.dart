enum BleOperation { read, write, writeWithoutResponse, notify, indicate }

class BleService {
  const BleService({
    required this.uuid,
    this.characteristicUuids = const [],
    this.characteristics = const [],
  });

  final String uuid;

  /// Kept for older fixtures and diagnostic output. Production discovery also
  /// captures the GATT properties in [characteristics].
  final List<String> characteristicUuids;
  final List<BleDiscoveredCharacteristic> characteristics;

  BleDiscoveredCharacteristic? characteristic(String uuid) {
    for (final characteristic in characteristics) {
      if (characteristic.uuid.toUpperCase() == uuid.toUpperCase()) {
        return characteristic;
      }
    }
    return null;
  }
}

class BleDiscoveredCharacteristic {
  const BleDiscoveredCharacteristic({
    required this.uuid,
    required this.operations,
  });

  final String uuid;
  final Set<BleOperation> operations;
}

class BleCharacteristic {
  const BleCharacteristic({
    required this.deviceId,
    required this.serviceUuid,
    required this.characteristicUuid,
  });

  final String deviceId;
  final String serviceUuid;
  final String characteristicUuid;
}

enum BleLogicalEndpoint {
  fa10Fa11,
  fa10Fa12,
  fa10Fa15,
  fa10Fa16,
  fa10Fa17,
  fa10Fa19,
  fb10Fb11,
  ff10Ff11,
  ff10Ff12,
  ff10Ff13,
}

enum BleConnectionState { connecting, connected, disconnecting, disconnected }
