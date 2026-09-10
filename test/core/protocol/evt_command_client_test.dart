import 'dart:async';
import 'dart:typed_data';

import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/diagnostics/diagnostic_trace.dart';
import 'package:aipin/core/diagnostics/safe_app_logger.dart';
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

  test(
    'wait heartbeat distinguishes native write and response, then stops',
    () async {
      final transport = _DeferredWriteBleTransport();
      final logger = _CapturingLogger();
      final client = EvtCommandClient(
        transport: transport,
        codec: EvtProtocolCodec(),
        responses: transport.subscriptionStream,
        logger: logger,
      );
      addTearDown(client.close);
      addTearDown(transport.completeWrite);
      final operation = client.execute(
        const EvtCommandRequest(
          command: 0x01,
          writeCharacteristic: characteristic,
          timeout: Duration(seconds: 6),
          maxRetries: 0,
        ),
      );
      operation.ignore();
      await transport.writeStarted;
      final writing = await logger.nextEvent('evt_response_waiting');
      expect(writing.fields['state'], 'write_pending');
      expect(writing.fields, isNot(contains('remaining_ms')));
      transport.completeWrite();
      final waiting = await logger.nextEvent('evt_response_waiting');
      expect(waiting.fields['state'], 'waiting_response');
      expect(waiting.fields['remaining_ms'], inInclusiveRange(0, 6000));
      expect(waiting.fields['expected_command'], '0x81');
      expect(waiting.fields['wait_id'], writing.fields['wait_id']);

      transport.emitSubscriptionBytes(
        EvtProtocolCodec().encodeRequest(0x81, [0]),
      );
      await operation;
      final terminal = logger.events.singleWhere(
        (event) => event.name == 'evt_response_wait_finished',
      );
      expect(terminal.fields['state'], 'success');
      final count = logger.events.length;
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(logger.events, hasLength(count));
    },
  );

  test('each timed out retry closes its own response wait', () async {
    final transport = FakeBleTransport();
    final logger = _CapturingLogger();
    final client = EvtCommandClient(
      transport: transport,
      codec: EvtProtocolCodec(),
      responses: transport.subscriptionStream,
      logger: logger,
    );
    addTearDown(client.close);
    await expectLater(
      client.execute(
        const EvtCommandRequest(
          command: 0x01,
          writeCharacteristic: characteristic,
          timeout: Duration(milliseconds: 20),
          maxRetries: 1,
        ),
      ),
      throwsA(isA<EvtCommandTimeoutException>()),
    );
    final terminal = logger.events
        .where((event) => event.name == 'evt_response_wait_finished')
        .toList();
    expect(terminal, hasLength(2));
    expect(terminal.map((event) => event.fields['attempt']), [1, 2]);
    expect(
      terminal.map((event) => event.fields['wait_id']).toSet(),
      hasLength(2),
    );
    expect(
      terminal.every((event) => event.fields['state'] == 'failed'),
      isTrue,
    );
    expect(
      terminal.every((event) => '${event.fields['reason']}'.contains('超时')),
      isTrue,
    );
  });

  test(
    'stream wait continues after a partial frame until the terminal frame',
    () async {
      final transport = FakeBleTransport();
      final logger = _CapturingLogger();
      final client = EvtCommandClient(
        transport: transport,
        codec: EvtProtocolCodec(),
        responses: transport.subscriptionStream,
        logger: logger,
      );
      addTearDown(client.close);
      final result = client
          .executeStreaming(
            const EvtCommandRequest(
              command: 0x23,
              writeCharacteristic: characteristic,
              maxRetries: 0,
            ),
            isTerminal: (frame) => frame.content.first == 0xFF,
            idleTimeout: const Duration(seconds: 4),
          )
          .toList();
      result.ignore();
      await Future<void>.delayed(Duration.zero);
      transport.emitSubscriptionBytes(
        EvtProtocolCodec().encodeRequest(0xA3, [1]),
      );
      final waiting = await logger.nextEvent('evt_response_waiting');
      expect(waiting.fields['response_count'], 1);
      expect(
        logger.events.where(
          (event) => event.name == 'evt_response_wait_finished',
        ),
        isEmpty,
      );
      transport.emitSubscriptionBytes(
        EvtProtocolCodec().encodeRequest(0xA3, [0xFF]),
      );
      expect(await result, hasLength(2));
      final terminal = logger.events.singleWhere(
        (event) => event.name == 'evt_response_wait_finished',
      );
      expect(terminal.fields['state'], 'success');
      expect(terminal.fields['response_count'], 2);
      final count = logger.events.length;
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(logger.events, hasLength(count));
    },
  );

  test('closing during native write ends response logging once', () async {
    final transport = _DeferredWriteBleTransport();
    final logger = _CapturingLogger();
    final client = EvtCommandClient(
      transport: transport,
      codec: EvtProtocolCodec(),
      responses: transport.subscriptionStream,
      logger: logger,
    );
    addTearDown(client.close);
    addTearDown(transport.completeWrite);
    final result = client.execute(
      const EvtCommandRequest(
        command: 0x01,
        writeCharacteristic: characteristic,
        maxRetries: 0,
      ),
    );
    result.ignore();
    await transport.writeStarted;
    await client.close();
    transport.completeWrite();
    await expectLater(result, throwsA(isA<StateError>()));
    final terminal = logger.events.singleWhere(
      (event) => event.name == 'evt_response_wait_finished',
    );
    expect(terminal.fields['state'], 'cancelled');
    expect(
      logger.events.map((event) => event.name),
      isNot(contains('evt_response_wait_armed')),
    );
  });

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

  test('accepts FA19 bind indication before native write completes', () async {
    final transport = _DeferredWriteBleTransport();
    final logger = _CapturingLogger();
    final client = EvtCommandClient(
      transport: transport,
      codec: EvtProtocolCodec(),
      responses: transport.subscriptionStream,
      logger: logger,
    );
    addTearDown(client.close);
    const bindingCharacteristic = BleCharacteristic(
      deviceId: 'device-1',
      serviceUuid: '0000FA10-0000-1000-8000-00805F9B34FB',
      characteristicUuid: '0000FA19-0000-1000-8000-00805F9B34FB',
    );
    final result = client.execute(
      const EvtCommandRequest(
        command: 0x09,
        content: [1, 0x30, 0x30, 0x30, 0x30, 0x30, 0x30],
        expectedResponseCommand: 0x89,
        writeCharacteristic: bindingCharacteristic,
        maxRetries: 0,
      ),
    );
    await transport.writeStarted;
    transport.emitSubscriptionBytes(
      Uint8List.fromList([0xED, 4, 0, 0x89, 1, 0x2E, 0xAC]),
    );
    await Future<void>.delayed(Duration.zero);
    transport.completeWrite();

    final response = await result;
    expect(response.frame.command, 0x89);
    expect(response.frame.content, [1]);
    expect(response.attempts, 1);
    final waitFinished = logger.events.singleWhere(
      (event) => event.name == 'evt_response_wait_finished',
    );
    expect(waitFinished.fields['state'], 'success');
    expect(waitFinished.fields['response_count'], 1);
    expect(
      logger.events.map((event) => event.name),
      isNot(contains('evt_response_wait_armed')),
    );
    expect(transport.writes, hasLength(1));
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

  for (final streaming in [false, true]) {
    test(
      'handles receive failure during native write (streaming=$streaming)',
      () async {
        final transport = _DeferredWriteBleTransport();
        final client = EvtCommandClient(
          transport: transport,
          codec: EvtProtocolCodec(),
          responses: transport.subscriptionStream,
        );
        addTearDown(client.close);
        final failure = StateError('Native indication subscription ended');
        const request = EvtCommandRequest(
          command: 0x09,
          writeCharacteristic: characteristic,
          maxRetries: 0,
        );
        final Future<Object?> operation = streaming
            ? client.executeStreaming(request, isTerminal: (_) => true).toList()
            : client.execute(request);
        final expectation = expectLater(operation, throwsA(same(failure)));
        await transport.writeStarted;
        transport.emitSubscriptionError(failure);
        await Future<void>.delayed(Duration.zero);
        transport.completeWrite();
        await expectation;
        expect(transport.writes, hasLength(1));
      },
    );
  }

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

  test('does not retry a command explicitly marked non-idempotent', () async {
    final transport = FakeBleTransport();
    final client = EvtCommandClient(
      transport: transport,
      codec: EvtProtocolCodec(),
      responses: transport.subscriptionStream,
    );

    await expectLater(
      client.execute(
        const EvtCommandRequest(
          command: 0x09,
          writeCharacteristic: characteristic,
          timeout: Duration(milliseconds: 10),
          maxRetries: 0,
        ),
      ),
      throwsA(isA<EvtCommandTimeoutException>()),
    );
    expect(transport.writes, hasLength(1));
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
    'does not write a queued command when write admission is revoked',
    () async {
      final transport = FakeBleTransport();
      final codec = EvtProtocolCodec();
      var admitted = true;
      final client = EvtCommandClient(
        transport: transport,
        codec: codec,
        responses: transport.subscriptionStream,
        beforeWrite: (_) {
          if (!admitted) {
            throw StateError('authorization expired');
          }
        },
      );

      final first = client.execute(
        const EvtCommandRequest(
          command: 0x01,
          writeCharacteristic: characteristic,
          timeout: Duration(milliseconds: 100),
        ),
      );
      final queued = client.execute(
        const EvtCommandRequest(
          command: 0x06,
          writeCharacteristic: characteristic,
          timeout: Duration(milliseconds: 100),
        ),
      );

      await Future<void>.delayed(Duration.zero);
      expect(transport.writes, hasLength(1));
      admitted = false;
      transport.emitSubscriptionBytes(codec.encodeRequest(0x81, const []));

      await first;
      await expectLater(queued, throwsA(isA<StateError>()));
      expect(transport.writes, hasLength(1));
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
    'holds one command open while continuous matching frames arrive without raw packet duplication',
    () async {
      final transport = FakeBleTransport();
      final codec = EvtProtocolCodec();
      final logger = _CapturingLogger();
      final client = EvtCommandClient(
        transport: transport,
        codec: codec,
        responses: transport.subscriptionStream,
        logger: logger,
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
      expect(
        logger.events.every(
          (event) => !event.fields.containsKey('raw_packet_hex'),
        ),
        isTrue,
      );
      await client.close();
    },
  );

  test('does not count delayed GATT writes as streaming idle time', () async {
    final transport = _DeferredWriteBleTransport();
    final codec = EvtProtocolCodec();
    final client = EvtCommandClient(
      transport: transport,
      codec: codec,
      responses: transport.subscriptionStream,
    );
    final operation = client
        .executeStreaming(
          const EvtCommandRequest(
            command: 0x23,
            writeCharacteristic: characteristic,
            expectedResponseCommand: 0x23,
          ),
          isTerminal: (_) => true,
          idleTimeout: const Duration(milliseconds: 20),
        )
        .drain<void>();

    await transport.writeStarted;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    transport.completeWrite();
    await Future<void>.delayed(Duration.zero);
    transport.emitSubscriptionBytes(
      codec.encodeRequest(0x23, const [0, 0, 0, 0, 0, 0]),
    );
    await expectLater(operation.timeout(const Duration(seconds: 1)), completes);
    await client.close();
  });

  test(
    'starts streaming idle timeout after the GATT write completes',
    () async {
      final transport = _DeferredWriteBleTransport();
      final client = EvtCommandClient(
        transport: transport,
        codec: EvtProtocolCodec(),
        responses: transport.subscriptionStream,
      );
      final error = Completer<Object>();
      final done = Completer<void>();

      final subscription = client
          .executeStreaming(
            const EvtCommandRequest(
              command: 0x23,
              writeCharacteristic: characteristic,
              expectedResponseCommand: 0x23,
            ),
            isTerminal: (_) => true,
            idleTimeout: const Duration(milliseconds: 20),
          )
          .listen(
            (_) {},
            onError: (Object value, StackTrace _) {
              if (!error.isCompleted) {
                error.complete(value);
              }
            },
            onDone: () {
              if (!done.isCompleted) {
                done.complete();
              }
            },
          );

      await transport.writeStarted;
      transport.completeWrite();
      await expectLater(
        error.future.timeout(const Duration(seconds: 1)),
        completion(isA<EvtCommandTimeoutException>()),
      );
      await done.future.timeout(const Duration(seconds: 1));
      await subscription.cancel();
      await client.close();
    },
  );

  test(
    'does not write a queued streaming command when write admission is revoked',
    () async {
      final transport = FakeBleTransport();
      final codec = EvtProtocolCodec();
      var admitted = true;
      final client = EvtCommandClient(
        transport: transport,
        codec: codec,
        responses: transport.subscriptionStream,
        beforeWrite: (_) {
          if (!admitted) {
            throw StateError('authorization expired');
          }
        },
      );

      final first = client.execute(
        const EvtCommandRequest(
          command: 0x01,
          writeCharacteristic: characteristic,
          timeout: Duration(milliseconds: 100),
        ),
      );
      final queued = client
          .executeStreaming(
            const EvtCommandRequest(
              command: 0x23,
              writeCharacteristic: characteristic,
              expectedResponseCommand: 0x23,
            ),
            isTerminal: (_) => true,
          )
          .drain<void>();

      await Future<void>.delayed(Duration.zero);
      expect(transport.writes, hasLength(1));
      admitted = false;
      transport.emitSubscriptionBytes(codec.encodeRequest(0x81, const []));

      await first;
      await expectLater(queued, throwsA(isA<StateError>()));
      expect(transport.writes, hasLength(1));
      await client.close();
    },
  );

  test(
    'logs queue, transmit, receive, and matched control-frame summaries without raw packet duplication',
    () async {
      final transport = FakeBleTransport();
      final codec = EvtProtocolCodec();
      final logger = _CapturingLogger();
      final client = EvtCommandClient(
        transport: transport,
        codec: codec,
        responses: transport.subscriptionStream,
        logger: logger,
      );

      final operation = client.execute(
        const EvtCommandRequest(
          command: 0x07,
          content: [0x01],
          writeCharacteristic: characteristic,
          timeout: Duration(milliseconds: 100),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      transport.emitSubscriptionBytes(codec.encodeRequest(0x87, const [0x01]));

      await operation;

      expect(
        logger.events.map((event) => event.name),
        containsAll(<String>[
          'evt_command_queued',
          'evt_command_transmit_started',
          'evt_command_transmit_completed',
          'evt_command_frame_decoded',
          'evt_command_response_received',
          'evt_command_response_matched',
          'evt_command_completed',
          'evt_response_wait_started',
          'evt_response_wait_armed',
          'evt_response_wait_finished',
        ]),
      );
      final transmit = logger.events.firstWhere(
        (event) => event.name == 'evt_command_transmit_started',
      );
      expect(
        transmit.fields['frame_summary'],
        'evt_control cmd=0x07 content=01',
      );
      expect(transmit.fields['wire_summary'], contains('ED 04 00 07 01'));
      final acknowledgement = logger.events.firstWhere(
        (event) => event.name == 'evt_command_response_matched',
      );
      expect(acknowledgement.fields['event_kind'], 'acknowledged');
      expect(acknowledgement.fields['wait_id'], transmit.fields['wait_id']);
      final decoded = logger.events.firstWhere(
        (event) => event.name == 'evt_command_frame_decoded',
      );
      expect(decoded.fields.containsKey('raw_packet_hex'), isFalse);
      expect(
        logger.events.every(
          (event) => !event.fields.containsKey('raw_packet_hex'),
        ),
        isTrue,
      );

      await client.close();
    },
  );

  test(
    'logs unmatched frames and timeouts with a redacted authentication summary only',
    () async {
      final transport = FakeBleTransport();
      final codec = EvtProtocolCodec();
      final logger = _CapturingLogger();
      final client = EvtCommandClient(
        transport: transport,
        codec: codec,
        responses: transport.subscriptionStream,
        logger: logger,
      );

      final operation = client.execute(
        const EvtCommandRequest(
          command: 0x09,
          content: [0x02, 0xDE, 0xAD, 0xBE, 0xEF, 0xFA, 0xCE],
          writeCharacteristic: characteristic,
          timeout: Duration(milliseconds: 10),
          maxRetries: 0,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      transport.emitSubscriptionBytes(codec.encodeRequest(0x87, const [0x01]));

      await expectLater(operation, throwsA(isA<EvtCommandTimeoutException>()));

      expect(
        logger.events.map((event) => event.name),
        containsAll(<String>[
          'evt_command_response_unmatched',
          'evt_command_timeout',
        ]),
      );
      final transmit = logger.events.firstWhere(
        (event) => event.name == 'evt_command_transmit_started',
      );
      expect(
        transmit.fields['frame_summary'],
        'evt_authentication cmd=0x09 action=0x02 security_code=redacted',
      );
      expect(
        transmit.fields['wire_summary'],
        'evt_authentication cmd=0x09 action=0x02 '
        'wire=ED 0A 00 09 02 ** ** ** ** ** ** DE 3C',
      );
      expect(transmit.fields.containsKey('raw_packet_hex'), isFalse);
      expect(
        logger.events.map((event) => event.fields.values.join(' ')).join(' '),
        isNot(contains('DE AD BE EF FA CE')),
      );

      await client.close();
    },
  );
}

class _CapturedLogEvent {
  const _CapturedLogEvent({required this.name, required this.fields});

  final String name;
  final Map<String, Object?> fields;
}

class _CapturingLogger implements SafeAppLogger {
  final events = <_CapturedLogEvent>[];
  final _updates = StreamController<_CapturedLogEvent>.broadcast();

  Future<_CapturedLogEvent> nextEvent(String name) => _updates.stream
      .firstWhere((event) => event.name == name)
      .timeout(const Duration(seconds: 3));

  @override
  void error(
    String event, {
    DiagnosticTrace? trace,
    String? operation,
    String? stage,
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  }) => _record(event, fields);

  @override
  void info(
    String event, {
    DiagnosticTrace? trace,
    String? operation,
    String? stage,
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  }) => _record(event, fields);

  @override
  void warning(
    String event, {
    DiagnosticTrace? trace,
    String? operation,
    String? stage,
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  }) => _record(event, fields);

  void _record(String event, Map<String, Object?> fields) {
    final record = _CapturedLogEvent(
      name: event,
      fields: Map<String, Object?>.from(fields),
    );
    events.add(record);
    _updates.add(record);
  }
}

class _DeferredWriteBleTransport extends FakeBleTransport {
  final Completer<void> _writeStarted = Completer<void>();
  final Completer<void> _writeCompleted = Completer<void>();

  Future<void> get writeStarted => _writeStarted.future;

  void completeWrite() {
    if (!_writeCompleted.isCompleted) {
      _writeCompleted.complete();
    }
  }

  @override
  Future<void> write(BleCharacteristic characteristic, Uint8List bytes) async {
    writes.add(Uint8List.fromList(bytes));
    if (!_writeStarted.isCompleted) {
      _writeStarted.complete();
    }
    await _writeCompleted.future;
  }
}
