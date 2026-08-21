class BleService {
  const BleService({required this.uuid, this.characteristicUuids = const []});

  final String uuid;
  final List<String> characteristicUuids;
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

enum BleConnectionState { connecting, connected, disconnecting, disconnected }
