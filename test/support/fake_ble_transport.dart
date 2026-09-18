import 'dart:async';
import 'dart:typed_data';

import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/ble/ble_transport.dart';
import 'package:aipin/core/ble/device_profile.dart';
import 'package:aipin/features/device_discovery/domain/device_candidate.dart';
import 'package:aipin/core/protocol/evt_protocol_codec.dart';

class FakeBleTransport implements BleTransport {
  FakeBleTransport({
    DeviceProfile? profile,
    List<BleService>? services,
    this.deferRead = false,
    this.deferServiceDiscovery = false,
    this.deferDisconnect = false,
    this.readError,
    this.negotiatedMtu = 247,
    this.gattCacheClearResult = BleGattCacheClearResult.unsupported,
    this.gattCacheClearError,
    this.closeSubscriptionImmediatelyForCharacteristic,
    this.deferNotificationSetup = false,
    this.autoRespondToPreAuthenticationDeviceInfo = true,
    List<int>? preAuthenticationDeviceInfoResponse,
    Map<String, Object> notificationSetupFailureByCharacteristicUuid = const {},
    Map<String, List<int>> readValuesByCharacteristicUuid = const {},
  }) : profile = profile ?? DeviceProfile.empty(),
       services = services ?? const [],
       _preAuthenticationDeviceInfoResponse = Uint8List.fromList(
         preAuthenticationDeviceInfoResponse ??
             _defaultPreAuthenticationDeviceInfoResponse,
       ),
       _readValuesByCharacteristicUuid = Map.unmodifiable(
         readValuesByCharacteristicUuid.map(
           (uuid, value) => MapEntry(uuid, Uint8List.fromList(value)),
         ),
       ),
       _notificationSetupFailureByCharacteristicUuid = Map.unmodifiable(
         notificationSetupFailureByCharacteristicUuid.map(
           (uuid, error) => MapEntry(uuid.toUpperCase(), error),
         ),
       );

  factory FakeBleTransport.withGattReadyProfile({
    bool deferDisconnect = false,
    bool deferServiceDiscovery = false,
  }) {
    const profile = DeviceProfile(
      namePrefix: 'AIPIN',
      manufacturerPrefixHex: 'A389',
      serviceUuid: '0000AF30-0000-1000-8000-00805F9B34FB',
      gattServiceUuid: '0000FA10-1212-EFDE-1523-785FEABCD123',
      endpoints: {
        BleLogicalEndpoint.fa10Fa11: BleEndpoint(
          serviceUuid: '0000FA10-1212-EFDE-1523-785FEABCD123',
          characteristicUuid: '0000FA11-1212-EFDE-1523-785FEABCD123',
          operations: {BleOperation.write, BleOperation.indicate},
        ),
        BleLogicalEndpoint.fa10Fa19: BleEndpoint(
          serviceUuid: '0000FA10-1212-EFDE-1523-785FEABCD123',
          characteristicUuid: '0000FA19-1212-EFDE-1523-785FEABCD123',
          operations: {BleOperation.write, BleOperation.indicate},
        ),
        BleLogicalEndpoint.fa10Fa12: BleEndpoint(
          serviceUuid: '0000FA10-1212-EFDE-1523-785FEABCD123',
          characteristicUuid: '0000FA12-1212-EFDE-1523-785FEABCD123',
          operations: {
            BleOperation.read,
            BleOperation.write,
            BleOperation.indicate,
          },
        ),
        BleLogicalEndpoint.fa10Fa15: BleEndpoint(
          serviceUuid: '0000FA10-1212-EFDE-1523-785FEABCD123',
          characteristicUuid: '0000FA15-1212-EFDE-1523-785FEABCD123',
          operations: {BleOperation.write, BleOperation.indicate},
        ),
        BleLogicalEndpoint.fa10Fa16: BleEndpoint(
          serviceUuid: '0000FA10-1212-EFDE-1523-785FEABCD123',
          characteristicUuid: '0000FA16-1212-EFDE-1523-785FEABCD123',
          operations: {BleOperation.write, BleOperation.indicate},
        ),
        BleLogicalEndpoint.fa10Fa17: BleEndpoint(
          serviceUuid: '0000FA10-1212-EFDE-1523-785FEABCD123',
          characteristicUuid: '0000FA17-1212-EFDE-1523-785FEABCD123',
          operations: {BleOperation.write, BleOperation.indicate},
        ),
        BleLogicalEndpoint.fb10Fb11: BleEndpoint(
          serviceUuid: '0000FB10-1212-EFDE-1523-785FEABCD123',
          characteristicUuid: '0000FB11-1212-EFDE-1523-785FEABCD123',
          operations: {BleOperation.read, BleOperation.indicate},
        ),
        BleLogicalEndpoint.ff10Ff11: BleEndpoint(
          serviceUuid: '0000FF10-1212-EFDE-1523-785FEABCD123',
          characteristicUuid: '0000FF11-1212-EFDE-1523-785FEABCD123',
          operations: {BleOperation.write, BleOperation.indicate},
        ),
        BleLogicalEndpoint.ff10Ff12: BleEndpoint(
          serviceUuid: '0000FF10-1212-EFDE-1523-785FEABCD123',
          characteristicUuid: '0000FF12-1212-EFDE-1523-785FEABCD123',
          operations: {BleOperation.write, BleOperation.indicate},
        ),
        BleLogicalEndpoint.ff10Ff13: BleEndpoint(
          serviceUuid: '0000FF10-1212-EFDE-1523-785FEABCD123',
          characteristicUuid: '0000FF13-1212-EFDE-1523-785FEABCD123',
          operations: {BleOperation.write, BleOperation.notify},
        ),
        // V1.6 DVT makes the metadata/archive-confirmation channel part of
        // the required GATT contract. Keep the shared ready fixture aligned
        // with a real peripheral so unrelated session tests reach admission.
        BleLogicalEndpoint.ff10Ff16: BleEndpoint(
          serviceUuid: '0000FF10-1212-EFDE-1523-785FEABCD123',
          characteristicUuid: '0000FF16-1212-EFDE-1523-785FEABCD123',
          operations: {BleOperation.write, BleOperation.indicate},
        ),
      },
    );
    return FakeBleTransport(
      profile: profile,
      deferRead: true,
      deferDisconnect: deferDisconnect,
      deferServiceDiscovery: deferServiceDiscovery,
      services: const [
        BleService(
          uuid: '0000FA10-1212-EFDE-1523-785FEABCD123',
          characteristics: [
            BleDiscoveredCharacteristic(
              uuid: '0000FA11-1212-EFDE-1523-785FEABCD123',
              operations: {BleOperation.write, BleOperation.indicate},
            ),
            BleDiscoveredCharacteristic(
              uuid: '0000FA16-1212-EFDE-1523-785FEABCD123',
              operations: {BleOperation.write, BleOperation.indicate},
            ),
            BleDiscoveredCharacteristic(
              uuid: '0000FA19-1212-EFDE-1523-785FEABCD123',
              operations: {BleOperation.write, BleOperation.indicate},
            ),
            BleDiscoveredCharacteristic(
              uuid: '0000FA12-1212-EFDE-1523-785FEABCD123',
              operations: {
                BleOperation.read,
                BleOperation.write,
                BleOperation.indicate,
              },
            ),
            BleDiscoveredCharacteristic(
              uuid: '0000FA15-1212-EFDE-1523-785FEABCD123',
              operations: {BleOperation.write, BleOperation.indicate},
            ),
            BleDiscoveredCharacteristic(
              uuid: '0000FA17-1212-EFDE-1523-785FEABCD123',
              operations: {BleOperation.write, BleOperation.indicate},
            ),
          ],
        ),
        BleService(
          uuid: '0000FB10-1212-EFDE-1523-785FEABCD123',
          characteristics: [
            BleDiscoveredCharacteristic(
              uuid: '0000FB11-1212-EFDE-1523-785FEABCD123',
              operations: {BleOperation.read, BleOperation.indicate},
            ),
          ],
        ),
        BleService(
          uuid: '0000FF10-1212-EFDE-1523-785FEABCD123',
          characteristics: [
            BleDiscoveredCharacteristic(
              uuid: '0000FF11-1212-EFDE-1523-785FEABCD123',
              operations: {BleOperation.write, BleOperation.indicate},
            ),
            BleDiscoveredCharacteristic(
              uuid: '0000FF12-1212-EFDE-1523-785FEABCD123',
              operations: {BleOperation.write, BleOperation.indicate},
            ),
            BleDiscoveredCharacteristic(
              uuid: '0000FF13-1212-EFDE-1523-785FEABCD123',
              operations: {BleOperation.write, BleOperation.notify},
            ),
            BleDiscoveredCharacteristic(
              uuid: '0000FF16-1212-EFDE-1523-785FEABCD123',
              operations: {BleOperation.write, BleOperation.indicate},
            ),
          ],
        ),
      ],
    );
  }

  static final matchingCandidate = DeviceCandidate(
    connectionId: '71:BF:E2:3B:84:23',
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
  final _subscriptionControllersByCharacteristic =
      <String, StreamController<Uint8List>>{};
  final disconnectedDeviceIds = <String>[];
  final List<String> discoveryRequests = [];
  final List<String> gattCacheClearDeviceIds = [];
  final List<String> connectionOperations = [];
  final List<BleCharacteristic> subscribedCharacteristics = [];
  final List<BleCharacteristic> notificationSetupRequests = [];
  final List<BleCharacteristic> readCharacteristics = [];
  var scanCallCount = 0;
  final bool deferRead;
  final bool deferServiceDiscovery;
  final bool deferDisconnect;
  final Object? readError;
  final int negotiatedMtu;
  final BleGattCacheClearResult gattCacheClearResult;
  final Object? gattCacheClearError;
  final String? closeSubscriptionImmediatelyForCharacteristic;
  final bool deferNotificationSetup;

  /// Simulates the V1.6 admission exchange (FA11 0x01 -> 0x81) for a complete
  /// GATT-ready fake. Tests that exercise a missing/late pre-auth response can
  /// disable this without changing the transport's regular write behavior.
  final bool autoRespondToPreAuthenticationDeviceInfo;
  final Uint8List _preAuthenticationDeviceInfoResponse;
  final Map<String, Object> _notificationSetupFailureByCharacteristicUuid;
  final Map<String, Uint8List> _readValuesByCharacteristicUuid;
  final Completer<Uint8List> _deferredRead = Completer<Uint8List>();
  final Completer<List<BleService>> _deferredServices =
      Completer<List<BleService>>();
  final Completer<void> _deferredNotificationSetup = Completer<void>();
  final Completer<void> _deferredDisconnect = Completer<void>();
  final List<BleService> services;
  var _preAuthenticationDeviceInfoResponseSent = false;
  Uint8List readValue = Uint8List(0);
  final List<int> requestedMtus = [];

  Stream<Uint8List> get subscriptionStream => _subscriptionController.stream;
  final writes = <Uint8List>[];
  final writtenCharacteristics = <BleCharacteristic>[];
  final writesWithoutResponse = <Uint8List>[];

  void emitCandidate(DeviceCandidate candidate) =>
      _scanController.add(candidate);

  void emitScanError(Object error) => _scanController.addError(error);

  void emitConnection(BleConnectionState state) =>
      _connectionController.add(state);

  void emitSubscriptionBytes(List<int> bytes) {
    final value = Uint8List.fromList(bytes);
    _subscriptionController.add(value);
    for (final controller in _subscriptionControllersByCharacteristic.values) {
      controller.add(value);
    }
  }

  /// Emits a notification only through the subscription for [characteristicUuid].
  void emitSubscriptionBytesForCharacteristic(
    String characteristicUuid,
    List<int> bytes,
  ) {
    _subscriptionControllersByCharacteristic[characteristicUuid.toUpperCase()]
        ?.add(Uint8List.fromList(bytes));
  }

  void emitSubscriptionError(Object error) {
    _subscriptionController.addError(error, StackTrace.current);
    for (final controller in _subscriptionControllersByCharacteristic.values) {
      controller.addError(error, StackTrace.current);
    }
  }

  @override
  Stream<DeviceCandidate> scan() {
    scanCallCount += 1;
    return _scanController.stream;
  }

  @override
  Stream<BleConnectionState> connect(String deviceId) async* {
    _preAuthenticationDeviceInfoResponseSent = false;
    yield BleConnectionState.connected;
    yield* _connectionController.stream;
  }

  @override
  Future<List<BleService>> discoverServices(String deviceId) async {
    discoveryRequests.add(deviceId);
    return deferServiceDiscovery ? _deferredServices.future : services;
  }

  @override
  Future<BleGattCacheClearResult> clearGattCache(String deviceId) async {
    gattCacheClearDeviceIds.add(deviceId);
    connectionOperations.add('clear_gatt_cache');
    if (gattCacheClearError != null) {
      throw gattCacheClearError!;
    }
    return gattCacheClearResult;
  }

  void completeServiceDiscovery([List<BleService>? value]) {
    if (!_deferredServices.isCompleted) {
      _deferredServices.complete(value ?? services);
    }
  }

  @override
  Future<int> requestMtu(String deviceId, {required int preferredMtu}) async {
    requestedMtus.add(preferredMtu);
    return negotiatedMtu;
  }

  @override
  Stream<Uint8List> subscribe(BleCharacteristic characteristic) {
    subscribedCharacteristics.add(characteristic);
    if (characteristic.characteristicUuid.toUpperCase() ==
        closeSubscriptionImmediatelyForCharacteristic?.toUpperCase()) {
      return Stream<Uint8List>.empty();
    }
    return _subscriptionControllersByCharacteristic
        .putIfAbsent(
          characteristic.characteristicUuid.toUpperCase(),
          () => StreamController<Uint8List>.broadcast(),
        )
        .stream;
  }

  @override
  Future<void> awaitSubscriptionReady(BleCharacteristic characteristic) {
    notificationSetupRequests.add(characteristic);
    final error =
        _notificationSetupFailureByCharacteristicUuid[characteristic
            .characteristicUuid
            .toUpperCase()];
    if (error != null) {
      return Future<void>.error(error);
    }
    return deferNotificationSetup
        ? _deferredNotificationSetup.future
        : Future<void>.value();
  }

  void completeNotificationSetup() {
    if (!_deferredNotificationSetup.isCompleted) {
      _deferredNotificationSetup.complete();
    }
  }

  void completeDisconnect() {
    if (!_deferredDisconnect.isCompleted) {
      _deferredDisconnect.complete();
    }
  }

  @override
  Future<Uint8List> read(BleCharacteristic characteristic) async {
    readCharacteristics.add(characteristic);
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
    writtenCharacteristics.add(characteristic);
    writes.add(Uint8List.fromList(bytes));
    _schedulePreAuthenticationDeviceInfoResponse(characteristic, bytes);
  }

  void _schedulePreAuthenticationDeviceInfoResponse(
    BleCharacteristic characteristic,
    Uint8List bytes,
  ) {
    if (!autoRespondToPreAuthenticationDeviceInfo ||
        _preAuthenticationDeviceInfoResponseSent ||
        !profile.isGattReady ||
        services.isEmpty ||
        characteristic.characteristicUuid.toUpperCase() !=
            profile
                .endpoint(BleLogicalEndpoint.fa10Fa11)
                .characteristicUuid
                .toUpperCase()) {
      return;
    }
    final frame = EvtProtocolCodec().decode(bytes).value;
    if (frame == null || frame.command != 0x01 || frame.content.isNotEmpty) {
      return;
    }
    _preAuthenticationDeviceInfoResponseSent = true;
    // Deliver after the native write future completes. This mirrors a
    // peripheral indication and guarantees the command client's pending slot
    // is installed before the response reaches the session controller.
    Future<void>.microtask(() {
      emitSubscriptionBytesForCharacteristic(
        characteristic.characteristicUuid,
        _preAuthenticationDeviceInfoResponse,
      );
    });
  }

  static final List<int> _defaultPreAuthenticationDeviceInfoResponse = () {
    final content = List<int>.filled(90, 0);
    content[0] = 3;
    content.setRange(1, 14, 'SN202608130001'.codeUnits);
    content.setRange(21, 26, '1.0.0'.codeUnits);
    content.setRange(29, 31, 'A1'.codeUnits);
    content.setRange(45, 55, 'AIPIN_8423'.codeUnits);
    // V1.6 pre-authentication responses must redact all state/capacity data.
    content.setRange(74, 78, [0, 0, 0, 0]);
    content.setRange(78, 82, [0, 0, 0, 0]);
    content[83] = 0;
    content[84] = 0;
    content[85] = 0;
    content[87] = 0;
    content[88] = 0;
    return EvtProtocolCodec().encodeRequest(0x81, content);
  }();

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
    connectionOperations.add('disconnect');
    if (deferDisconnect) {
      await _deferredDisconnect.future;
    }
  }

  Future<void> dispose() async {
    await _scanController.close();
    await _connectionController.close();
    await _subscriptionController.close();
    for (final controller in _subscriptionControllersByCharacteristic.values) {
      await controller.close();
    }
  }
}
