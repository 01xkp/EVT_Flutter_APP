import 'dart:typed_data';

import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/diagnostics/diagnostic_trace.dart';
import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/core/protocol/wqota_client.dart';
import 'package:aipin/core/protocol/wqota_codec.dart';
import 'package:aipin/features/device_session/data/wqota_ble_update_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_ble_transport.dart';

void main() {
  final codec = WqotaCodec(
    wireFormat: WqotaWireFormat.captured(
      captureId: 'dvt-v1.6-target-capture-001',
      requestPrefixFlags: const <int>[0x70, 0x07, 0x6E, 0xC1],
      responsePrefixFlags: const <int>[0x70, 0x07, 0x6E, 0x01],
    ),
  );

  test('derives the V1.6 E5 payload limit from ATT MTU', () {
    expect(WqotaBleUpdateGateway.maximumBlockBytesForMtu(23), 3);
    expect(WqotaBleUpdateGateway.maximumBlockBytesForMtu(517), 497);
    expect(WqotaBleUpdateGateway.maximumBlockBytesForMtu(900), 655);
  });

  test('stops sending E5 blocks after the response activity timeout', () async {
    final transport = _SlowWriteTransport();
    final client = WqotaClient(
      transport: transport,
      writeCharacteristic: WqotaGatt.writeCharacteristic('device-1'),
      notifications: transport.subscriptionStream,
      codec: codec,
      idleTimeout: const Duration(milliseconds: 5),
    );
    addTearDown(client.close);
    final gateway = WqotaBleUpdateGateway(
      client: client,
      requestMtu: () async => 517,
      verifyBusinessVersion: (_) async => true,
      finalVerificationSupported: true,
      maximumBlockBytes: 1,
    );
    await expectLater(
      gateway.transferWindow(offset: 18, bytes: Uint8List(3)),
      throwsA(isA<WqotaIdleTimeoutException>()),
    );
    expect(transport.writesWithoutResponse, hasLength(1));
  });

  test('sends an E5 block with big-endian offset and CRC32', () async {
    final transport = FakeBleTransport(negotiatedMtu: 517);
    final client = WqotaClient(
      transport: transport,
      writeCharacteristic: WqotaGatt.writeCharacteristic('device-1'),
      notifications: transport.subscriptionStream,
      codec: codec,
    );
    addTearDown(client.close);
    final gateway = WqotaBleUpdateGateway(
      client: client,
      requestMtu: () async => transport.negotiatedMtu,
      verifyBusinessVersion: (_) async => true,
      finalVerificationSupported: true,
    );

    await gateway.prepareTransport();
    final next = gateway.transferWindow(
      offset: 18,
      bytes: Uint8List.fromList(const <int>[0xAA, 0xBB, 0xCC]),
    );
    await Future<void>.delayed(Duration.zero);
    transport.emitSubscriptionBytes(
      _response(WqotaOpcode.sendFirmwareBlock, const <int>[
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ]),
    );

    final window = await next;
    expect(window.offset, 0);
    expect(window.length, 0);
    expect(transport.writesWithoutResponse, hasLength(1));
    final frame = transport.writesWithoutResponse.single;
    expect(frame.sublist(0, 7), <int>[0x70, 0x07, 0x6E, 0xC1, 0xE5, 0, 12]);
    expect(frame.sublist(7, 12), <int>[1, 0, 0, 0, 18]);
    expect(frame.sublist(12, 15), <int>[0xAA, 0xBB, 0xCC]);
    expect(frame.sublist(15, 19), <int>[0xBE, 0x4D, 0xF8, 0x4C]);
    expect(frame.last, 0x33);
  });

  test('requires E1 to return the fixed 0/18 header window', () async {
    final transport = FakeBleTransport();
    final client = WqotaClient(
      transport: transport,
      writeCharacteristic: WqotaGatt.writeCharacteristic('device-1'),
      notifications: transport.subscriptionStream,
      codec: codec,
    );
    addTearDown(client.close);
    final gateway = WqotaBleUpdateGateway(
      client: client,
      requestMtu: () async => 517,
      verifyBusinessVersion: (_) async => true,
      finalVerificationSupported: true,
    );

    final result = gateway.queryFileInfoOffset();
    await Future<void>.delayed(Duration.zero);
    transport.emitSubscriptionBytes(
      _response(WqotaOpcode.getFileInfoOffset, const <int>[
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        17,
      ]),
    );

    await expectLater(result, throwsA(isA<WqotaProtocolException>()));
  });

  test('cancels the E5 response wait when a native write fails', () async {
    final transport = _FailingWriteTransport();
    final logger = _RecordingLogger();
    final client = WqotaClient(
      transport: transport,
      writeCharacteristic: WqotaGatt.writeCharacteristic('device-1'),
      notifications: transport.subscriptionStream,
      codec: codec,
      logger: logger,
      idleTimeout: const Duration(milliseconds: 10),
    );
    addTearDown(client.close);
    final gateway = WqotaBleUpdateGateway(
      client: client,
      requestMtu: () async => 517,
      verifyBusinessVersion: (_) async => true,
      finalVerificationSupported: true,
    );
    await gateway.prepareTransport();

    await expectLater(
      gateway.transferWindow(
        offset: 18,
        bytes: Uint8List.fromList(const <int>[0xAA, 0xBB, 0xCC]),
      ),
      throwsA(isA<StateError>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(logger.events, contains('wqota_wait_cancelled'));
    expect(logger.events, isNot(contains('wqota_wait_timeout')));
  });
}

Uint8List _response(WqotaOpcode opcode, List<int> data) =>
    Uint8List.fromList(<int>[
      0x70,
      0x07,
      0x6E,
      0x01,
      opcode.value,
      (data.length >> 8) & 0xFF,
      data.length & 0xFF,
      ...data,
      0x33,
    ]);

class _FailingWriteTransport extends FakeBleTransport {
  @override
  Future<void> writeWithoutResponse(
    BleCharacteristic characteristic,
    Uint8List bytes,
  ) async {
    writesWithoutResponse.add(Uint8List.fromList(bytes));
    throw StateError('native WQOTA write failed');
  }
}

class _SlowWriteTransport extends FakeBleTransport {
  @override
  Future<void> writeWithoutResponse(
    BleCharacteristic characteristic,
    Uint8List bytes,
  ) async {
    writesWithoutResponse.add(Uint8List.fromList(bytes));
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

class _RecordingLogger implements SafeAppLogger {
  final events = <String>[];

  @override
  void error(
    String event, {
    DiagnosticTrace? trace,
    String? operation,
    String? stage,
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  }) => events.add(event);

  @override
  void info(
    String event, {
    DiagnosticTrace? trace,
    String? operation,
    String? stage,
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  }) => events.add(event);

  @override
  void warning(
    String event, {
    DiagnosticTrace? trace,
    String? operation,
    String? stage,
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  }) => events.add(event);
}
