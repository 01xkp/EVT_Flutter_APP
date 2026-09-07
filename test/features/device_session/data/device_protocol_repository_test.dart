import 'dart:convert';
import 'dart:typed_data';

import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/ble/device_profile.dart';
import 'package:aipin/core/protocol/evt_command_client.dart';
import 'package:aipin/core/protocol/evt_frame.dart';
import 'package:aipin/core/protocol/evt_protocol_codec.dart';
import 'package:aipin/features/device_session/data/device_protocol_repository.dart';
import 'package:aipin/features/device_session/domain/device_configuration.dart';
import 'package:aipin/features/device_session/domain/device_security_gateway.dart';
import 'package:aipin/features/device_session/domain/ticket_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_ble_transport.dart';

void main() {
  final codec = EvtProtocolCodec();

  test('decodes the documented device information response', () {
    final frame = EvtFrame(
      command: 0x81,
      content: Uint8List.fromList([
        3,
        ...'SN202608130001'.codeUnits,
        ...List<int>.filled(6, 0),
        ...'1.0.0'.codeUnits,
        ...List<int>.filled(3, 0),
        ...'A1'.codeUnits,
        ...List<int>.filled(6, 0),
        ...List<int>.filled(8, 0),
        ...'AIPIN_8423'.codeUnits,
        ...List<int>.filled(19, 0),
        0x00,
        0x01,
        0x00,
        0x00,
        0x80,
        0x00,
        0x00,
        0x00,
        0,
        0,
        0x50,
        0,
        0,
        1,
        1,
        0,
      ]),
    );

    final info = DeviceProtocolRepository.decodeDeviceInfo(frame);

    expect(info.capabilities.protocolVersion, 3);
    expect(info.deviceCode, 'SN202608130001');
    expect(info.deviceName, 'AIPIN_8423');
    expect(info.totalDiskSpaceMb, 256);
    expect(info.remainDiskSpaceMb, 128);
    expect(info.batteryLevel, 0x50);
    expect(info.powerOff, 1);
    expect(info.chargingMode, 1);
  });

  test('decodes the UTF-8 device name slot from the V1.5 device response', () {
    final frame = EvtFrame(
      command: 0x81,
      content: Uint8List.fromList([
        3,
        ...'SN202608130001'.codeUnits,
        ...List<int>.filled(6, 0),
        ...'1.0.0'.codeUnits,
        ...List<int>.filled(3, 0),
        ...'A1'.codeUnits,
        ...List<int>.filled(6, 0),
        ...List<int>.filled(8, 0),
        ...utf8.encode('\u58f0\u9875'),
        ...List<int>.filled(23, 0),
        0x00,
        0x01,
        0x00,
        0x00,
        0x80,
        0x00,
        0x00,
        0x00,
        0,
        0,
        0x50,
        0,
        0,
        1,
        1,
        0,
      ]),
    );

    expect(
      DeviceProtocolRepository.decodeDeviceInfo(frame).deviceName,
      '\u58f0\u9875',
    );
  });

  test('decodes status and paged file responses with strict lengths', () {
    final status = DeviceProtocolRepository.decodeStatus(
      EvtFrame(
        command: 0x86,
        content: Uint8List.fromList([0x01, 0, 5, 0, 0, 0, 1, 0]),
      ),
    );
    expect(status.recordConsent, isTrue);

    final statusEvent = DeviceProtocolRepository.decodeStatusEvent(
      EvtFrame(
        command: 0x86,
        content: Uint8List.fromList([0x80, 0, 5, 1, 0xFF, 0xFF, 0, 2]),
      ),
    );
    expect(statusEvent.privacy, isTrue);
    expect(statusEvent.privacyRemainingMinutes, 0xFFFF);
    expect(statusEvent.recordConsent, isFalse);
    expect(statusEvent.syncState, 2);

    final fileFrame = EvtFrame(
      command: 0xA2,
      content: Uint8List.fromList([
        1,
        ...'6a7be704_001.ogg'.codeUnits,
        0,
        0,
        0x20,
        0,
        0,
      ]),
    );
    final files = DeviceProtocolRepository.decodeFileList(fileFrame);
    expect(files.single.name, '6a7be704_001.ogg');
    expect(files.single.length, 8192);
    expect(files.single.nameSlot, hasLength(17));

    final battery = DeviceProtocolRepository.decodeBattery(
      EvtFrame(command: 0x91, content: Uint8List.fromList([80, 1, 0])),
    );
    expect(battery.percent, 80);
    expect(battery.isCharging, isTrue);
    expect(
      DeviceProtocolRepository.decodeFileCount(
        EvtFrame(command: 0xA1, content: Uint8List.fromList([2, 0])),
      ),
      2,
    );
  });

  test('writes the complete 12-byte configuration payload', () async {
    final transport = FakeBleTransport();
    final client = EvtCommandClient(
      transport: transport,
      codec: codec,
      responses: transport.subscriptionStream,
    );
    final repository = DeviceProtocolRepository(
      deviceId: 'device-1',
      profile: _profile,
      transport: transport,
      commands: client,
      codec: codec,
    );
    final operation = repository.writeConfiguration(
      DeviceConfiguration(
        systemTime: DateTime.fromMillisecondsSinceEpoch(
          1_726_000_000_000,
          isUtc: true,
        ),
        recordDurationSeconds: 1800,
        recordMode: 1,
        recordType: 2,
        denoise: false,
        powerOff: 0,
        chargingMode: 0,
        audioStreamEnabled: false,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(transport.writes, hasLength(1));
    final written = codec.decode(transport.writes.single).value!;
    expect(written.command, 0x02);
    expect(written.content, hasLength(12));
    transport.emitSubscriptionBytes(codec.encodeRequest(0x82, const [1]));
    await operation;
    await client.close();
  });

  test(
    'ignores a delayed UTC response while waiting for configuration acknowledgement',
    () async {
      final transport = FakeBleTransport();
      final client = EvtCommandClient(
        transport: transport,
        codec: codec,
        responses: transport.subscriptionStream,
      );
      final repository = DeviceProtocolRepository(
        deviceId: 'device-1',
        profile: _profile,
        transport: transport,
        commands: client,
        codec: codec,
      );

      final operation = repository.writeConfiguration(
        DeviceConfiguration(
          systemTime: DateTime.fromMillisecondsSinceEpoch(
            1_726_000_000_000,
            isUtc: true,
          ),
          recordDurationSeconds: 1800,
          recordMode: 1,
          recordType: 2,
          denoise: false,
          powerOff: 0,
          chargingMode: 0,
          audioStreamEnabled: false,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      transport.emitSubscriptionBytes(
        codec.encodeRequest(0x82, const [0x80, 0x96, 0x98, 0x66]),
      );
      transport.emitSubscriptionBytes(codec.encodeRequest(0x82, const [1]));

      await operation;
      await client.close();
    },
  );

  test('reads the device UTC with an empty 0x02 request', () async {
    final transport = FakeBleTransport();
    final client = EvtCommandClient(
      transport: transport,
      codec: codec,
      responses: transport.subscriptionStream,
    );
    final repository = DeviceProtocolRepository(
      deviceId: 'device-1',
      profile: _profile,
      transport: transport,
      commands: client,
      codec: codec,
    );

    final operation = repository.readConfigurationTime();
    await Future<void>.delayed(Duration.zero);

    final request = codec.decode(transport.writes.single).value!;
    expect(request.command, 0x02);
    expect(request.content, isEmpty);
    transport.emitSubscriptionBytes(
      codec.encodeRequest(0x82, const [0x80, 0x96, 0x98, 0x66]),
    );

    expect(
      await operation,
      DateTime.fromMillisecondsSinceEpoch(1_721_276_032_000, isUtc: true),
    );
    await client.close();
  });

  test(
    'ignores a stale configuration acknowledgement while reading UTC',
    () async {
      final transport = FakeBleTransport();
      final client = EvtCommandClient(
        transport: transport,
        codec: codec,
        responses: transport.subscriptionStream,
      );
      final repository = DeviceProtocolRepository(
        deviceId: 'device-1',
        profile: _profile,
        transport: transport,
        commands: client,
        codec: codec,
      );

      final operation = repository.readConfigurationTime();
      await Future<void>.delayed(Duration.zero);
      transport.emitSubscriptionBytes(codec.encodeRequest(0x82, const [1]));
      transport.emitSubscriptionBytes(
        codec.encodeRequest(0x82, const [0x80, 0x96, 0x98, 0x66]),
      );

      expect(
        await operation,
        DateTime.fromMillisecondsSinceEpoch(1_721_276_032_000, isUtc: true),
      );
      await client.close();
    },
  );

  test(
    'updates consent and privacy duration through their 0x06 subcommands',
    () async {
      final transport = FakeBleTransport();
      final client = EvtCommandClient(
        transport: transport,
        codec: codec,
        responses: transport.subscriptionStream,
      );
      final repository = DeviceProtocolRepository(
        deviceId: 'device-1',
        profile: _profile,
        transport: transport,
        commands: client,
        codec: codec,
      );

      final consent = repository.setRecordConsent(true);
      await Future<void>.delayed(Duration.zero);
      expect(codec.decode(transport.writes.single).value!.content, [
        0x02,
        0x01,
        1,
      ]);
      transport.emitSubscriptionBytes(
        codec.encodeRequest(0x86, const [0x02, 0, 0]),
      );
      await consent;

      final privacy = repository.setPrivacyDuration(3);
      await Future<void>.delayed(Duration.zero);
      expect(codec.decode(transport.writes.last).value!.content, [
        0x04,
        0x01,
        3,
      ]);
      transport.emitSubscriptionBytes(
        codec.encodeRequest(0x86, const [0x04, 0, 0]),
      );
      await privacy;
      await client.close();
    },
  );

  test(
    'confirms archive only with the documented size, CRC and success flag',
    () async {
      final transport = FakeBleTransport();
      final client = EvtCommandClient(
        transport: transport,
        codec: codec,
        responses: transport.subscriptionStream,
      );
      final repository = DeviceProtocolRepository(
        deviceId: 'device-1',
        profile: _profile,
        transport: transport,
        commands: client,
        codec: codec,
      );
      final nameSlot = <int>[
        ...'capture.m4a'.codeUnits,
        ...List<int>.filled(6, 0),
      ];
      final operation = repository.confirmArchive(
        nameSlot: nameSlot,
        fileSize: 8192,
        crc32: 0xCBF43926,
      );
      await Future<void>.delayed(Duration.zero);
      final written = codec.decode(transport.writes.single).value!;
      expect(written.command, 0x26);
      expect(written.content, hasLength(28));
      expect(written.content.first, 0x02);
      expect(written.content.last, 0x01);
      transport.emitSubscriptionBytes(
        codec.encodeRequest(0xA6, const [0x02, 0x00, 0x01, 0x04]),
      );
      await expectLater(operation, completion(4));
      await client.close();
    },
  );

  test(
    'rejects metadata returned for a different immutable file slot',
    () async {
      final transport = FakeBleTransport();
      final client = EvtCommandClient(
        transport: transport,
        codec: codec,
        responses: transport.subscriptionStream,
      );
      final repository = DeviceProtocolRepository(
        deviceId: 'device-1',
        profile: _profile,
        transport: transport,
        commands: client,
        codec: codec,
      );
      final requestedSlot = <int>[
        ...'capture.ogg'.codeUnits,
        ...List<int>.filled(6, 0),
      ];
      final returnedSlot = <int>[
        ...'other.ogg'.codeUnits,
        ...List<int>.filled(8, 0),
      ];
      final metadataData = <int>[...returnedSlot, ...List<int>.filled(28, 0)];
      metadataData[44] = 1;

      final operation = repository.readFileMetadata(requestedSlot);
      await Future<void>.delayed(Duration.zero);
      transport.emitSubscriptionBytes(
        codec.encodeRequest(0xA6, <int>[0x01, 0, 45, ...metadataData]),
      );

      await expectLater(operation, throwsA(isA<FormatException>()));
      await client.close();
    },
  );

  test(
    'downloads a file from one request followed by continuous notify frames',
    () async {
      final transport = FakeBleTransport();
      final client = EvtCommandClient(
        transport: transport,
        codec: codec,
        responses: transport.subscriptionStream,
      );
      final repository = DeviceProtocolRepository(
        deviceId: 'device-1',
        profile: _profile,
        transport: transport,
        commands: client,
        codec: codec,
      );
      final nameSlot = <int>[
        ...'capture.ogg'.codeUnits,
        ...List<int>.filled(6, 0),
      ];

      final bytes = <int>[];
      final completed = repository
          .downloadFile(nameSlot: nameSlot)
          .forEach(bytes.addAll);
      await Future<void>.delayed(Duration.zero);
      expect(transport.writes, hasLength(1));
      transport.emitSubscriptionBytes(
        codec.encodeRequest(0x23, const [0, 0, 0, 0, 2, 0, 1, 2]),
      );
      transport.emitSubscriptionBytes(
        codec.encodeRequest(0x23, const [2, 0, 0, 0, 1, 0, 3]),
      );
      transport.emitSubscriptionBytes(
        codec.encodeRequest(0x23, const [3, 0, 0, 0, 0, 0]),
      );

      await completed;
      expect(bytes, <int>[1, 2, 3]);
      expect(transport.writes, hasLength(1));
      await client.close();
    },
  );

  test(
    'uses the V2 envelope and exact transaction for device authentication',
    () async {
      final transport = FakeBleTransport();
      final client = EvtCommandClient(
        transport: transport,
        codec: codec,
        responses: transport.subscriptionStream,
      );
      final repository = DeviceProtocolRepository(
        deviceId: 'device-1',
        profile: _profile,
        transport: transport,
        commands: client,
        codec: codec,
      );

      final operation = repository.execute(
        const DeviceSecurityRequest(
          action: DeviceAuthAction.authenticate,
          transactionId: 7,
          data: [0xAA, 0xBB],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final request = codec.decode(transport.writes.single).value!;
      expect(request.command, 0x09);
      expect(request.content, <int>[0xF2, 0x20, 7, 0, 0, 0, 2, 0, 0xAA, 0xBB]);
      transport.emitSubscriptionBytes(
        codec.encodeRequest(0x89, const [0xF2, 0x20, 7, 0, 0, 0, 0, 1, 0, 0]),
      );

      final response = await operation;
      expect(response.action, DeviceAuthAction.authenticate);
      expect(response.transactionId, 7);
      expect(response.result, 0);
      expect(response.data, <int>[0]);
      await client.close();
    },
  );
}

final _profile = DeviceProfile(
  namePrefix: 'AIPIN',
  manufacturerPrefixHex: 'A389',
  serviceUuid: '0000AF30-0000-1000-8000-00805F9B34FB',
  gattServiceUuid: '0000FA10-0000-1000-8000-00805F9B34FB',
  readCharacteristicUuid: '0000FB11-0000-1000-8000-00805F9B34FB',
  notifyCharacteristicUuid: '0000FA16-0000-1000-8000-00805F9B34FB',
  writeCharacteristicUuid: '0000FA16-0000-1000-8000-00805F9B34FB',
  endpoints: {
    BleLogicalEndpoint.fa10Fa11: _endpoint('FA10', 'FA11', {
      BleOperation.write,
    }),
    BleLogicalEndpoint.fa10Fa12: _endpoint('FA10', 'FA12', {
      BleOperation.write,
    }),
    BleLogicalEndpoint.fa10Fa16: _endpoint('FA10', 'FA16', {
      BleOperation.write,
    }),
    BleLogicalEndpoint.fa10Fa17: _endpoint('FA10', 'FA17', {
      BleOperation.write,
    }),
    BleLogicalEndpoint.fa10Fa19: _endpoint('FA10', 'FA19', {
      BleOperation.write,
    }),
    BleLogicalEndpoint.ff10Ff12: _endpoint('FF10', 'FF12', {
      BleOperation.write,
    }),
    BleLogicalEndpoint.ff10Ff13: _endpoint('FF10', 'FF13', {
      BleOperation.write,
    }),
    BleLogicalEndpoint.ff10Ff16: _endpoint('FF10', 'FF16', {
      BleOperation.write,
    }),
  },
);

BleEndpoint _endpoint(
  String service,
  String characteristic,
  Set<BleOperation> operations,
) => BleEndpoint(
  serviceUuid: normalizeBleUuid(service),
  characteristicUuid: normalizeBleUuid(characteristic),
  operations: operations,
);
