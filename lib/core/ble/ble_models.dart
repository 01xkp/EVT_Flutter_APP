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

enum BleOperation { read, write, writeWithoutResponse, notify, indicate }

enum BleLogicalEndpoint {
  fa10Fa11, fa10Fa12, fa10Fa15, fa10Fa16, fa10Fa17, fa10Fa18, fa10Fa19,
  fb10Fb11, ff10Ff11, ff10Ff12, ff10Ff13, ff10Ff16, wqota2001, wqota2002,
}

enum BleConnectionState { connecting, connected, disconnecting, disconnected }
