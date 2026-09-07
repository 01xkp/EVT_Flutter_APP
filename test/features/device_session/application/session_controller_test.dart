import 'package:aipin/core/ble/device_profile.dart';
import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/ble/ble_transport.dart';
import 'package:aipin/core/protocol/evt_protocol_codec.dart';
import 'package:aipin/features/device_session/application/session_controller.dart';
import 'package:aipin/features/device_session/application/device_auth_controller.dart';
import 'package:aipin/features/device_session/domain/device_configuration.dart';
import 'package:aipin/features/device_session/domain/realtime_audio_gateway.dart';
import 'package:aipin/features/device_session/domain/device_security_gateway.dart';
import 'package:aipin/features/device_session/domain/ticket_gateway.dart';
import 'package:aipin/features/device_session/domain/session_phase.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_ble_transport.dart';

void main() {
  test(
    'prepares authentication after subscriptions without reading protected state',
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
      expect(controller.state.phase, SessionPhase.authenticationReady);
      expect(controller.state.isAuthenticationReady, isTrue);
      expect(controller.state.isObservable, isFalse);
      expect(transport.readCharacteristics, isEmpty);
    },
  );

  test('allows 0x09 authentication before protected FB11 is read', () async {
    final profile = _profileWithDeviceInfo();
    final codec = EvtProtocolCodec();
    final transport = FakeBleTransport(
      profile: profile,
      deferRead: true,
      services: _servicesFor(profile),
    );
    final controller = SessionController(transport, profile, codec);
    addTearDown(controller.dispose);

    await controller.connect(FakeBleTransport.matchingCandidate);

    expect(transport.readCharacteristics, isEmpty);
    final operation = controller.execute(
      const DeviceSecurityRequest(
        action: DeviceAuthAction.authenticate,
        transactionId: 7,
        data: [],
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(codec.decode(transport.writes.single).value!.command, 0x09);
    transport.emitSubscriptionBytes(
      codec.encodeRequest(0x89, const [0xF2, 0x20, 7, 0, 0, 0, 0, 0, 0]),
    );
    await operation;
  });

  test('synchronizes only status endpoints for a status-only grant', () async {
    final profile = _profileWithAuthoritativeStatusEndpoints();
    final codec = EvtProtocolCodec();
    final transport = FakeBleTransport(
      profile: profile,
      services: _servicesFor(profile),
      readValuesByCharacteristicUuid: {
        _fb11: FakeBleTransport.validBatteryFrame,
        _fa15: codec.encodeRequest(0x85, const [0, 1, 0, 0, 128, 0, 0, 0]),
      },
    );
    final controller = SessionController(transport, profile, codec);
    addTearDown(controller.dispose);

    await controller.connect(FakeBleTransport.matchingCandidate);
    await _completeAuthenticatedSession(controller, transport);
    final configurationWriteCount = transport.writes
        .map((bytes) => codec.decode(bytes).value!.command)
        .where((command) => command == 0x02)
        .length;

    final synchronized = controller.synchronizeAfterAuthentication(const {
      DevicePermission.status,
    });
    await _respondToCommand(
      transport,
      codec,
      command: 0x06,
      subCommand: 0x01,
      response: codec.encodeRequest(0x86, const [0x01, 0, 5, 0, 0, 0, 1, 0]),
    );
    await synchronized;

    final commands = transport.writes
        .map((bytes) => codec.decode(bytes).value!)
        .map((frame) => frame.command)
        .toList();
    expect(commands, contains(0x06));
    expect(
      commands.where((command) => command == 0x02),
      hasLength(configurationWriteCount),
    );
    expect(commands, isNot(contains(0x21)));
  });

  test(
    'rejects authenticated device-info synchronization when MTU cannot carry a V3 0x81 indication',
    () async {
      for (final mtu in <int>[23, 99, 106, 135]) {
        final profile = _profileWithDeviceInfo();
        final transport = FakeBleTransport(
          profile: profile,
          deferRead: true,
          negotiatedMtu: mtu,
          services: _servicesFor(profile),
        );
        final controller = SessionController(
          transport,
          profile,
          EvtProtocolCodec(),
        );
        addTearDown(controller.dispose);
        addTearDown(transport.dispose);

        await controller.connect(FakeBleTransport.matchingCandidate);

        await expectLater(
          controller.synchronizeAfterAuthentication(const {}),
          throwsA(isA<BleTransportException>()),
          reason: 'mtu=$mtu',
        );
        expect(transport.requestedMtus, <int>[517], reason: 'mtu=$mtu');
        expect(controller.state.phase, SessionPhase.interrupted);
        expect(transport.writes, isEmpty, reason: 'mtu=$mtu');
      }
    },
  );

  test(
    'admits V3 at the 136-byte maximum 0x81 indication MTU boundary',
    () async {
      final profile = _profileWithDeviceInfo();
      final transport = FakeBleTransport(
        profile: profile,
        deferRead: true,
        negotiatedMtu: 136,
        services: _servicesFor(profile),
      );
      final controller = SessionController(
        transport,
        profile,
        EvtProtocolCodec(),
      );
      addTearDown(controller.dispose);
      addTearDown(transport.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);
      final synchronized = controller.synchronizeAfterAuthentication(const {});
      await Future<void>.delayed(Duration.zero);
      transport.emitSubscriptionBytes(_deviceInfoFrame(protocolVersion: 3));
      await _respondToCommand(
        transport,
        EvtProtocolCodec(),
        command: 0x02,
        response: EvtProtocolCodec().encodeRequest(0x82, const [1]),
      );
      await synchronized;

      expect(transport.requestedMtus, <int>[517]);
      expect(controller.state.phase, SessionPhase.observable);
    },
  );

  test(
    'loads only authenticated status, configuration and file details once',
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

      expect(controller.state.phase, SessionPhase.authenticationReady);
      expect(controller.state.deviceBattery, isNull);
      expect(controller.state.deviceStorage, isNull);
      expect(controller.state.deviceStatus, isNull);
      expect(controller.state.fileCount, isNull);

      final synchronized = controller.synchronizeAfterAuthentication(const {
        DevicePermission.status,
        DevicePermission.configuration,
        DevicePermission.files,
      });
      await _respondToCommand(
        transport,
        codec,
        command: 0x01,
        response: _deviceInfoFrame(protocolVersion: 3),
      );
      await _respondToCommand(
        transport,
        codec,
        command: 0x02,
        response: codec.encodeRequest(0x82, const [1]),
      );
      await _respondToCommand(
        transport,
        codec,
        command: 0x06,
        subCommand: 0x01,
        response: codec.encodeRequest(0x86, const [0x01, 0, 5, 1, 15, 0, 1, 0]),
      );
      await _respondToCommand(
        transport,
        codec,
        command: 0x02,
        response: codec.encodeRequest(0x82, const [0x80, 0x96, 0x98, 0x66]),
      );
      await _respondToCommand(
        transport,
        codec,
        command: 0x06,
        subCommand: 0x03,
        response: codec.encodeRequest(0x86, const [0x03, 0, 1, 2]),
      );
      await synchronized;

      expect(controller.state.deviceBattery?.percent, 80);
      expect(controller.state.deviceStorage?.totalMegabytes, 256);
      expect(controller.state.deviceStorage?.freeMegabytes, 128);
      expect(controller.state.deviceStatus?.privacy, isTrue);
      expect(controller.state.deviceStatus?.privacyRemainingMinutes, 15);
      expect(controller.state.privacyDurationCode, 2);
      expect(controller.state.fileCount, 3);
      expect(
        transport.writes
            .map((bytes) => codec.decode(bytes).value!)
            .where((frame) => frame.command == 0x06),
        hasLength(2),
      );
    },
  );

  test(
    'authentication synchronization writes the V1.5 baseline configuration',
    () async {
      final profile = _profileWithAuthoritativeStatusEndpoints();
      final codec = EvtProtocolCodec();
      final transport = FakeBleTransport(
        profile: profile,
        services: _servicesFor(profile),
      );
      final controller = SessionController(transport, profile, codec);
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);

      final synchronized = controller.synchronizeAfterAuthentication(const {});
      await _respondToCommand(
        transport,
        codec,
        command: 0x01,
        response: _deviceInfoFrame(
          protocolVersion: 3,
          powerOff: 1,
          chargingMode: 1,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final configuration = codec.decode(transport.writes.last).value!;
      expect(
        transport.writes
            .map((bytes) => codec.decode(bytes).value!.command)
            .toList(),
        <int>[0x01, 0x02],
      );
      expect(configuration.content, hasLength(12));
      expect(configuration.content.sublist(4), <int>[
        0x08,
        0x07,
        1,
        2,
        0,
        1,
        1,
        0,
      ]);
      transport.emitSubscriptionBytes(codec.encodeRequest(0x82, const [1]));
      await synchronized;
    },
  );

  test(
    'authentication synchronization clears a stale realtime audio flag',
    () async {
      final profile = _profileWithAuthoritativeStatusEndpoints();
      final codec = EvtProtocolCodec();
      final transport = FakeBleTransport(
        profile: profile,
        services: _servicesFor(profile),
      );
      final controller = SessionController(transport, profile, codec);
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);

      final synchronized = controller.synchronizeAfterAuthentication(const {});
      await _respondToCommand(
        transport,
        codec,
        command: 0x01,
        response: _deviceInfoFrame(
          protocolVersion: 3,
          audioStreamEnabled: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final configuration = codec.decode(transport.writes.last).value!;
      expect(configuration.command, 0x02);
      expect(configuration.content[11], 0);

      transport.emitSubscriptionBytes(codec.encodeRequest(0x82, const [1]));
      await synchronized;
    },
  );

  test(
    'rejects a device missing the required V1.5 configuration channel',
    () async {
      final profile = _profileWithDeviceInfo();
      final transport = FakeBleTransport(
        profile: profile,
        services: _servicesFor(
          profile,
          operationOverrides: const {BleLogicalEndpoint.fa10Fa12: {}},
        ),
      );
      final controller = SessionController(
        transport,
        profile,
        EvtProtocolCodec(),
      );
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);

      expect(controller.state.phase, SessionPhase.interrupted);
      expect(
        transport.disconnectedDeviceIds,
        contains(FakeBleTransport.matchingCandidate.connectionId),
      );
    },
  );

  test(
    'reads protected status through the V1.5 FA16 indication endpoint',
    () async {
      final profile = _profileWithAuthoritativeStatusEndpoints();
      final codec = EvtProtocolCodec();
      final transport = FakeBleTransport(
        profile: profile,
        deferRead: true,
        services: _servicesFor(profile),
      );
      final controller = SessionController(transport, profile, codec);
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);
      await _completeAuthenticatedSession(controller, transport);

      final status = controller.readStatus();
      await _respondToCommand(
        transport,
        codec,
        command: 0x06,
        subCommand: 0x01,
        response: codec.encodeRequest(0x86, const [0x01, 0, 5, 0, 0, 0, 1, 0]),
      );

      expect((await status).recordConsent, isTrue);
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

  test('rejects a V1.5 core GATT profile when FA16 cannot indicate', () async {
    final profile = _profileWithDeviceInfo();
    final transport = FakeBleTransport(
      profile: profile,
      deferRead: true,
      services: _servicesFor(
        profile,
        operationOverrides: const {
          BleLogicalEndpoint.fa10Fa16: {
            BleOperation.write,
            BleOperation.notify,
          },
        },
      ),
    );
    final controller = SessionController(
      transport,
      profile,
      EvtProtocolCodec(),
    );
    addTearDown(controller.dispose);

    await controller.connect(FakeBleTransport.matchingCandidate);

    expect(controller.state.phase, SessionPhase.interrupted);
    expect(controller.state.failure?.kind.name, 'access');
  });

  test('rejects a V1.5 core GATT profile when FA11 cannot indicate', () async {
    final profile = _profileWithDeviceInfo();
    final transport = FakeBleTransport(
      profile: profile,
      deferRead: true,
      services: _servicesFor(
        profile,
        operationOverrides: const {
          BleLogicalEndpoint.fa10Fa11: {BleOperation.write},
        },
      ),
    );
    final controller = SessionController(
      transport,
      profile,
      EvtProtocolCodec(),
    );
    addTearDown(controller.dispose);

    await controller.connect(FakeBleTransport.matchingCandidate);

    expect(controller.state.phase, SessionPhase.interrupted);
    expect(controller.state.failure?.kind.name, 'access');
    expect(
      transport.disconnectedDeviceIds,
      contains(FakeBleTransport.matchingCandidate.connectionId),
    );
  });

  test(
    'invalid authenticated device information interrupts the session',
    () async {
      final transport = FakeBleTransport.withGattReadyProfile();
      final controller = SessionController(
        transport,
        transport.profile,
        EvtProtocolCodec(),
      );
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);
      final synchronized = controller.synchronizeAfterAuthentication(const {});
      await Future<void>.delayed(Duration.zero);
      transport.emitSubscriptionBytes(const [
        0xED,
        0x03,
        0x00,
        0x91,
        0x00,
        0x00,
      ]);
      await expectLater(synchronized, throwsA(anything));

      expect(controller.state.phase, SessionPhase.interrupted);
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
      final synchronized = controller.synchronizeAfterAuthentication(const {});
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.phase, SessionPhase.authenticationReady);
      expect(transport.writes, hasLength(1));

      transport.emitSubscriptionBytes(_deviceInfoFrame(protocolVersion: 2));
      await expectLater(synchronized, throwsA(isA<BleTransportException>()));

      expect(controller.state.phase, SessionPhase.interrupted);
      expect(controller.state.failure?.kind.name, 'protocol');
      expect(
        transport.disconnectedDeviceIds,
        contains(FakeBleTransport.matchingCandidate.connectionId),
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
    'does not use a realtime endpoint that indicates instead of notifying',
    () async {
      final profile = _profileWithRealtimeAudio();
      final transport = FakeBleTransport(
        profile: profile,
        deferRead: true,
        services: _servicesFor(
          profile,
          operationOverrides: const {
            BleLogicalEndpoint.fa10Fa18: {BleOperation.indicate},
          },
        ),
      );
      final controller = SessionController(
        transport,
        profile,
        EvtProtocolCodec(),
      );
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);
      await _completeAuthenticatedSession(controller, transport);

      expect(controller.subscribeRealtimeAudio, throwsStateError);
      expect(
        transport.subscribedCharacteristics.map(
          (characteristic) => characteristic.characteristicUuid,
        ),
        isNot(contains(_fa18)),
      );
    },
  );

  test(
    'sends a file-chunk request through the V3-approved ATT MTU without a second negotiation',
    () async {
      final profile = _profileWithFileDownload();
      final transport = FakeBleTransport(
        profile: profile,
        deferRead: true,
        negotiatedMtu: 136,
        services: _servicesFor(profile),
      );
      final controller = SessionController(
        transport,
        profile,
        EvtProtocolCodec(),
      );
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);
      await _completeAuthenticatedSession(controller, transport);
      final read = controller.readFileChunk(nameSlot: _fileNameSlot);
      await _respondToCommand(
        transport,
        EvtProtocolCodec(),
        command: 0x23,
        response: EvtProtocolCodec().encodeRequest(0x23, const [
          0,
          0,
          0,
          0,
          0,
          0,
        ]),
      );
      await expectLater(read, completion(isEmpty));

      expect(transport.requestedMtus, [517]);
      expect(
        transport.writes.map(
          (bytes) => EvtProtocolCodec().decode(bytes).value!.command,
        ),
        contains(0x23),
      );
    },
  );

  test('enables realtime audio from the V1.5 baseline configuration', () async {
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
    await _completeAuthenticatedSession(controller, transport);
    final RealtimeAudioGateway gateway = controller;

    expect(
      transport.subscribedCharacteristics.map(
        (characteristic) => characteristic.characteristicUuid,
      ),
      isNot(contains(_fa18)),
    );

    final subscription = gateway.subscribeRealtimeAudio().listen((_) {});
    addTearDown(subscription.cancel);

    expect(transport.subscribedCharacteristics.last.characteristicUuid, _fa18);

    final configure = gateway.setAudioStreamEnabled(true);
    await _respondToCommand(
      transport,
      codec,
      command: 0x02,
      response: codec.encodeRequest(0x82, const [1]),
    );
    await _respondToCommand(
      transport,
      codec,
      command: 0x02,
      response: codec.encodeRequest(0x82, const [0x80, 0x96, 0x98, 0x66]),
    );
    await configure;

    final configuration = transport.writes
        .map((bytes) => codec.decode(bytes).value!)
        .where((frame) => frame.command == 0x02 && frame.content.length == 12)
        .last;
    expect(configuration.content.last, 1);

    final startRecording = gateway.setRealtimeRecording(true);
    transport.emitSubscriptionBytes(codec.encodeRequest(0x87, const [1]));
    await startRecording;

    expect(codec.decode(transport.writes.last).value!.command, 0x07);
    expect(codec.decode(transport.writes.last).value!.content, [1]);
  });

  test(
    'changes only AudioStream when a complete recording configuration was already written',
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
      await _completeAuthenticatedSession(controller, transport);
      final configured = controller.writeConfiguration(
        DeviceConfiguration(
          systemTime: DateTime.utc(2026, 9, 2, 10),
          recordDurationSeconds: 777,
          recordMode: 3,
          recordType: 4,
          denoise: true,
          powerOff: 7,
          chargingMode: 2,
          audioStreamEnabled: false,
        ),
      );
      await _respondToCommand(
        transport,
        codec,
        command: 0x02,
        response: codec.encodeRequest(0x82, const [1]),
      );
      await _respondToCommand(
        transport,
        codec,
        command: 0x02,
        response: codec.encodeRequest(0x82, const [0x80, 0x96, 0x98, 0x66]),
      );
      await configured;

      final streamEnabled = (controller as RealtimeAudioGateway)
          .setAudioStreamEnabled(true);
      await _respondToCommand(
        transport,
        codec,
        command: 0x02,
        response: codec.encodeRequest(0x82, const [1]),
      );
      await _respondToCommand(
        transport,
        codec,
        command: 0x02,
        response: codec.encodeRequest(0x82, const [0x80, 0x96, 0x98, 0x66]),
      );
      await streamEnabled;

      final configuration = transport.writes
          .map((bytes) => codec.decode(bytes).value!)
          .where((frame) => frame.command == 0x02 && frame.content.length == 12)
          .last;
      expect(configuration.content.sublist(4), const [9, 3, 3, 4, 1, 7, 2, 1]);
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
      await _completeAuthenticatedSession(controller, transport);
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
        contains(FakeBleTransport.matchingCandidate.connectionId),
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
    await _completeAuthenticatedSession(controller, transport);
    expect(controller.state.phase, SessionPhase.observable);

    transport.emitSubscriptionError(StateError('notification closed'));
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.phase, SessionPhase.interrupted);
    expect(
      transport.disconnectedDeviceIds,
      contains(FakeBleTransport.matchingCandidate.connectionId),
    );
  });

  test(
    'keeps the authentication channel ready when protected reads would fail',
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

      expect(controller.state.phase, SessionPhase.authenticationReady);
      expect(transport.readCharacteristics, isEmpty);
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
      BleLogicalEndpoint.fa10Fa19: const BleEndpoint(
        serviceUuid: fa10,
        characteristicUuid: '0000FA19-1212-EFDE-1523-785FEABCD123',
        operations: {BleOperation.write, BleOperation.indicate},
      ),
      BleLogicalEndpoint.fa10Fa12: const BleEndpoint(
        serviceUuid: fa10,
        characteristicUuid: _fa12,
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
      BleLogicalEndpoint.fa10Fa12: const BleEndpoint(
        serviceUuid: _fa10,
        characteristicUuid: _fa12,
        operations: {BleOperation.write, BleOperation.indicate},
      ),
      BleLogicalEndpoint.fa10Fa16: const BleEndpoint(
        serviceUuid: _fa10,
        characteristicUuid: _fa16,
        operations: {BleOperation.indicate, BleOperation.write},
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

DeviceProfile _profileWithFileDownload() {
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
      BleLogicalEndpoint.ff10Ff13: const BleEndpoint(
        serviceUuid: _ff10,
        characteristicUuid: _ff13,
        operations: {BleOperation.write, BleOperation.notify},
      ),
    },
  );
}

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

List<BleService> _servicesFor(
  DeviceProfile profile, {
  Map<BleLogicalEndpoint, Set<BleOperation>> operationOverrides = const {},
}) {
  Set<BleOperation> operationsFor(
    BleLogicalEndpoint endpoint,
    Set<BleOperation> fallback,
  ) =>
      operationOverrides[endpoint] ??
      profile.endpoints[endpoint]?.operations ??
      fallback;

  return [
    BleService(
      uuid: _fa10,
      characteristics: [
        BleDiscoveredCharacteristic(
          uuid: '0000FA11-1212-EFDE-1523-785FEABCD123',
          operations: operationsFor(BleLogicalEndpoint.fa10Fa11, const {
            BleOperation.write,
            BleOperation.indicate,
          }),
        ),
        BleDiscoveredCharacteristic(
          uuid: '0000FA19-1212-EFDE-1523-785FEABCD123',
          operations: operationsFor(BleLogicalEndpoint.fa10Fa19, const {
            BleOperation.write,
            BleOperation.indicate,
          }),
        ),
        BleDiscoveredCharacteristic(
          uuid: '0000FA16-1212-EFDE-1523-785FEABCD123',
          operations: operationsFor(BleLogicalEndpoint.fa10Fa16, const {
            BleOperation.write,
            BleOperation.indicate,
          }),
        ),
        BleDiscoveredCharacteristic(
          uuid: _fa15,
          operations: operationsFor(BleLogicalEndpoint.fa10Fa15, const {
            BleOperation.read,
            BleOperation.indicate,
          }),
        ),
        BleDiscoveredCharacteristic(
          uuid: _fa12,
          operations: operationsFor(BleLogicalEndpoint.fa10Fa12, const {
            BleOperation.read,
            BleOperation.write,
            BleOperation.indicate,
          }),
        ),
        BleDiscoveredCharacteristic(
          uuid: _fa17,
          operations: operationsFor(BleLogicalEndpoint.fa10Fa17, const {
            BleOperation.write,
            BleOperation.indicate,
          }),
        ),
        BleDiscoveredCharacteristic(
          uuid: _fa18,
          operations: operationsFor(BleLogicalEndpoint.fa10Fa18, const {
            BleOperation.notify,
          }),
        ),
      ],
    ),
    BleService(
      uuid: _fb10Service,
      characteristics: [
        BleDiscoveredCharacteristic(
          uuid: _fb11,
          operations: operationsFor(BleLogicalEndpoint.fb10Fb11, const {
            BleOperation.read,
            BleOperation.indicate,
          }),
        ),
      ],
    ),
    if (profile.endpoints.containsKey(BleLogicalEndpoint.ff10Ff11) ||
        profile.endpoints.containsKey(BleLogicalEndpoint.ff10Ff13))
      BleService(
        uuid: _ff10,
        characteristics: [
          if (profile.endpoints.containsKey(BleLogicalEndpoint.ff10Ff11))
            BleDiscoveredCharacteristic(
              uuid: _ff11,
              operations: operationsFor(BleLogicalEndpoint.ff10Ff11, const {
                BleOperation.read,
                BleOperation.indicate,
              }),
            ),
          if (profile.endpoints.containsKey(BleLogicalEndpoint.ff10Ff13))
            BleDiscoveredCharacteristic(
              uuid: _ff13,
              operations: operationsFor(BleLogicalEndpoint.ff10Ff13, const {
                BleOperation.write,
                BleOperation.notify,
              }),
            ),
        ],
      ),
    if (profile.endpoints.containsKey(BleLogicalEndpoint.wqota2002))
      BleService(
        uuid: '00007033-0000-1000-8000-00805F9B34FB',
        characteristics: [
          BleDiscoveredCharacteristic(
            uuid: '00002002-0000-1000-8000-00805F9B34FB',
            operations: operationsFor(BleLogicalEndpoint.wqota2002, const {
              BleOperation.notify,
            }),
          ),
        ],
      ),
  ];
}

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
const _ff13 = '0000FF13-1212-EFDE-1523-785FEABCD123';

const _fileNameSlot = <int>[
  0x36,
  0x61,
  0x37,
  0x62,
  0x65,
  0x37,
  0x30,
  0x34,
  0x5F,
  0x30,
  0x30,
  0x31,
  0x2E,
  0x6F,
  0x67,
  0x67,
  0,
];

List<int> _deviceInfoFrame({
  required int protocolVersion,
  int powerOff = 0,
  int chargingMode = 0,
  bool audioStreamEnabled = false,
}) {
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
  content[87] = powerOff;
  content[88] = chargingMode;
  content[89] = audioStreamEnabled ? 1 : 0;
  return EvtProtocolCodec().encodeRequest(0x81, content);
}

Future<void> _completeAuthenticatedSession(
  SessionController controller,
  FakeBleTransport transport,
) async {
  final synchronized = controller.synchronizeAfterAuthentication(const {});
  await Future<void>.delayed(Duration.zero);
  transport.emitSubscriptionBytes(_deviceInfoFrame(protocolVersion: 3));
  await _respondToCommand(
    transport,
    EvtProtocolCodec(),
    command: 0x02,
    response: EvtProtocolCodec().encodeRequest(0x82, const [1]),
  );
  await synchronized;
}

Future<void> _respondToCommand(
  FakeBleTransport transport,
  EvtProtocolCodec codec, {
  required int command,
  int? subCommand,
  required List<int> response,
}) async {
  await Future<void>.delayed(Duration.zero);
  final request = codec.decode(transport.writes.last).value!;
  expect(request.command, command);
  if (subCommand != null) {
    expect(request.content.first, subCommand);
  }
  transport.emitSubscriptionBytes(response);
}
