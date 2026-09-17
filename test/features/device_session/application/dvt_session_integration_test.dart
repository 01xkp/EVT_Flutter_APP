import 'dart:typed_data';

import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/ble/device_profile.dart';
import 'package:aipin/core/protocol/evt_protocol_codec.dart';
import 'package:aipin/core/protocol/wqota_codec.dart';
import 'package:aipin/features/device_session/application/session_controller.dart';
import 'package:aipin/features/device_session/domain/evt_legacy_security_gateway.dart';
import 'package:aipin/features/device_session/domain/evt_unbind_preflight.dart';
import 'package:aipin/features/device_session/domain/firmware_package.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_ble_transport.dart';

final _slot = [...'6a7be704_001.ogg'.codeUnits, 0];

void main() {
  test(
    'small actual MTU refuses fixed audio block without starting recording',
    () async {
      final transport = _DvtPeripheral(mtu: 185);
      final session = SessionController(
        transport,
        transport.profile,
        EvtProtocolCodec(),
      );
      addTearDown(() async {
        await session.close();
        session.dispose();
        await transport.dispose();
      });
      await session.connect(FakeBleTransport.matchingCandidate);
      await _authenticate(session);
      await expectLater(
        session.startDvtAudioProbe(),
        throwsA(
          isA<StateError>().having((e) => e.message, 'reason', contains('489')),
        ),
      );
      expect(transport.audioStream, 0);
      expect(transport.recordActions, isEmpty);
      expect(session.dvtTransferBusy, isFalse);
    },
  );

  test(
    'DVT metadata requires auth, receives only A6 from FF16 after CCC',
    () async {
      final transport = _DvtPeripheral();
      final session = SessionController(
        transport,
        transport.profile,
        EvtProtocolCodec(),
      );
      addTearDown(() async {
        await session.close();
        session.dispose();
        await transport.dispose();
      });
      await session.connect(FakeBleTransport.matchingCandidate);
      await expectLater(
        session.readDvtFileMetadata(nameSlot: _slot),
        throwsStateError,
      );
      expect(transport.commands, isNot(contains(0x26)));
      await _authenticate(session);
      final metadata = await session.readDvtFileMetadata(nameSlot: _slot);
      expect(metadata.fileSize, 9);
      expect(metadata.crc32, 0xCBF43926);
      expect(metadata.nameSlot, _slot);
      expect(transport.metadataCccReady, isTrue);
    },
  );

  test('DVT unbind rejects ready file and accepts reclaimable state', () async {
    final transport = _DvtPeripheral();
    final session = SessionController(
      transport,
      transport.profile,
      EvtProtocolCodec(),
    );
    addTearDown(() async {
      await session.close();
      session.dispose();
      await transport.dispose();
    });
    await session.connect(FakeBleTransport.matchingCandidate);
    await _authenticate(session);
    await expectLater(
      session.verifyDvtArchivePreflight(),
      throwsA(isA<EvtUnbindPreflightException>()),
    );
    transport.fileState = 4;
    await session.verifyDvtArchivePreflight();
    expect(transport.commands.where((cmd) => cmd == 0x09), hasLength(1));
  });

  test(
    'uncertain FF16 write closes the session before another A6 request',
    () async {
      final transport = _DvtPeripheral();
      final session = SessionController(
        transport,
        transport.profile,
        EvtProtocolCodec(),
      );
      addTearDown(() async {
        await session.close();
        session.dispose();
        await transport.dispose();
      });
      await session.connect(FakeBleTransport.matchingCandidate);
      await _authenticate(session);
      transport.failMetadataWrite = true;

      await expectLater(
        session.readDvtFileMetadata(nameSlot: _slot),
        throwsStateError,
      );

      expect(session.state.hasActiveBleConnection, isFalse);
      transport.failMetadataWrite = false;
      await expectLater(
        session.readDvtFileMetadata(nameSlot: _slot),
        throwsStateError,
      );
      expect(transport.commands.where((cmd) => cmd == 0x26), hasLength(1));
    },
  );

  test(
    'audio CCC precedes stream config; only 88 delivered, stop restores config',
    () async {
      final transport = _DvtPeripheral();
      final session = SessionController(
        transport,
        transport.profile,
        EvtProtocolCodec(),
      );
      addTearDown(() async {
        await session.close();
        session.dispose();
        await transport.dispose();
      });
      await session.connect(FakeBleTransport.matchingCandidate);
      await _authenticate(session);
      final received = <Uint8List>[];
      final sub = session.dvtAudioPayloads.listen(received.add);
      addTearDown(sub.cancel);
      await session.startDvtAudioProbe();
      expect(transport.audioCccBeforeEnable, isTrue);
      transport.audio(0x87, [1]);
      // A corrupt declared length must not hold the FA18 parser indefinitely
      // now that partial binary payloads are no longer scanned for ED heads.
      transport.emitSubscriptionBytesForCharacteristic(
        transport.profile
            .endpoint(BleLogicalEndpoint.fa10Fa18)
            .characteristicUuid,
        Uint8List.fromList([0xED, 0xFF, 0x7F, 0x88]),
      );
      transport.audio(0x88, [1, 2, 3]);
      await Future<void>.delayed(Duration.zero);
      expect(received, [
        Uint8List.fromList([1, 2, 3]),
      ]);
      await expectLater(
        session.readDvtFileMetadata(nameSlot: _slot),
        throwsStateError,
      );
      await session.stopDvtAudioProbe();
      expect(transport.audioStream, 0);
      expect(transport.recordActions, [1, 0]);
    },
  );

  test(
    'file gateway created in old connection cannot act after reconnect',
    () async {
      final transport = _DvtPeripheral();
      final session = SessionController(
        transport,
        transport.profile,
        EvtProtocolCodec(),
      );
      addTearDown(() async {
        await session.close();
        session.dispose();
        await transport.dispose();
      });
      await session.connect(FakeBleTransport.matchingCandidate);
      await _authenticate(session);
      final gateway = SessionDvtFileGateway(session);
      await session.disconnect();
      await session.connect(FakeBleTransport.matchingCandidate);
      await _authenticate(session);
      expect(
        () => gateway.readDvtFileMetadata(nameSlot: _slot),
        throwsStateError,
      );
      await expectLater(
        gateway.downloadEvtFile(nameSlot: _slot).drain<void>(),
        throwsStateError,
      );
      expect(() => gateway.listFiles(offset: 0, pageSize: 1), throwsStateError);
    },
  );

  test(
    'reconnect version verification does not reopen the WQOTA transport',
    () async {
      final transport = _DvtPeripheral();
      final session = SessionController(
        transport,
        transport.profile,
        EvtProtocolCodec(),
      );
      addTearDown(() async {
        await session.close();
        session.dispose();
        await transport.dispose();
      });
      await session.connect(FakeBleTransport.matchingCandidate);
      await _authenticate(session);

      final controller = await session.createDvtOtaVerificationController(
        _firmwarePackage(),
      );
      addTearDown(controller.dispose);

      expect(
        transport.notificationSetupRequests,
        isNot(
          contains(
            isA<BleCharacteristic>().having(
              (value) => value.characteristicUuid,
              'characteristic UUID',
              DeviceProfile.dvtV16()
                  .endpoint(BleLogicalEndpoint.wqota2002)
                  .characteristicUuid,
            ),
          ),
        ),
      );
    },
  );

  test('a stale OTA page cannot release a newer page transport', () async {
    final transport = _DvtPeripheral();
    final session = SessionController(
      transport,
      transport.profile,
      EvtProtocolCodec(),
    );
    addTearDown(() async {
      await session.close();
      session.dispose();
      await transport.dispose();
    });
    await session.connect(FakeBleTransport.matchingCandidate);
    await _authenticate(session);

    final first = await session.createDvtOtaController(_firmwarePackage());
    await session.releaseDvtOta(owner: first);
    final second = await session.createDvtOtaController(_firmwarePackage());

    await session.releaseDvtOta(owner: first);
    expect(session.dvtTransferBusy, isTrue);

    await session.releaseDvtOta(owner: second);
    expect(session.dvtTransferBusy, isFalse);
    first.dispose();
    second.dispose();
  });
}

FirmwarePackage _firmwarePackage() => FirmwarePackage(
  vendorId: 0x1234,
  productId: 0x5678,
  version: 2,
  expectedBusinessVersion: '1.0.2',
  payload: Uint8List.fromList(const <int>[1, 2, 3]),
  expectedPayloadCrc32: 0x55BC801D,
  wireFormat: WqotaWireFormat.captured(
    captureId: 'dvt-v1.6-target-capture-001',
    requestPrefixFlags: const <int>[0x70, 0x07, 0x6E, 0xC1],
    responsePrefixFlags: const <int>[0x70, 0x07, 0x6E, 0x01],
  ),
  finalVerificationSupported: true,
);

Future<void> _authenticate(SessionController session) async {
  expect(
    await session.executeEvtLegacySecurity(
      EvtLegacySecurityRequest(
        action: EvtLegacySecurityAction.authenticate,
        securityCode: '123456',
      ),
    ),
    isTrue,
  );
  await session.synchronizeAfterAuthentication(const {});
}

class _DvtPeripheral extends FakeBleTransport {
  _DvtPeripheral({int mtu = 517})
    : super(
        negotiatedMtu: mtu,
        profile: DeviceProfile.dvtV16(),
        services: _services(),
        autoRespondToPreAuthenticationDeviceInfo: false,
      );
  final codec = EvtProtocolCodec();
  final commands = <int>[];
  final recordActions = <int>[];
  bool metadataCccReady = false;
  bool failMetadataWrite = false;
  bool audioCccBeforeEnable = false;
  int audioStream = 0;
  int fileState = 1;

  static List<BleService> _services() {
    final endpoints = DeviceProfile.dvtV16().endpoints.values;
    return endpoints
        .map((e) => e.serviceUuid)
        .toSet()
        .map(
          (uuid) => BleService(
            uuid: uuid,
            characteristics: endpoints
                .where((e) => e.serviceUuid == uuid)
                .map(
                  (e) => BleDiscoveredCharacteristic(
                    uuid: e.characteristicUuid,
                    operations: e.operations,
                  ),
                )
                .toList(),
          ),
        )
        .toList();
  }

  void audio(int command, List<int> content) =>
      emitSubscriptionBytesForCharacteristic(
        profile.endpoint(BleLogicalEndpoint.fa10Fa18).characteristicUuid,
        codec.encodeRequest(command, content),
      );

  @override
  Future<Uint8List> read(BleCharacteristic characteristic) async =>
      codec.encodeRequest(0x91, [80, 0, 0]);

  @override
  Future<void> write(BleCharacteristic characteristic, Uint8List bytes) async {
    await super.write(characteristic, bytes);
    final frame = codec.decode(bytes).value!;
    commands.add(frame.command);
    List<int> content;
    switch (frame.command) {
      case 0x01:
        content = List.filled(90, 0);
        content[0] = 3;
        content.setRange(1, 14, 'SN202608130001'.codeUnits);
        content.setRange(21, 26, '1.0.0'.codeUnits);
        content.setRange(45, 55, 'AIPIN_8423'.codeUnits);
      case 0x02:
        audioStream = frame.content[11];
        if (audioStream == 1) {
          audioCccBeforeEnable = notificationSetupRequests.any(
            (c) =>
                c.characteristicUuid ==
                profile
                    .endpoint(BleLogicalEndpoint.fa10Fa18)
                    .characteristicUuid,
          );
        }
        content = [1];
      case 0x06:
        content = [1, 0, 5, 0, 0, 0, 1, 0];
      case 0x07:
        recordActions.add(frame.content.first);
        content = frame.content.first == 0 ? [0] : [1, 8, 7, 0, 0, 1, 2, 0];
      case 0x09:
        content = [1];
      case 0x22:
        content = frame.content.first == 0 ? [1, ..._slot, 9, 0, 0, 0] : [0];
      case 0x26:
        if (failMetadataWrite) {
          // Android/iOS may report a failed write callback even though the
          // peripheral accepted the bytes and its indication is still pending.
          throw StateError('FF16 native write callback failed');
        }
        metadataCccReady = notificationSetupRequests.any(
          (c) => c.characteristicUuid == characteristic.characteristicUuid,
        );
        final data = Uint8List(41)..setRange(0, 17, _slot);
        final view = ByteData.sublistView(data);
        view.setUint32(21, 1, Endian.little);
        view.setUint32(32, 9, Endian.little);
        view.setUint32(36, 0xCBF43926, Endian.little);
        data[40] = fileState;
        content = [1, 0, 41, ...data];
      default:
        throw StateError('Unexpected request ${frame.command}');
    }
    emitSubscriptionBytesForCharacteristic(
      characteristic.characteristicUuid,
      codec.encodeRequest(frame.command | 0x80, content),
    );
  }
}
