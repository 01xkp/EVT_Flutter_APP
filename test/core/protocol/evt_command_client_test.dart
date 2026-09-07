import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/protocol/evt_command_client.dart';
import 'package:aipin/core/protocol/evt_protocol_codec.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_ble_transport.dart';

void main() {
  const characteristic = BleCharacteristic(
    deviceId: 'device-1',
    serviceUuid: '0000FA10-0000-1000-8000-00805F9B34FB',
    characteristicUuid: '0000FA11-0000-1000-8000-00805F9B34FB',
  );

  test('matches a validated response and reports attempts', () async {
    final transport = FakeBleTransport();
    final codec = EvtProtocolCodec();
    final client = EvtCommandClient(
      transport: transport,
      codec: codec,
      responses: transport.subscriptionStream,
    );

    final future = client.execute(
      const EvtCommandRequest(
        command: 0x01,
        content: [0x10],
        writeCharacteristic: characteristic,
        timeout: Duration(milliseconds: 100),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    transport.emitSubscriptionBytes(codec.encodeRequest(0x81, const [0x00]));

    final response = await future;
    expect(response.frame.command, 0x81);
    expect(response.attempts, 1);
    expect(transport.writes, hasLength(1));
    await client.close();
  });

  test('publishes unmatched valid frames as unsolicited events', () async {
    final transport = FakeBleTransport();
    final client = EvtCommandClient(
      transport: transport,
      codec: EvtProtocolCodec(),
      responses: transport.subscriptionStream,
    );
    final events = <int>[];
    final eventSubscription = client.events.listen(
      (frame) => events.add(frame.command),
    );

    transport.emitSubscriptionBytes(
      EvtProtocolCodec().encodeRequest(0x86, const [0x01]),
    );
    await Future<void>.delayed(Duration.zero);
    expect(events, [0x86]);
    await eventSubscription.cancel();
    await client.close();
  });

  test('retries once after timeout and then fails', () async {
    final transport = FakeBleTransport();
    final client = EvtCommandClient(
      transport: transport,
      codec: EvtProtocolCodec(),
      responses: transport.subscriptionStream,
    );

    await expectLater(
      client.execute(
        const EvtCommandRequest(
          command: 0x06,
          writeCharacteristic: characteristic,
          timeout: Duration(milliseconds: 10),
        ),
      ),
      throwsA(isA<EvtCommandTimeoutException>()),
    );
    expect(transport.writes, hasLength(2));
    await client.close();
  });

  test(
    'serializes requests so the second write waits for the first response',
    () async {
      final transport = FakeBleTransport();
      final codec = EvtProtocolCodec();
      final client = EvtCommandClient(
        transport: transport,
        codec: codec,
        responses: transport.subscriptionStream,
      );

      final first = client.execute(
        const EvtCommandRequest(
          command: 0x06,
          writeCharacteristic: characteristic,
          timeout: Duration(milliseconds: 100),
        ),
      );
      final second = client.execute(
        const EvtCommandRequest(
          command: 0x07,
          writeCharacteristic: characteristic,
          timeout: Duration(milliseconds: 100),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(transport.writes, hasLength(1));
      transport.emitSubscriptionBytes(codec.encodeRequest(0x86, const []));
      await first;
      await Future<void>.delayed(Duration.zero);
      expect(transport.writes, hasLength(2));
      transport.emitSubscriptionBytes(codec.encodeRequest(0x87, const []));
      await second;
      await client.close();
    },
  );

  test(
    'keeps a response pending until its transaction matcher accepts it',
    () async {
      final transport = FakeBleTransport();
      final codec = EvtProtocolCodec();
      final client = EvtCommandClient(
        transport: transport,
        codec: codec,
        responses: transport.subscriptionStream,
      );
      final unsolicited = <int>[];
      final subscription = client.events.listen(
        (frame) => unsolicited.add(frame.content[2]),
      );

      final operation = client.execute(
        EvtCommandRequest(
          command: 0x09,
          writeCharacteristic: characteristic,
          responseMatcher: (frame) =>
              frame.content.length >= 6 && frame.content[2] == 7,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      transport.emitSubscriptionBytes(
        codec.encodeRequest(0x89, const [0xF2, 0x20, 8, 0, 0, 0, 0, 0]),
      );
      await Future<void>.delayed(Duration.zero);
      expect(unsolicited, [8]);
      transport.emitSubscriptionBytes(
        codec.encodeRequest(0x89, const [0xF2, 0x20, 7, 0, 0, 0, 0, 0]),
      );

      await expectLater(operation, completes);
      await subscription.cancel();
      await client.close();
    },
  );

  test(
    'holds one command open while continuous matching frames arrive',
    () async {
      final transport = FakeBleTransport();
      final codec = EvtProtocolCodec();
      final client = EvtCommandClient(
        transport: transport,
        codec: codec,
        responses: transport.subscriptionStream,
      );

      final frames = client.executeStreaming(
        const EvtCommandRequest(
          command: 0x23,
          content: [1, 0],
          writeCharacteristic: characteristic,
          expectedResponseCommand: 0x23,
        ),
        isTerminal: (frame) =>
            frame.content.length == 6 &&
            frame.content[4] == 0 &&
            frame.content[5] == 0,
      );
      final received = <List<int>>[];
      final done = frames.forEach((frame) => received.add(frame.content));

      await Future<void>.delayed(Duration.zero);
      expect(transport.writes, hasLength(1));
      transport.emitSubscriptionBytes(
        codec.encodeRequest(0x23, const [0, 0, 0, 0, 2, 0, 1, 2]),
      );
      transport.emitSubscriptionBytes(
        codec.encodeRequest(0x23, const [2, 0, 0, 0, 0, 0]),
      );

      await done;
      expect(received, <List<int>>[
        <int>[0, 0, 0, 0, 2, 0, 1, 2],
        <int>[2, 0, 0, 0, 0, 0],
      ]);
      await client.close();
    },
  );
}
