import 'dart:async';
import 'dart:typed_data';

import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/ble/ble_transport.dart';
import 'package:aipin/core/ble/device_profile.dart';
import 'package:aipin/features/device_discovery/domain/device_candidate.dart';

class FakeBleTransport implements BleTransport {
  FakeBleTransport({
    DeviceProfile? profile,
    List<BleService>? services,
    this.deferRead = false,
    this.readError,
    Map<String, List<int>> readValuesByCharacteristicUuid = const {},
  }) : profile = profile ?? DeviceProfile.empty(),
       services = services ?? const [],
       _readValuesByCharacteristicUuid = Map.unmodifiable(
         readValuesByCharacteristicUuid.map(
           (uuid, value) => MapEntry(uuid, Uint8List.fromList(value)),
         ),
       );

  factory FakeBleTransport.withGattReadyProfile() {
    const profile = DeviceProfile(
      namePrefix: 'AIPIN',
      manufacturerPrefixHex: 'A389',
      serviceUuid: '0000AF30-0000-1000-8000-00805F9B34FB',
      gattServiceUuid: '0000FA10-1212-EFDE-1523-785FEABCD123',
      readServiceUuid: '0000FB10-1212-EFDE-1523-785FEABCD123',
      readCharacteristicUuid: '0000FB11-1212-EFDE-1523-785FEABCD123',
      notifyServiceUuid: '0000FA10-1212-EFDE-1523-785FEABCD123',
      notifyCharacteristicUuid: '0000FA16-1212-EFDE-1523-785FEABCD123',
      writeServiceUuid: '0000FA10-1212-EFDE-1523-785FEABCD123',
      writeCharacteristicUuid: '0000FA16-1212-EFDE-1523-785FEABCD123',
      endpoints: {
        BleLogicalEndpoint.fa10Fa11: BleEndpoint(
          serviceUuid: '0000FA10-1212-EFDE-1523-785FEABCD123',
          characteristicUuid: '0000FA11-1212-EFDE-1523-785FEABCD123',
          operations: const {BleOperation.write, BleOperation.indicate},
        ),
      },
    );
    return FakeBleTransport(
      profile: profile,
      deferRead: true,
      services: const [
        BleService(
          uuid: '0000FA10-1212-EFDE-1523-785FEABCD123',
          characteristicUuids: [
            '0000FA11-1212-EFDE-1523-785FEABCD123',
            '0000FA16-1212-EFDE-1523-785FEABCD123',
          ],
        ),
        BleService(
          uuid: '0000FB10-1212-EFDE-1523-785FEABCD123',
          characteristicUuids: ['0000FB11-1212-EFDE-1523-785FEABCD123'],
        ),
      ],
    );
  }

  static final matchingCandidate = DeviceCandidate(
    id: '71:BF:E2:3B:84:23',
    name: 'AIPIN_8423',
    manufacturerData: const [0xA3, 0x89, 0x71, 0xBF, 0xE2, 0x3B, 0x84, 0x23],
    serviceUuids: const ['0000AF30-0000-1000-8000-00805F9B34FB'],
    rssi: -48,
    discoveredAt: DateTime(2026, 8, 21),
  );

  static final weakMatchingCandidate = matchingCandidate.copyWith(rssi: -76);
  static const validBatteryFrame = [
    0xED,
    0x06,
    0x00,
    0x91,
    0x50,
    0x01,
    0x00,
    0x14,
    0x59,
  ];

  final DeviceProfile profile;
  final _scanController = StreamController<DeviceCandidate>.broadcast();
  final _connectionController =
      StreamController<BleConnectionState>.broadcast();
  final _subscriptionController = StreamController<Uint8List>.broadcast();
  final disconnectedDeviceIds = <String>[];
  final List<String> discoveryRequests = [];
  final List<BleCharacteristic> subscribedCharacteristics = [];
  var scanCallCount = 0;
  final bool deferRead;
  final Object? readError;
  final Map<String, Uint8List> _readValuesByCharacteristicUuid;
  final Completer<Uint8List> _deferredRead = Completer<Uint8List>();
  final List<BleService> services;
  Uint8List readValue = Uint8List(0);

  Stream<Uint8List> get subscriptionStream => _subscriptionController.stream;
  final writes = <Uint8List>[];
  final writesWithoutResponse = <Uint8List>[];

  void emitCandidate(DeviceCandidate candidate) =>
      _scanController.add(candidate);

  void emitScanError(Object error) => _scanController.addError(error);

  void emitConnection(BleConnectionState state) =>
      _connectionController.add(state);

  void emitSubscriptionBytes(List<int> bytes) {
    _subscriptionController.add(Uint8List.fromList(bytes));
  }

  void emitSubscriptionError(Object error) {
    _subscriptionController.addError(error, StackTrace.current);
  }

  @override
  Stream<DeviceCandidate> scan() {
    scanCallCount += 1;
    return _scanController.stream;
  }

  @override
  Stream<BleConnectionState> connect(String deviceId) async* {
    yield BleConnectionState.connected;
    yield* _connectionController.stream;
  }

  @override
  Future<List<BleService>> discoverServices(String deviceId) async {
    discoveryRequests.add(deviceId);
    return services;
  }

  @override
  Stream<Uint8List> subscribe(BleCharacteristic characteristic) {
    subscribedCharacteristics.add(characteristic);
    return _subscriptionController.stream;
  }

  @override
  Future<Uint8List> read(BleCharacteristic characteristic) async {
    if (readError != null) {
      throw readError!;
    }
    final configuredValue =
        _readValuesByCharacteristicUuid[characteristic.characteristicUuid];
    if (configuredValue != null) {
      return Uint8List.fromList(configuredValue);
    }
    return deferRead ? _deferredRead.future : readValue;
  }

  @override
  Future<void> write(BleCharacteristic characteristic, Uint8List bytes) async {
    writes.add(Uint8List.fromList(bytes));
  }

  @override
  Future<void> writeWithoutResponse(
    BleCharacteristic characteristic,
    Uint8List bytes,
  ) async {
    writesWithoutResponse.add(Uint8List.fromList(bytes));
  }

  void completeRead(List<int> bytes) {
    if (!_deferredRead.isCompleted) {
      _deferredRead.complete(Uint8List.fromList(bytes));
    }
  }

  @override
  Future<void> disconnect(String deviceId) async {
    disconnectedDeviceIds.add(deviceId);
  }

  Future<void> dispose() async {
    await _scanController.close();
    await _connectionController.close();
    await _subscriptionController.close();
  }
}
