import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/ble/device_profile.dart';
import 'package:aipin/core/protocol/evt_command_client.dart';
import 'package:aipin/core/protocol/evt_frame.dart';
import 'package:aipin/core/protocol/evt_protocol_codec.dart';
import 'package:aipin/features/device_session/data/device_protocol_repository.dart';
import 'package:aipin/features/device_session/domain/device_configuration.dart';
import 'package:aipin/features/device_session/domain/evt_legacy_security_gateway.dart';
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

  test(
    'decodes the V1.6 pre-authenticated fixed 90-byte redacted response',
    () {
      final content = _deviceInfoContent()
        ..fillRange(74, 90, 0)
        ..[0] = 3;

      final info = DeviceProtocolRepository.decodeDeviceInfo(
        EvtFrame(command: 0x81, content: Uint8List.fromList(content)),
      );

      expect(info.capabilities.protocolVersion, 3);
      expect(info.deviceCode, 'SN202608130001');
      expect(info.deviceName, 'AIPIN_8423');
      expect(info.totalDiskSpaceMb, 0);
      expect(info.remainDiskSpaceMb, 0);
      expect(info.recordStatus, 0);
      expect(info.batteryLevel, 0);
      expect(info.charging, 0);
      expect(info.powerOff, 0);
      expect(info.chargingMode, 0);
    },
  );

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
      () => DeviceProtocolRepository.decodeBattery(
        EvtFrame(command: 0x91, content: Uint8List.fromList([100, 2, 0])),
      ),
      throwsFormatException,
    );
    expect(
      DeviceProtocolRepository.decodeFileCount(
        EvtFrame(command: 0xA1, content: Uint8List.fromList([2, 0])),
      ),
      2,
    );
  });

  test('rejects malformed conditional V1.5 device-information layouts', () {
    final active = _deviceInfoContent(recordStatus: 1);
    expect(
      DeviceProtocolRepository.decodeDeviceInfo(
        EvtFrame(command: 0x81, content: Uint8List.fromList(active)),
      ).recordStatus,
      1,
    );

    expect(
      () => DeviceProtocolRepository.decodeDeviceInfo(
        EvtFrame(
          command: 0x81,
          // V1.5 defines AudioStream as 0=off and non-zero=on. Do not
          // reject a firmware-specific non-zero enabled value.
          content: Uint8List.fromList(_deviceInfoContent(audioStream: 2)),
        ),
      ),
      returnsNormally,
    );

    final activeWithAlternateRecordParameters = _deviceInfoContent(
      recordStatus: 2,
      recordType: 1,
      denoise: 1,
    );
    expect(
      DeviceProtocolRepository.decodeDeviceInfo(
        EvtFrame(
          command: 0x81,
          content: Uint8List.fromList(activeWithAlternateRecordParameters),
        ),
      ).recordStatus,
      2,
    );

    final compatibilityLayout = _deviceInfoContent(
      reservedFeatureStatus: 1,
      recordStatus: 2,
    );
    expect(
      DeviceProtocolRepository.decodeDeviceInfo(
        EvtFrame(
          command: 0x81,
          content: Uint8List.fromList(compatibilityLayout),
        ),
      ).recordStatus,
      2,
    );

    final invalidChargingState = _deviceInfoContent()..[85] = 2;
    expect(
      () => DeviceProtocolRepository.decodeDeviceInfo(
        EvtFrame(
          command: 0x81,
          content: Uint8List.fromList(invalidChargingState),
        ),
      ),
      throwsFormatException,
    );

    final extraByte = _deviceInfoContent(recordStatus: 1)..add(0);
    final missingByte = _deviceInfoContent(recordStatus: 1)..removeLast();
    final invalidRecordStatus = _deviceInfoContent()..[83] = 4;
    final invalidBattery = _deviceInfoContent()..[84] = 101;
    final invalidCharging = _deviceInfoContent()..[85] = 3;
    final invalidBuzzer = _deviceInfoContent()..[86] = 2;
    final invalidPowerOff = _deviceInfoContent()..[87] = 2;
    final invalidChargingMode = _deviceInfoContent()..[88] = 2;
    final invalidActiveRecordType = _deviceInfoContent(
      recordStatus: 1,
      recordType: 0,
    );
    final invalidActiveDenoise = _deviceInfoContent(
      recordStatus: 1,
      denoise: 2,
    );

    for (final content in [
      extraByte,
      missingByte,
      invalidRecordStatus,
      invalidBattery,
      invalidCharging,
      invalidBuzzer,
      invalidPowerOff,
      invalidChargingMode,
      invalidActiveRecordType,
      invalidActiveDenoise,
    ]) {
      expect(
        () => DeviceProtocolRepository.decodeDeviceInfo(
          EvtFrame(command: 0x81, content: Uint8List.fromList(content)),
        ),
        throwsFormatException,
      );
    }
  });

  test('does not read the battery tail as an error code for 0x81 ERROR', () {
    final info = DeviceProtocolRepository.decodeDeviceInfo(
      EvtFrame(
        command: 0x81,
        content: Uint8List.fromList(_deviceInfoContent(recordStatus: 0xFF)),
      ),
    );

    expect(info.recordStatus, 0xFF);
    expect(info.errorCode, isNull);
    expect(info.batteryLevel, 80);
    expect(info.charging, 1);
  });

  test('rejects inconsistent storage capacity values in EVT responses', () {
    final impossibleDeviceInfo = _deviceInfoContent()
      ..[74] = 1
      ..[75] = 0
      ..[76] = 0
      ..[77] = 0
      ..[78] = 2
      ..[79] = 0
      ..[80] = 0
      ..[81] = 0;

    expect(
      () => DeviceProtocolRepository.decodeDeviceInfo(
        EvtFrame(
          command: 0x81,
          content: Uint8List.fromList(impossibleDeviceInfo),
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => DeviceProtocolRepository.decodeStorage(
        EvtFrame(
          command: 0x85,
          content: Uint8List.fromList(const [1, 0, 0, 0, 2, 0, 0, 0]),
        ),
      ),
      throwsFormatException,
    );
  });

  test('preserves the exact 0x85 storage response bytes', () async {
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
    final operation = repository.readStorageFrame();
    await Future<void>.delayed(Duration.zero);
    final response = codec.encodeRequest(0x85, const [
      0x00,
      0x01,
      0x00,
      0x00,
      0x80,
      0x00,
      0x00,
      0x00,
    ]);
    transport.emitSubscriptionBytes(response);

    expect(await operation, orderedEquals(response));
    await client.close();
  });

  test('rejects invalid device-information fixed-slot padding', () {
    final nonZeroAfterDeviceCodeNul = _deviceInfoContent()
      ..[3] = 0
      ..[4] = 0x58;
    final nonZeroAfterNameNul = _deviceInfoContent()..[56] = 0x58;
    final nameOverMaximum = _deviceInfoContent()
      ..fillRange(45, 45 + 28, 0x41)
      ..[45 + 28] = 0;

    for (final content in [
      nonZeroAfterDeviceCodeNul,
      nonZeroAfterNameNul,
      nameOverMaximum,
    ]) {
      expect(
        () => DeviceProtocolRepository.decodeDeviceInfo(
          EvtFrame(command: 0x81, content: Uint8List.fromList(content)),
        ),
        throwsFormatException,
      );
    }
  });

  test('rejects invalid EVT status booleans and sync-state enums', () {
    for (final content in [
      <int>[0x01, 0, 5, 2, 0, 0, 1, 0],
      <int>[0x01, 0, 5, 0, 0, 0, 2, 0],
      <int>[0x80, 0, 5, 0, 0, 0, 1, 4],
    ]) {
      expect(
        () => content.first == 0x80
            ? DeviceProtocolRepository.decodeStatusEvent(
                EvtFrame(command: 0x86, content: Uint8List.fromList(content)),
              )
            : DeviceProtocolRepository.decodeStatus(
                EvtFrame(command: 0x86, content: Uint8List.fromList(content)),
              ),
        throwsFormatException,
      );
    }
  });

  test('rejects invalid charging enums in 0x91 battery frames', () {
    for (final content in [
      <int>[80, 3, 0],
      <int>[80, 1, 2],
    ]) {
      expect(
        () => DeviceProtocolRepository.decodeBattery(
          EvtFrame(command: 0x91, content: Uint8List.fromList(content)),
        ),
        throwsFormatException,
      );
    }
  });

  test('validates 0x87 state-dependent lengths and active-record enums', () {
    expect(
      () => DeviceProtocolRepository.validateRecordState(
        EvtFrame(command: 0x87, content: Uint8List.fromList([0])),
      ),
      returnsNormally,
    );
    expect(
      () => DeviceProtocolRepository.validateRecordState(
        EvtFrame(
          command: 0x87,
          content: Uint8List.fromList([1, 8, 7, 0, 0, 1, 2, 0]),
        ),
      ),
      returnsNormally,
    );
    expect(
      () => DeviceProtocolRepository.validateRecordState(
        EvtFrame(
          command: 0x87,
          content: Uint8List.fromList([2, 8, 7, 0, 0, 1, 1, 1]),
        ),
      ),
      returnsNormally,
    );

    for (final content in [
      <int>[],
      <int>[4],
      <int>[0, 0],
      <int>[1],
      // V1.6 fixes RecordMode to the existing value 1.
      <int>[1, 8, 7, 0, 0, 2, 2, 0],
      <int>[1, 8, 7, 0, 0, 1, 0, 0],
      <int>[1, 8, 7, 0, 0, 1, 2, 2],
    ]) {
      expect(
        () => DeviceProtocolRepository.validateRecordState(
          EvtFrame(command: 0x87, content: Uint8List.fromList(content)),
        ),
        throwsFormatException,
      );
    }
  });

  test(
    'surfaces a valid V1.6 0x87 error response instead of timing out',
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

      final operation = repository.setRecordAction(1);
      await Future<void>.delayed(Duration.zero);
      final errorFrame = codec.encodeRequest(0x87, const [0xFF, 0xFF, 0xFF]);
      transport.emitSubscriptionBytes(errorFrame);

      await expectLater(
        operation,
        throwsA(
          isA<EvtRecordActionException>()
              .having((error) => error.action, 'action', 1)
              .having((error) => error.errorCode, 'errorCode', -1)
              .having((error) => error.frame.command, 'frame command', 0x87),
        ),
      );
      expect(
        DeviceProtocolRepository.recordStateErrorCode(
          EvtFrame(
            command: 0x87,
            content: Uint8List.fromList(const [0xFF, 0x00, 0x80]),
          ),
        ),
        -32768,
      );
      await client.close();
    },
  );

  test('rejects a file-list page whose Count exceeds the EVT limit', () {
    expect(
      () => DeviceProtocolRepository.decodeFileList(
        EvtFrame(
          command: 0xA2,
          content: Uint8List.fromList([21, ...List<int>.filled(21 * 21, 0)]),
        ),
      ),
      throwsFormatException,
    );
  });

  test('writes the complete 12-byte EVT configuration payload', () async {
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
        audioStream: 0,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(transport.writes, hasLength(1));
    final written = codec.decode(transport.writes.single).value!;
    expect(written.command, 0x02);
    expect(written.content, hasLength(12));
    expect(written.content.last, 0);
    transport.emitSubscriptionBytes(codec.encodeRequest(0x82, const [1]));
    await operation;
    await client.close();
  });

  test('rejects a nonzero AudioStream value before writing in EVT', () async {
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

    await expectLater(
      repository.writeConfiguration(
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
          audioStream: 1,
        ),
      ),
      throwsFormatException,
    );
    expect(transport.writes, isEmpty);
    await client.close();
  });

  test('rejects an invalid V1.6 configuration enum before writing', () async {
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

    await expectLater(
      repository.writeConfiguration(
        DeviceConfiguration(
          systemTime: DateTime.fromMillisecondsSinceEpoch(
            1_726_000_000_000,
            isUtc: true,
          ),
          recordDurationSeconds: 1800,
          recordMode: 1,
          recordType: 3,
          denoise: false,
          powerOff: 0,
          chargingMode: 0,
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(transport.writes, isEmpty);
    await client.close();
  });

  test('rejects a non-fixed V1.6 record mode before writing', () async {
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

    await expectLater(
      repository.writeConfiguration(
        DeviceConfiguration(
          systemTime: DateTime.fromMillisecondsSinceEpoch(
            1_726_000_000_000,
            isUtc: true,
          ),
          recordDurationSeconds: 1800,
          recordMode: 2,
          recordType: 2,
          denoise: false,
          powerOff: 0,
          chargingMode: 0,
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(transport.writes, isEmpty);
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

  test('reads the device UTC through the documented FA12 GATT Read', () async {
    final transport = FakeBleTransport(
      readValuesByCharacteristicUuid: {
        _profile.endpoint(BleLogicalEndpoint.fa10Fa12).characteristicUuid: codec
            .encodeRequest(0x82, const [0x80, 0x96, 0x98, 0x66]),
      },
    );
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

    expect(
      await repository.readConfigurationTime(),
      DateTime.fromMillisecondsSinceEpoch(1_721_276_032_000, isUtc: true),
    );
    expect(transport.writes, isEmpty);
    expect(transport.readCharacteristics, hasLength(1));
    expect(
      transport.readCharacteristics.single.characteristicUuid,
      _profile.endpoint(BleLogicalEndpoint.fa10Fa12).characteristicUuid,
    );
    await client.close();
  });

  test(
    'rejects a malformed FA12 GATT Read response while reading UTC',
    () async {
      final transport = FakeBleTransport(
        readValuesByCharacteristicUuid: {
          _profile.endpoint(BleLogicalEndpoint.fa10Fa12).characteristicUuid:
              codec.encodeRequest(0x82, const [0x01]),
        },
      );
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

      await expectLater(
        repository.readConfigurationTime(),
        throwsA(isA<FormatException>()),
      );
      expect(transport.writes, isEmpty);
      await client.close();
    },
  );

  test(
    'retries an idempotent GATT Read exactly once after a timeout',
    () async {
      final transport = FakeBleTransport(deferRead: true);
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
        gattReadTimeout: const Duration(milliseconds: 10),
      );

      await expectLater(
        repository.readConfigurationTime(),
        throwsA(isA<TimeoutException>()),
      );
      expect(transport.readCharacteristics, hasLength(2));
      expect(
        transport.readCharacteristics.map(
          (characteristic) => characteristic.characteristicUuid,
        ),
        everyElement(
          _profile.endpoint(BleLogicalEndpoint.fa10Fa12).characteristicUuid,
        ),
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

  test('rejects 0x06 responses outside the documented EVT layout', () async {
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

    final setConsent = repository.setRecordConsent(true);
    await Future<void>.delayed(Duration.zero);
    transport.emitSubscriptionBytes(
      codec.encodeRequest(0x86, const [0x02, 0, 1, 0]),
    );
    await expectLater(setConsent, throwsFormatException);

    final readPrivacyDuration = repository.readPrivacyDuration();
    await Future<void>.delayed(Duration.zero);
    transport.emitSubscriptionBytes(
      codec.encodeRequest(0x86, const [0x03, 0, 1, 4]),
    );
    await expectLater(readPrivacyDuration, throwsFormatException);
    await client.close();
  });

  test(
    'rejects a file-list response that exceeds the requested page size',
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

      final operation = repository.listFiles(pageSize: 1);
      await Future<void>.delayed(Duration.zero);
      transport.emitSubscriptionBytes(
        codec.encodeRequest(0xA2, [
          2,
          ...'6a7be704_001.ogg'.codeUnits,
          0,
          1,
          0,
          0,
          0,
          ...'6a7be704_002.ogg'.codeUnits,
          0,
          2,
          0,
          0,
          0,
        ]),
      );
      await expectLater(operation, throwsFormatException);
      await client.close();
    },
  );

  test(
    'does not retry a timed-out file-list page without an echoed page offset',
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
        fileListResponseTimeout: const Duration(milliseconds: 10),
      );

      await expectLater(
        repository.listFiles(),
        throwsA(isA<EvtCommandTimeoutException>()),
      );

      expect(transport.writes, hasLength(1));
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

      final events = <Object>[];
      final completed = repository
          .downloadEvtFile(nameSlot: nameSlot)
          .forEach(events.add);
      await Future<void>.delayed(Duration.zero);
      expect(transport.writes, hasLength(1));
      transport.emitSubscriptionBytes(
        codec.encodeRequest(0xA3, const [0, 0, 0, 0, 2, 0, 1, 2]),
      );
      transport.emitSubscriptionBytes(
        codec.encodeRequest(0xA3, const [2, 0, 0, 0, 1, 0, 3]),
      );
      transport.emitSubscriptionBytes(
        codec.encodeRequest(0xA3, const [3, 0, 0, 0, 0, 0]),
      );

      await completed;
      expect(events, hasLength(3));
      expect((events[0] as dynamic).bytes, <int>[1, 2]);
      expect((events[1] as dynamic).bytes, <int>[3]);
      expect((events[2] as dynamic).isTerminal, isTrue);
      expect(transport.writes, hasLength(1));
      await client.close();
    },
  );

  test('rejects a file name slot that is not exactly 17 bytes', () async {
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

    await expectLater(
      repository
          .downloadEvtFile(nameSlot: <int>[...'capture.ogg'.codeUnits, 0])
          .toList(),
      throwsA(isA<FormatException>()),
    );
    expect(transport.writes, isEmpty);
    await client.close();
  });

  test('decodes the V1.6 cloud hex security code into six BLE bytes', () async {
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

    final operation = repository.executeEvtLegacySecurity(
      EvtLegacySecurityRequest(
        action: EvtLegacySecurityAction.authenticate,
        securityCode: '313233343536',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(transport.writes.single, <int>[
      0xED,
      0x0A,
      0x00,
      0x09,
      0x00,
      0x31,
      0x32,
      0x33,
      0x34,
      0x35,
      0x36,
      0xD3,
      0x48,
    ]);
    transport.emitSubscriptionBytes(codec.encodeRequest(0x89, const [0x01]));

    expect(await operation, isTrue);
    await client.close();
  });

  test(
    'encodes every V1.6 security action as one action byte plus six raw bytes',
    () {
      for (final action in EvtLegacySecurityAction.values) {
        final request = EvtLegacySecurityRequest(
          action: action,
          securityCode: '7A31C85E92B4',
        );

        expect(request.content, <int>[
          action.wireValue,
          0x7A,
          0x31,
          0xC8,
          0x5E,
          0x92,
          0xB4,
        ]);
      }
    },
  );

  test('rejects malformed V1.6 cloud security-code hex values', () {
    expect(
      () => EvtLegacySecurityRequest(
        action: EvtLegacySecurityAction.authenticate,
        securityCode: '7A31C85E92B',
      ),
      throwsFormatException,
    );
    expect(
      () => EvtLegacySecurityRequest(
        action: EvtLegacySecurityAction.authenticate,
        securityCode: 'GGGGGGGGGGGG',
      ),
      throwsFormatException,
    );
  });

  test('ignores a malformed matching 0x87 record-state event', () async {
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

    final operation = repository.setRecordAction(1);
    var completed = false;
    operation.then((_) => completed = true);
    await Future<void>.delayed(Duration.zero);
    transport.emitSubscriptionBytes(
      codec.encodeRequest(0x87, const [1, 8, 7, 0, 0, 1, 9, 0]),
    );
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);

    transport.emitSubscriptionBytes(
      codec.encodeRequest(0x87, const [1, 8, 7, 0, 0, 1, 2, 0]),
    );
    expect((await operation).content.first, 1);
    await client.close();
  });

  test(
    'waits for the requested 0x87 state instead of an unsolicited event',
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
      final operation = repository.setRecordAction(1);
      var completed = false;
      operation.then((_) => completed = true);

      await Future<void>.delayed(Duration.zero);
      transport.emitSubscriptionBytes(codec.encodeRequest(0x87, const [0]));
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      transport.emitSubscriptionBytes(
        codec.encodeRequest(0x87, const [1, 8, 7, 0, 0, 1, 2, 0]),
      );
      final response = await operation;
      expect(response.content.first, 1);
      expect(completed, isTrue);
      await client.close();
    },
  );
}

final _profile = DeviceProfile(
  namePrefix: 'AIPIN',
  manufacturerPrefixHex: 'A389',
  serviceUuid: '0000AF30-0000-1000-8000-00805F9B34FB',
  gattServiceUuid: '0000FA10-0000-1000-8000-00805F9B34FB',
  endpoints: {
    BleLogicalEndpoint.fa10Fa11: _endpoint('FA10', 'FA11', {
      BleOperation.write,
    }),
    BleLogicalEndpoint.fa10Fa12: _endpoint('FA10', 'FA12', {
      BleOperation.read,
      BleOperation.write,
    }),
    BleLogicalEndpoint.fa10Fa15: _endpoint('FA10', 'FA15', {
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

List<int> _deviceInfoContent({
  int reservedFeatureStatus = 0,
  int recordStatus = 0,
  int recordType = 2,
  int denoise = 0,
  int audioStream = 0,
}) {
  final content = <int>[
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
    0,
    1,
    0,
    0,
    0x80,
    0,
    0,
    0,
    reservedFeatureStatus,
  ];
  if (reservedFeatureStatus != 0) {
    content.addAll(List<int>.filled(30, 0));
  }
  content.add(recordStatus);
  if (recordStatus == 1 || recordStatus == 2) {
    content.addAll([8, 7, 0, 0, 1, recordType, denoise]);
  }
  content.addAll([80, 1, 0, 0, 0, audioStream]);
  return content;
}
