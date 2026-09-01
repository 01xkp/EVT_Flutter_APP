import 'package:aipin/core/ble/device_profile.dart';
import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/protocol/evt_protocol_codec.dart';
import 'package:aipin/features/device_session/application/session_controller.dart';
import 'package:aipin/features/device_session/domain/realtime_audio_gateway.dart';
import 'package:aipin/features/device_session/domain/session_phase.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_ble_transport.dart';

void main() {
  test(
    'does not become observable until subscribe and initial read both succeed',
    () async {
      final profile = _profileWithDeviceInfo();
      final transport = FakeBleTransport(
        profile: profile,
        deferRead: true,
        services: _servicesFor(profile),
      );
      final controller = SessionController(
        transport,
        profile,
        EvtProtocolCodec(),
      );
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);

      expect(controller.protocolRepository, isNotNull);
      expect(
        transport.subscribedCharacteristics.map(
          (characteristic) => characteristic.characteristicUuid,
        ),
        containsAll(<String>[
          '0000FA11-1212-EFDE-1523-785FEABCD123',
          '0000FA16-1212-EFDE-1523-785FEABCD123',
        ]),
      );
      transport.emitSubscriptionBytes(FakeBleTransport.validBatteryFrame);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.phase, isNot(SessionPhase.observable));
      final initialRead = controller.completeInitialRead(
        FakeBleTransport.validBatteryFrame,
      );
      await Future<void>.delayed(Duration.zero);
      transport.emitSubscriptionBytes(_deviceInfoFrame(protocolVersion: 3));
      await initialRead;
      expect(controller.state.phase, SessionPhase.observable);
    },
  );

  test(
    'loads authoritative battery, storage, privacy and file count after V3 admission',
    () async {
      final profile = _profileWithAuthoritativeStatusEndpoints();
      final codec = EvtProtocolCodec();
      final transport = FakeBleTransport(
        profile: profile,
        services: _servicesFor(profile),
        readValuesByCharacteristicUuid: {
          _fb11: FakeBleTransport.validBatteryFrame,
          _fa15: codec.encodeRequest(0x85, const [0, 1, 0, 0, 128, 0, 0, 0]),
          _ff11: codec.encodeRequest(0xA1, const [3, 0]),
        },
      );
      final controller = SessionController(transport, profile, codec);
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);
      await Future<void>.delayed(Duration.zero);
      transport.emitSubscriptionBytes(_deviceInfoFrame(protocolVersion: 3));
      await Future<void>.delayed(Duration.zero);
      transport.emitSubscriptionBytes(
        codec.encodeRequest(0x86, const [0x01, 0, 5, 1, 15, 0, 1, 0]),
      );
      await Future<void>.delayed(Duration.zero);
      transport.emitSubscriptionBytes(
        codec.encodeRequest(0x86, const [0x03, 0, 1, 2]),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.phase, SessionPhase.observable);
      expect(controller.state.deviceBattery?.percent, 80);
      expect(controller.state.deviceStorage?.totalMegabytes, 256);
      expect(controller.state.deviceStorage?.freeMegabytes, 128);
      expect(controller.state.deviceStatus?.privacy, isTrue);
      expect(controller.state.deviceStatus?.privacyRemainingMinutes, 15);
      expect(controller.state.privacyDurationCode, 2);
      expect(controller.state.fileCount, 3);
    },
  );

  test(
    'missing UUID profile reports access block instead of attempting a read',
    () async {
      final transport = FakeBleTransport();
      final controller = SessionController(
        transport,
        DeviceProfile.empty(),
        EvtProtocolCodec(),
      );
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);

      expect(controller.state.failure!.kind.name, 'access');
      expect(transport.discoveryRequests, isEmpty);
    },
  );

  test(
    'invalid initial data stays unverifiable and never opens observation',
    () async {
      final transport = FakeBleTransport.withGattReadyProfile();
      final controller = SessionController(
        transport,
        transport.profile,
        EvtProtocolCodec(),
      );
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);
      await controller.completeInitialRead(const [
        0xED,
        0x03,
        0x00,
        0x91,
        0x00,
        0x00,
      ]);

      expect(controller.state.phase, SessionPhase.initialSnapshotRead);
      expect(controller.state.failure, isNotNull);
    },
  );

  test(
    'rejects a non-V3 device before making the session observable',
    () async {
      final profile = _profileWithDeviceInfo();
      final transport = FakeBleTransport(
        profile: profile,
        deferRead: true,
        services: _servicesFor(profile),
      );
      final controller = SessionController(
        transport,
        profile,
        EvtProtocolCodec(),
      );
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);
      transport.completeRead(FakeBleTransport.validBatteryFrame);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.phase, SessionPhase.initialSnapshotRead);
      expect(transport.writes, hasLength(1));

      transport.emitSubscriptionBytes(_deviceInfoFrame(protocolVersion: 2));
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.phase, SessionPhase.interrupted);
      expect(controller.state.failure?.kind.name, 'protocol');
      expect(
        transport.disconnectedDeviceIds,
        contains(FakeBleTransport.matchingCandidate.id),
      );
    },
  );

  test(
    'does not subscribe the WQOTA notification through the business session',
    () async {
      final profile = _profileWithWqota();
      final transport = FakeBleTransport(
        profile: profile,
        deferRead: true,
        services: _servicesFor(profile),
      );
      final controller = SessionController(
        transport,
        profile,
        EvtProtocolCodec(),
      );
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);

      expect(
        transport.subscribedCharacteristics.map(
          (characteristic) => characteristic.characteristicUuid,
        ),
        isNot(contains('00002002-0000-1000-8000-00805F9B34FB')),
      );
    },
  );

  test(
    'owns FA18 only for a realtime capture and writes a complete audio configuration',
    () async {
      final profile = _profileWithRealtimeAudio();
      final codec = EvtProtocolCodec();
      final transport = FakeBleTransport(
        profile: profile,
        deferRead: true,
        services: _servicesFor(profile),
      );
      final controller = SessionController(transport, profile, codec);
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);
      await _completeV3Admission(transport);
      final RealtimeAudioGateway gateway = controller;

      expect(
        transport.subscribedCharacteristics.map(
          (characteristic) => characteristic.characteristicUuid,
        ),
        isNot(contains(_fa18)),
      );

      final subscription = gateway.subscribeRealtimeAudio().listen((_) {});
      addTearDown(subscription.cancel);

      expect(
        transport.subscribedCharacteristics.last.characteristicUuid,
        _fa18,
      );

      final configure = gateway.setAudioStreamEnabled(true);
      transport.emitSubscriptionBytes(codec.encodeRequest(0x82, const [1]));
      await configure;
      final configuration = codec.decode(transport.writes.last).value!;

      expect(configuration.command, 0x02);
      expect(configuration.content, hasLength(12));
      expect(configuration.content.last, 1);

      final startRecording = gateway.setRealtimeRecording(true);
      transport.emitSubscriptionBytes(codec.encodeRequest(0x87, const [1]));
      await startRecording;

      expect(codec.decode(transport.writes.last).value!.command, 0x07);
      expect(codec.decode(transport.writes.last).value!.content, [1]);
    },
  );

  test(
    'interrupts the session when the device disconnects after connecting',
    () async {
      final transport = FakeBleTransport.withGattReadyProfile();
      final controller = SessionController(
        transport,
        transport.profile,
        EvtProtocolCodec(),
      );
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);
      await _completeV3Admission(transport);
      expect(controller.state.phase, SessionPhase.observable);

      transport.emitConnection(BleConnectionState.disconnected);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.phase, SessionPhase.interrupted);
      expect(controller.state.failure?.kind.name, 'transport');
    },
  );

  test(
    'marks missing GATT endpoints as interrupted and releases the link',
    () async {
      final readyTransport = FakeBleTransport.withGattReadyProfile();
      final transport = FakeBleTransport(
        profile: readyTransport.profile,
        deferRead: true,
        services: const [],
      );
      final controller = SessionController(
        transport,
        transport.profile,
        EvtProtocolCodec(),
      );
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);

      expect(controller.state.phase, SessionPhase.interrupted);
      expect(controller.state.failure?.kind.name, 'access');
      expect(
        transport.disconnectedDeviceIds,
        contains(FakeBleTransport.matchingCandidate.id),
      );
    },
  );

  test('releases the link when the notification stream fails', () async {
    final transport = FakeBleTransport.withGattReadyProfile();
    final controller = SessionController(
      transport,
      transport.profile,
      EvtProtocolCodec(),
    );
    addTearDown(controller.dispose);

    await controller.connect(FakeBleTransport.matchingCandidate);
    await _completeV3Admission(transport);
    expect(controller.state.phase, SessionPhase.observable);

    transport.emitSubscriptionError(StateError('notification closed'));
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.phase, SessionPhase.interrupted);
    expect(
      transport.disconnectedDeviceIds,
      contains(FakeBleTransport.matchingCandidate.id),
    );
  });

  test(
    'marks an initial read failure as interrupted instead of staying in setup',
    () async {
      final readyTransport = FakeBleTransport.withGattReadyProfile();
      final transport = FakeBleTransport(
        profile: readyTransport.profile,
        services: readyTransport.services,
        readError: StateError('read failed'),
      );
      final controller = SessionController(
        transport,
        transport.profile,
        EvtProtocolCodec(),
      );
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.phase, SessionPhase.interrupted);
      expect(controller.state.failure?.kind.name, 'transport');
    },
  );
}

DeviceProfile _profileWithDeviceInfo({bool includeWqota = false}) {
  const fa10 = _fa10;
  const fb10 = _fb10Service;
  const wqota = '00007033-0000-1000-8000-00805F9B34FB';
  return DeviceProfile(
    namePrefix: 'AIPIN',
    manufacturerPrefixHex: 'A389',
    serviceUuid: '0000AF30-0000-1000-8000-00805F9B34FB',
    gattServiceUuid: fa10,
    readServiceUuid: fb10,
    readCharacteristicUuid: '0000FB11-1212-EFDE-1523-785FEABCD123',
    notifyServiceUuid: fa10,
    notifyCharacteristicUuid: '0000FA16-1212-EFDE-1523-785FEABCD123',
    writeServiceUuid: fa10,
    writeCharacteristicUuid: '0000FA16-1212-EFDE-1523-785FEABCD123',
    endpoints: {
      BleLogicalEndpoint.fa10Fa11: const BleEndpoint(
        serviceUuid: fa10,
        characteristicUuid: '0000FA11-1212-EFDE-1523-785FEABCD123',
        operations: {BleOperation.write, BleOperation.indicate},
      ),
      if (includeWqota)
        BleLogicalEndpoint.wqota2002: const BleEndpoint(
          serviceUuid: wqota,
          characteristicUuid: '00002002-0000-1000-8000-00805F9B34FB',
          operations: {BleOperation.notify},
        ),
    },
  );
}

DeviceProfile _profileWithAuthoritativeStatusEndpoints() {
  final base = _profileWithDeviceInfo();
  return DeviceProfile(
    namePrefix: base.namePrefix,
    manufacturerPrefixHex: base.manufacturerPrefixHex,
    serviceUuid: base.serviceUuid,
    gattServiceUuid: base.gattServiceUuid,
    readServiceUuid: base.readServiceUuid,
    readCharacteristicUuid: base.readCharacteristicUuid,
    notifyServiceUuid: base.notifyServiceUuid,
    notifyCharacteristicUuid: base.notifyCharacteristicUuid,
    writeServiceUuid: base.writeServiceUuid,
    writeCharacteristicUuid: base.writeCharacteristicUuid,
    endpoints: {
      ...base.endpoints,
      BleLogicalEndpoint.fa10Fa15: const BleEndpoint(
        serviceUuid: _fa10,
        characteristicUuid: _fa15,
        operations: {BleOperation.read, BleOperation.indicate},
      ),
      BleLogicalEndpoint.fa10Fa16: const BleEndpoint(
        serviceUuid: _fa10,
        characteristicUuid: _fa16,
        operations: {BleOperation.notify, BleOperation.write},
      ),
      BleLogicalEndpoint.fb10Fb11: const BleEndpoint(
        serviceUuid: _fb10Service,
        characteristicUuid: _fb11,
        operations: {BleOperation.read, BleOperation.indicate},
      ),
      BleLogicalEndpoint.ff10Ff11: const BleEndpoint(
        serviceUuid: _ff10,
        characteristicUuid: _ff11,
        operations: {BleOperation.read, BleOperation.indicate},
      ),
    },
  );
}

DeviceProfile _profileWithWqota() => _profileWithDeviceInfo(includeWqota: true);

DeviceProfile _profileWithRealtimeAudio() {
  final base = _profileWithDeviceInfo();
  return DeviceProfile(
    namePrefix: base.namePrefix,
    manufacturerPrefixHex: base.manufacturerPrefixHex,
    serviceUuid: base.serviceUuid,
    gattServiceUuid: base.gattServiceUuid,
    readServiceUuid: base.readServiceUuid,
    readCharacteristicUuid: base.readCharacteristicUuid,
    notifyServiceUuid: base.notifyServiceUuid,
    notifyCharacteristicUuid: base.notifyCharacteristicUuid,
    writeServiceUuid: base.writeServiceUuid,
    writeCharacteristicUuid: base.writeCharacteristicUuid,
    endpoints: {
      ...base.endpoints,
      BleLogicalEndpoint.fa10Fa12: const BleEndpoint(
        serviceUuid: _fa10,
        characteristicUuid: _fa12,
        operations: {
          BleOperation.read,
          BleOperation.write,
          BleOperation.indicate,
        },
      ),
      BleLogicalEndpoint.fa10Fa17: const BleEndpoint(
        serviceUuid: _fa10,
        characteristicUuid: _fa17,
        operations: {BleOperation.write, BleOperation.indicate},
      ),
      BleLogicalEndpoint.fa10Fa18: const BleEndpoint(
        serviceUuid: _fa10,
        characteristicUuid: _fa18,
        operations: {BleOperation.notify},
      ),
    },
  );
}

List<BleService> _servicesFor(DeviceProfile profile) => [
  const BleService(
    uuid: _fa10,
    characteristicUuids: [
      '0000FA11-1212-EFDE-1523-785FEABCD123',
      '0000FA16-1212-EFDE-1523-785FEABCD123',
      _fa15,
      _fa12,
      _fa17,
      _fa18,
    ],
  ),
  const BleService(uuid: _fb10Service, characteristicUuids: [_fb11]),
  if (profile.endpoints.containsKey(BleLogicalEndpoint.ff10Ff11))
    const BleService(uuid: _ff10, characteristicUuids: [_ff11]),
  if (profile.endpoints.containsKey(BleLogicalEndpoint.wqota2002))
    const BleService(
      uuid: '00007033-0000-1000-8000-00805F9B34FB',
      characteristicUuids: ['00002002-0000-1000-8000-00805F9B34FB'],
    ),
];

const _fa10 = '0000FA10-1212-EFDE-1523-785FEABCD123';
const _fa12 = '0000FA12-1212-EFDE-1523-785FEABCD123';
const _fa15 = '0000FA15-1212-EFDE-1523-785FEABCD123';
const _fa16 = '0000FA16-1212-EFDE-1523-785FEABCD123';
const _fa17 = '0000FA17-1212-EFDE-1523-785FEABCD123';
const _fa18 = '0000FA18-1212-EFDE-1523-785FEABCD123';
const _fb10Service = '0000FB10-1212-EFDE-1523-785FEABCD123';
const _fb11 = '0000FB11-1212-EFDE-1523-785FEABCD123';
const _ff10 = '0000FF10-1212-EFDE-1523-785FEABCD123';
const _ff11 = '0000FF11-1212-EFDE-1523-785FEABCD123';

List<int> _deviceInfoFrame({required int protocolVersion}) {
  final content = List<int>.filled(90, 0);
  content[0] = protocolVersion;
  content.setRange(1, 14, 'SN202608130001'.codeUnits);
  content.setRange(21, 26, '1.0.0'.codeUnits);
  content.setRange(29, 31, 'A1'.codeUnits);
  content.setRange(45, 55, 'AIPIN_8423'.codeUnits);
  content.setRange(74, 78, [0, 1, 0, 0]);
  content.setRange(78, 82, [128, 0, 0, 0]);
  content[83] = 0;
  content[84] = 80;
  content[85] = 1;
  return EvtProtocolCodec().encodeRequest(0x81, content);
}

Future<void> _completeV3Admission(FakeBleTransport transport) async {
  transport.completeRead(FakeBleTransport.validBatteryFrame);
  await Future<void>.delayed(Duration.zero);
  transport.emitSubscriptionBytes(_deviceInfoFrame(protocolVersion: 3));
  await Future<void>.delayed(Duration.zero);
}
