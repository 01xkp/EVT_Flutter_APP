import 'dart:async';

import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/ble/ble_transport.dart';
import 'package:aipin/core/ble/reactive_ble_transport.dart';
import 'package:aipin/core/diagnostics/diagnostic_trace.dart';
import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/core/protocol/evt_command_client.dart';
import 'package:aipin/core/protocol/evt_protocol_codec.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart' as reactive;
import 'package:flutter_test/flutter_test.dart';
import 'package:reactive_ble_mobile/reactive_ble_mobile.dart';
// The wire-contract test intentionally uses the vendored native message schema.
// ignore: implementation_imports
import 'package:reactive_ble_mobile/src/generated/bledata.pb.dart' as pb;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _NativeReceiveHarness native;
  late ReactiveBleTransport transport;
  late reactive.FlutterReactiveBle ble;
  late _ReceiveLogger logger;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    native = _NativeReceiveHarness()..install();
    reactive.ReactiveBlePlatform.instance =
        const ReactiveBleMobilePlatformFactory().create();
    ble = reactive.FlutterReactiveBle();
    await ble.initialize();
    logger = _ReceiveLogger();
    transport = ReactiveBleTransport(
      ble: ble,
      logger: logger,
      enableNativeBleLogBridge: false,
    );
  });

  tearDown(() async {
    await ble.deinitialize();
    native.uninstall();
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'idle notification cancellation does not need another device packet',
    () async {
      final subscription = transport.subscribe(_fa19).listen((_) {});
      await transport.awaitSubscriptionReady(_fa19);

      await subscription.cancel().timeout(const Duration(seconds: 1));
      await native.stopped.future.timeout(const Duration(seconds: 1));
      expect(logger.events, contains('notification_stream_closed'));
    },
  );

  test(
    'plugin notification cancellation does not need another device packet',
    () async {
      final subscription = ble
          .subscribeToCharacteristic(
            reactive.QualifiedCharacteristic(
              deviceId: _fa19.deviceId,
              serviceId: reactive.Uuid.parse(_fa19.serviceUuid),
              characteristicId: reactive.Uuid.parse(_fa19.characteristicUuid),
            ),
          )
          .listen((_) {});
      await transport.awaitSubscriptionReady(_fa19);

      await subscription.cancel().timeout(const Duration(seconds: 1));
      await native.stopped.future.timeout(const Duration(seconds: 1));
    },
  );

  test(
    'FA19 response crosses the real Dart plugin before write completion',
    () async {
      final codec = EvtProtocolCodec();
      final client = EvtCommandClient(
        transport: transport,
        codec: codec,
        responses: transport.subscribe(_fa19),
        logger: logger,
      );
      addTearDown(client.close);
      await transport.awaitSubscriptionReady(_fa19);
      expect(native.valueChannelListening, isTrue);
      final releaseWrite = Completer<void>();
      addTearDown(() {
        if (!releaseWrite.isCompleted) releaseWrite.complete();
      });
      native.onWrite = (request) async {
        await native.emit(
          request.characteristic,
          codec.encodeRequest(0x89, [1]),
        );
        await releaseWrite.future;
      };

      var completed = false;
      final response = client.execute(_authenticationRequest).then((value) {
        completed = true;
        return value;
      });
      await logger.responseMatched.future.timeout(const Duration(seconds: 2));
      expect(completed, isFalse);
      expect(logger.events, contains('notification_received'));
      releaseWrite.complete();

      expect((await response).frame.content, [1]);
      expect(native.writes, 1);
    },
  );

  test(
    '1000 native packets retain their bytes and order through the Dart plugin',
    () async {
      final received = <List<int>>[];
      final subscription = transport.subscribe(_fa19).listen(received.add);
      addTearDown(subscription.cancel);
      await transport.awaitSubscriptionReady(_fa19);
      final address = await native.subscription.future;
      final packets = List.generate(
        1000,
        (index) => [index & 255, index >> 8, 0, 255],
      );

      for (final packet in packets) {
        await native.emit(address, packet);
      }
      await Future<void>.delayed(Duration.zero);

      expect(received, packets);
      expect(
        logger.events.where((event) => event == 'notification_received'),
        hasLength(1000),
      );
    },
  );

  test(
    'packets from another characteristic instance cannot satisfy authentication',
    () async {
      final codec = EvtProtocolCodec();
      final client = EvtCommandClient(
        transport: transport,
        codec: codec,
        responses: transport.subscribe(_fa19),
        logger: logger,
      );
      addTearDown(client.close);
      await transport.awaitSubscriptionReady(_fa19);
      native.onWrite = (request) async {
        final wrongInstance = pb.CharacteristicAddress.fromBuffer(
          request.characteristic.writeToBuffer(),
        )..characteristicInstanceId = '999';
        await native.emit(wrongInstance, codec.encodeRequest(0x89, [0]));
        await native.emit(
          request.characteristic,
          codec.encodeRequest(0x89, [1]),
        );
      };

      final response = await client.execute(_authenticationRequest);

      expect(response.frame.content, [1]);
      expect(
        logger.events.where((event) => event == 'notification_received'),
        hasLength(1),
      );
    },
  );

  test(
    'native receive failure reaches the pending command without waiting for timeout',
    () async {
      final client = EvtCommandClient(
        transport: transport,
        codec: EvtProtocolCodec(),
        responses: transport.subscribe(_fa19),
        logger: logger,
      );
      addTearDown(client.close);
      await transport.awaitSubscriptionReady(_fa19);
      native.onWrite = (request) => native.emitFailure(request.characteristic);

      await expectLater(
        client
            .execute(_authenticationRequest)
            .timeout(const Duration(seconds: 1)),
        throwsA(isA<BleTransportException>()),
      );
      expect(logger.events, contains('notification_subscription_failed'));
      expect(logger.events, isNot(contains('evt_command_timeout')));
      await native.stopped.future.timeout(const Duration(seconds: 1));
    },
  );

  test(
    'a silent peripheral times out and the idle receiver can still close',
    () async {
      final client = EvtCommandClient(
        transport: transport,
        codec: EvtProtocolCodec(),
        responses: transport.subscribe(_fa19),
        logger: logger,
      );
      addTearDown(client.close);
      await transport.awaitSubscriptionReady(_fa19);

      await expectLater(
        client.execute(
          const EvtCommandRequest(
            command: 0x09,
            content: [0, 49, 50, 51, 52, 53, 54],
            writeCharacteristic: _fa19,
            expectedResponseCommand: 0x89,
            maxRetries: 0,
            timeout: Duration(milliseconds: 50),
          ),
        ),
        throwsA(isA<EvtCommandTimeoutException>()),
      );
      expect(logger.events, contains('evt_command_timeout'));
      expect(logger.events, isNot(contains('evt_command_response_matched')));
      await client.close().timeout(const Duration(seconds: 1));
      await native.stopped.future.timeout(const Duration(seconds: 1));
    },
  );
}

const _fa19 = BleCharacteristic(
  deviceId: '71:BF:E2:3B:84:23',
  serviceUuid: '0000FA10-1212-EFDE-1523-785FEABCD123',
  characteristicUuid: '0000FA19-1212-EFDE-1523-785FEABCD123',
);
const _authenticationRequest = EvtCommandRequest(
  command: 0x09,
  content: [0, 49, 50, 51, 52, 53, 54],
  writeCharacteristic: _fa19,
  expectedResponseCommand: 0x89,
  maxRetries: 0,
  timeout: Duration(seconds: 5),
);

class _NativeReceiveHarness {
  static const methodChannel = MethodChannel('flutter_reactive_ble_method');
  static const valueChannel = 'flutter_reactive_ble_char_update';
  static const eventChannels = [
    valueChannel,
    'flutter_reactive_ble_connected_device',
    'flutter_reactive_ble_status',
  ];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final subscription = Completer<pb.CharacteristicAddress>();
  final stopped = Completer<void>();
  Future<void> Function(pb.WriteCharacteristicRequest request)? onWrite;
  bool valueChannelListening = false;
  int writes = 0;

  void install() {
    for (final channel in eventChannels) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), (call) async {
        if (channel == valueChannel) {
          valueChannelListening = call.method == 'listen';
        }
        return null;
      });
    }
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      switch (call.method) {
        case 'initialize':
        case 'deinitialize':
          return null;
        case 'stopNotifications':
          if (!stopped.isCompleted) stopped.complete();
          return null;
        case 'getDiscoveredServices':
          final serviceId = pb.Uuid(
            data: reactive.Uuid.parse(_fa19.serviceUuid).data,
          );
          final characteristicId = pb.Uuid(
            data: reactive.Uuid.parse(_fa19.characteristicUuid).data,
          );
          return pb.DiscoverServicesInfo(
            deviceId: _fa19.deviceId,
            services: [
              pb.DiscoveredService(
                serviceUuid: serviceId,
                serviceInstanceId: '1',
                characteristics: [
                  pb.DiscoveredCharacteristic(
                    characteristicId: characteristicId,
                    serviceId: serviceId,
                    characteristicInstanceId: '7',
                    isWritableWithResponse: true,
                    isIndicatable: true,
                  ),
                ],
              ),
            ],
          ).writeToBuffer();
        case 'readNotifications':
          subscription.complete(
            pb.NotifyCharacteristicRequest.fromBuffer(
              call.arguments as List<int>,
            ).characteristic,
          );
          return null;
        case 'awaitNotificationSetup':
          await subscription.future;
          return null;
        case 'writeCharacteristicWithResponse':
          final request = pb.WriteCharacteristicRequest.fromBuffer(
            call.arguments as List<int>,
          );
          writes++;
          await onWrite?.call(request);
          return pb.WriteCharacteristicInfo(
            characteristic: request.characteristic,
          ).writeToBuffer();
        default:
          throw StateError('Unexpected native call: ${call.method}');
      }
    });
  }

  Future<void> emit(pb.CharacteristicAddress address, List<int> bytes) =>
      _deliver(
        pb.CharacteristicValueInfo(characteristic: address, value: bytes),
      );

  Future<void> emitFailure(pb.CharacteristicAddress address) => _deliver(
    pb.CharacteristicValueInfo(
      characteristic: address,
      failure: pb.GenericFailure(
        code: 0,
        message: 'Native indication stream failed',
      ),
    ),
  );

  Future<void> _deliver(pb.CharacteristicValueInfo message) {
    final delivered = Completer<void>();
    ServicesBinding.instance.channelBuffers.push(
      valueChannel,
      const StandardMethodCodec().encodeSuccessEnvelope(
        message.writeToBuffer(),
      ),
      (_) => delivered.complete(),
    );
    return delivered.future;
  }

  void uninstall() {
    messenger.setMockMethodCallHandler(methodChannel, null);
    for (final channel in eventChannels) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), null);
    }
  }
}

class _ReceiveLogger implements SafeAppLogger {
  final events = <String>[];
  final responseMatched = Completer<void>();

  @override
  void info(
    String event, {
    DiagnosticTrace? trace,
    String? operation,
    String? stage,
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  }) {
    events.add(event);
    if (event == 'evt_command_response_matched' &&
        !responseMatched.isCompleted) {
      responseMatched.complete();
    }
  }

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
}
