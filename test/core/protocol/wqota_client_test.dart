import 'dart:async';
import 'dart:typed_data';

import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/protocol/wqota_client.dart';
import 'package:aipin/core/protocol/wqota_codec.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_ble_transport.dart';

void main() {
  final codec = WqotaCodec(
    wireFormat: WqotaWireFormat.captured(
      captureId: 'dvt-v1.6-target-capture-001',
      requestPrefixFlags: const <int>[0x70, 0x07, 0x6E, 0xC1],
      responsePrefixFlags: const <int>[0x70, 0x07, 0x6E, 0x01],
    ),
  );

  test(
    'writes one standalone WQOTA request and matches its echoed serial',
    () async {
      final transport = FakeBleTransport();
      final client = WqotaClient(
        transport: transport,
        writeCharacteristic: WqotaGatt.writeCharacteristic('device-1'),
        notifications: transport.subscriptionStream,
        codec: codec,
      );
      addTearDown(client.close);

      final response = client.execute(
        opcode: WqotaOpcode.getFileInfoOffset,
        data: const <int>[7],
        serialNumber: 7,
      );
      await Future<void>.delayed(Duration.zero);
      expect(transport.writesWithoutResponse, hasLength(1));
      transport.emitSubscriptionBytes(
        _response(WqotaOpcode.getFileInfoOffset, const <int>[
          0,
          7,
          0,
          0,
          0,
          18,
          0,
        ]),
      );

      expect((await response).data, <int>[0, 7, 0, 0, 0, 18, 0]);
    },
  );

  test(
    'times out after the V1.6 activity window without a valid response',
    () async {
      final transport = FakeBleTransport();
      final client = WqotaClient(
        transport: transport,
        writeCharacteristic: WqotaGatt.writeCharacteristic('device-1'),
        notifications: transport.subscriptionStream,
        codec: codec,
        idleTimeout: const Duration(milliseconds: 5),
      );
      addTearDown(client.close);

      await expectLater(
        client.execute(
          opcode: WqotaOpcode.getFileInfoOffset,
          data: const <int>[8],
          serialNumber: 8,
        ),
        throwsA(isA<WqotaIdleTimeoutException>()),
      );
    },
  );

  test(
    'propagates a Notify stream failure that arrives before a native write settles',
    () async {
      final notifications = StreamController<Uint8List>.broadcast();
      final transport = _DeferredWriteTransport();
      final client = WqotaClient(
        transport: transport,
        writeCharacteristic: WqotaGatt.writeCharacteristic('device-1'),
        notifications: notifications.stream,
        codec: codec,
      );
      addTearDown(() async {
        await client.close();
        await notifications.close();
      });

      final response = client.execute(
        opcode: WqotaOpcode.getFileInfoOffset,
        data: const <int>[9],
        serialNumber: 9,
      );
      await transport.writeStarted.future;
      notifications.addError(StateError('notify stream failed'));
      await Future<void>.delayed(Duration.zero);
      transport.completeWrite();

      await expectLater(
        response,
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            contains('notify stream failed'),
          ),
        ),
      );
    },
  );

  test('fails closed after the Notify stream ends', () async {
    final notifications = StreamController<Uint8List>.broadcast();
    final transport = FakeBleTransport();
    final client = WqotaClient(
      transport: transport,
      writeCharacteristic: WqotaGatt.writeCharacteristic('device-1'),
      notifications: notifications.stream,
      codec: codec,
    );
    addTearDown(() async {
      await client.close();
      await notifications.close();
    });

    final response = client.execute(
      opcode: WqotaOpcode.getFileInfoOffset,
      data: const <int>[10],
      serialNumber: 10,
    );
    await Future<void>.delayed(Duration.zero);
    await notifications.close();

    await expectLater(
      response,
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('notification stream closed unexpectedly'),
        ),
      ),
    );
    expect(
      () => client.execute(
        opcode: WqotaOpcode.getFileInfoOffset,
        data: const <int>[11],
        serialNumber: 11,
      ),
      throwsA(isA<StateError>()),
    );
    expect(transport.writesWithoutResponse, hasLength(1));
  });

  test('exposes the dedicated 0x7033 GATT endpoints', () {
    final write = WqotaGatt.writeCharacteristic('device-1');
    final notify = WqotaGatt.notifyCharacteristic('device-1');

    expect(write.serviceUuid, '00007033-0000-1000-8000-00805F9B34FB');
    expect(write.characteristicUuid, '00002001-0000-1000-8000-00805F9B34FB');
    expect(notify.characteristicUuid, '00002002-0000-1000-8000-00805F9B34FB');
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

class _DeferredWriteTransport extends FakeBleTransport {
  final writeStarted = Completer<void>();
  final _writeCompletion = Completer<void>();

  @override
  Future<void> writeWithoutResponse(
    BleCharacteristic characteristic,
    Uint8List bytes,
  ) {
    writesWithoutResponse.add(Uint8List.fromList(bytes));
    if (!writeStarted.isCompleted) {
      writeStarted.complete();
    }
    return _writeCompletion.future;
  }

  void completeWrite() {
    if (!_writeCompletion.isCompleted) {
      _writeCompletion.complete();
    }
  }
}
