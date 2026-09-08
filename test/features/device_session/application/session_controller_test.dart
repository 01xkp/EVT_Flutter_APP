import 'dart:async';

import 'package:aipin/core/ble/device_profile.dart';
import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/ble/ble_transport.dart';
import 'package:aipin/core/diagnostics/diagnostic_trace.dart';
import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/core/protocol/evt_command_client.dart';
import 'package:aipin/core/protocol/evt_frame.dart';
import 'package:aipin/core/protocol/evt_protocol_codec.dart';
import 'package:aipin/features/device_session/application/session_controller.dart';
import 'package:aipin/features/device_session/domain/device_permission.dart';
import 'package:aipin/features/device_session/domain/device_snapshot.dart';
import 'package:aipin/features/device_session/domain/evt_legacy_security_gateway.dart';
import 'package:aipin/features/device_session/domain/session_phase.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_ble_transport.dart';

void main() {
  test('records safe, Chinese-marked EVT session setup milestones', () async {
    final profile = _profileWithDeviceInfo();
    final transport = FakeBleTransport(
      profile: profile,
      deferRead: true,
      services: _servicesFor(profile),
    );
    final logger = _CapturingLogger();
    final candidate = FakeBleTransport.matchingCandidate.copyWith(
      connectionId: '11:22:33:44:55:66',
      name: 'Sensitive EVT Device Name',
    );
    final controller = SessionController(
      transport,
      profile,
      EvtProtocolCodec(),
      logger: logger,
    );
    addTearDown(controller.dispose);

    await controller.connect(candidate);
    await controller.disconnect();

    expect(
      logger.events,
      containsAll(<String>[
        'session_open_requested',
        'gatt_connection_stream_requested',
        'gatt_service_discovery_requested',
        'evt_gatt_contract_checked',
        'evt_subscription_setup_requested',
        'session_authentication_ready',
        'disconnect_started',
        'transport_cleanup_started',
        'disconnect_completed',
      ]),
    );
    final open = logger.calls.firstWhere(
      (call) => call.event == 'session_open_requested',
    );
    expect(open.fields['reason'], startsWith('【会话连接】'));
    expect(open.fields['device_suffix'], '...5566');
    expect(logger.flattenedFields, isNot(contains('11:22:33:44:55:66')));
    expect(
      logger.flattenedFields,
      isNot(contains('Sensitive EVT Device Name')),
    );
  });

  test(
    'subscribes available EVT endpoints before V1 authentication and performs no protected reads',
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

      expect(
        transport.subscribedCharacteristics.map(
          (characteristic) => characteristic.characteristicUuid,
        ),
        <String>[
          _fa19,
          _fa11,
          _fa12,
          _fa15,
          _fa16,
          _fa17,
          _fb11,
          _ff12,
          _ff13,
          _ff11,
        ],
      );
      expect(controller.state.phase, SessionPhase.authenticationReady);
      expect(controller.state.isAuthenticationReady, isTrue);
      expect(controller.state.isObservable, isFalse);
      expect(transport.readCharacteristics, isEmpty);
    },
  );

  test(
    'allows authentication setup when compatibility-only FF11 is absent',
    () async {
      final profile = _profileWithDeviceInfo();
      final transport = FakeBleTransport(
        profile: profile,
        deferRead: true,
        services: _servicesFor(
          profile,
          omittedEndpoints: const {BleLogicalEndpoint.ff10Ff11},
        ),
      );
      final controller = SessionController(
        transport,
        profile,
        EvtProtocolCodec(),
      );
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);

      expect(controller.state.phase, SessionPhase.authenticationReady);
      expect(
        transport.subscribedCharacteristics.map(
          (characteristic) => characteristic.characteristicUuid,
        ),
        isNot(contains(_ff11)),
      );
      expect(transport.disconnectedDeviceIds, isEmpty);
    },
  );

  test(
    'waits for native CCC confirmation before making V1 authentication available',
    () async {
      final profile = _profileWithDeviceInfo();
      final transport = FakeBleTransport(
        profile: profile,
        deferRead: true,
        deferNotificationSetup: true,
        services: _servicesFor(profile),
      );
      final controller = SessionController(
        transport,
        profile,
        EvtProtocolCodec(),
      );
      addTearDown(controller.dispose);

      final connection = controller.connect(FakeBleTransport.matchingCandidate);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.phase, SessionPhase.subscribing);
      expect(transport.notificationSetupRequests, hasLength(1));
      expect(transport.readCharacteristics, isEmpty);
      expect(transport.writes, isEmpty);

      transport.completeNotificationSetup();
      await connection;

      expect(controller.state.phase, SessionPhase.authenticationReady);
      expect(transport.notificationSetupRequests, hasLength(10));
    },
  );

  test(
    'does not continue setup when a disconnected attempt finishes service discovery late',
    () async {
      final profile = _profileWithDeviceInfo();
      final transport = FakeBleTransport(
        profile: profile,
        deferRead: true,
        deferServiceDiscovery: true,
        services: _servicesFor(profile),
      );
      final controller = SessionController(
        transport,
        profile,
        EvtProtocolCodec(),
      );
      addTearDown(controller.dispose);

      final connecting = controller.connect(FakeBleTransport.matchingCandidate);
      await _waitForDiscoveryRequest(transport);

      transport.emitConnection(BleConnectionState.disconnected);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.phase, SessionPhase.interrupted);

      transport.completeServiceDiscovery();
      await connecting;
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.phase, SessionPhase.interrupted);
      expect(controller.state.endpointCapabilities, isEmpty);
      expect(transport.subscribedCharacteristics, isEmpty);
    },
  );

  test(
    'does not block V1 authentication when optional FF11 CCC confirmation fails',
    () async {
      final profile = _profileWithDeviceInfo();
      final transport = FakeBleTransport(
        profile: profile,
        deferRead: true,
        services: _servicesFor(profile),
        notificationSetupFailureByCharacteristicUuid: {
          _ff11: StateError('FF11 CCC unavailable'),
        },
      );
      final controller = SessionController(
        transport,
        profile,
        EvtProtocolCodec(),
      );
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);

      expect(controller.state.phase, SessionPhase.authenticationReady);
      expect(transport.disconnectedDeviceIds, isEmpty);
      expect(
        transport.notificationSetupRequests.map(
          (characteristic) => characteristic.characteristicUuid,
        ),
        contains(_ff11),
      );
    },
  );

  test(
    'uses the V1 0x09 security payload and one-byte result semantics',
    () async {
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
      final authenticated = controller.executeEvtLegacySecurity(
        EvtLegacySecurityRequest(
          action: EvtLegacySecurityAction.authenticate,
          securityCode: '123456',
        ),
      );
      final authenticateRequest = await _waitForCommand(
        transport,
        codec,
        command: 0x09,
        minimumWriteCount: 1,
      );

      expect(authenticateRequest.content, <int>[
        0,
        0x31,
        0x32,
        0x33,
        0x34,
        0x35,
        0x36,
      ]);
      transport.emitSubscriptionBytes(codec.encodeRequest(0x89, const [1]));
      expect(await authenticated, isTrue);

      final rejected = controller.executeEvtLegacySecurity(
        EvtLegacySecurityRequest(
          action: EvtLegacySecurityAction.bind,
          securityCode: '654321',
        ),
      );
      final bindRequest = await _waitForCommand(
        transport,
        codec,
        command: 0x09,
        minimumWriteCount: 2,
      );
      expect(bindRequest.content, <int>[1, 0x36, 0x35, 0x34, 0x33, 0x32, 0x31]);
      transport.emitSubscriptionBytes(codec.encodeRequest(0x89, const [0]));
      expect(await rejected, isFalse);

      expect(controller.state.phase, SessionPhase.authenticationReady);
      expect(transport.disconnectedDeviceIds, isEmpty);

      expect(
        () => EvtLegacySecurityRequest(
          action: EvtLegacySecurityAction.reset,
          securityCode: '12345',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(transport.writes, hasLength(2));
    },
  );

  test(
    'resets the GATT session after an unconfirmed V1 security result',
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
        legacySecurityResponseTimeout: const Duration(milliseconds: 10),
      );
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);
      await expectLater(
        controller.executeEvtLegacySecurity(
          EvtLegacySecurityRequest(
            action: EvtLegacySecurityAction.authenticate,
            securityCode: '123456',
          ),
        ),
        throwsA(isA<EvtCommandTimeoutException>()),
      );

      expect(controller.state.phase, SessionPhase.interrupted);
      expect(
        transport.disconnectedDeviceIds,
        contains(FakeBleTransport.matchingCandidate.connectionId),
      );

      transport.emitSubscriptionBytes(
        EvtProtocolCodec().encodeRequest(0x89, const [1]),
      );
      await Future<void>.delayed(Duration.zero);
      await expectLater(
        controller.executeEvtLegacySecurity(
          EvtLegacySecurityRequest(
            action: EvtLegacySecurityAction.bind,
            securityCode: '654321',
          ),
        ),
        throwsA(isA<StateError>()),
      );
      expect(transport.writes, hasLength(1));
    },
  );

  test(
    'refreshes an Android GATT cache once before disconnecting after a V1 response timeout',
    () async {
      final profile = _profileWithDeviceInfo();
      final transport = FakeBleTransport(
        profile: profile,
        deferRead: true,
        services: _servicesFor(profile),
        gattCacheClearResult: BleGattCacheClearResult.cleared,
      );
      final controller = SessionController(
        transport,
        profile,
        EvtProtocolCodec(),
        legacySecurityResponseTimeout: const Duration(milliseconds: 10),
      );
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);
      await expectLater(
        controller.executeEvtLegacySecurity(
          EvtLegacySecurityRequest(
            action: EvtLegacySecurityAction.authenticate,
            securityCode: '123456',
          ),
        ),
        throwsA(isA<EvtCommandTimeoutException>()),
      );

      expect(transport.gattCacheClearDeviceIds, <String>[
        FakeBleTransport.matchingCandidate.connectionId,
      ]);
      expect(transport.connectionOperations, <String>[
        'clear_gatt_cache',
        'disconnect',
      ]);
      expect(transport.writes, hasLength(1));
      expect(controller.state.phase, SessionPhase.interrupted);
    },
  );

  test(
    'keeps the original V1 timeout and disconnects when GATT cache recovery is unsupported or fails',
    () async {
      for (final scenario
          in <({String name, BleGattCacheClearResult result, Object? error})>[
            (
              name: 'unsupported',
              result: BleGattCacheClearResult.unsupported,
              error: null,
            ),
            (
              name: 'failed result',
              result: BleGattCacheClearResult.failed,
              error: null,
            ),
            (
              name: 'transport error',
              result: BleGattCacheClearResult.failed,
              error: StateError('GATT cache refresh unavailable'),
            ),
          ]) {
        final profile = _profileWithDeviceInfo();
        final transport = FakeBleTransport(
          profile: profile,
          deferRead: true,
          services: _servicesFor(profile),
          gattCacheClearResult: scenario.result,
          gattCacheClearError: scenario.error,
        );
        final logger = _CapturingLogger();
        final controller = SessionController(
          transport,
          profile,
          EvtProtocolCodec(),
          logger: logger,
          legacySecurityResponseTimeout: const Duration(milliseconds: 10),
        );
        addTearDown(controller.dispose);
        addTearDown(transport.dispose);

        await controller.connect(FakeBleTransport.matchingCandidate);
        await expectLater(
          controller.executeEvtLegacySecurity(
            EvtLegacySecurityRequest(
              action: EvtLegacySecurityAction.authenticate,
              securityCode: '123456',
            ),
          ),
          throwsA(isA<EvtCommandTimeoutException>()),
          reason: scenario.name,
        );

        expect(transport.gattCacheClearDeviceIds, <String>[
          FakeBleTransport.matchingCandidate.connectionId,
        ], reason: scenario.name);
        expect(transport.connectionOperations, <String>[
          'clear_gatt_cache',
          'disconnect',
        ], reason: scenario.name);
        expect(transport.writes, hasLength(1), reason: scenario.name);
        expect(
          controller.state.phase,
          SessionPhase.interrupted,
          reason: scenario.name,
        );

        if (scenario.result == BleGattCacheClearResult.unsupported &&
            scenario.error == null) {
          final recovery = logger.calls.firstWhere(
            (call) => call.event == 'legacy_security_gatt_recovery_completed',
          );
          expect(recovery.result, isNot('success'));
          expect(
            recovery.fields['gatt_cache_refresh_result'],
            BleGattCacheClearResult.unsupported.name,
          );
        }
      }
    },
  );

  test(
    'does not request a GATT cache refresh for a malformed V1 security response',
    () async {
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
      final authentication = controller.executeEvtLegacySecurity(
        EvtLegacySecurityRequest(
          action: EvtLegacySecurityAction.authenticate,
          securityCode: '123456',
        ),
      );
      await _waitForCommand(transport, codec, command: 0x09);
      transport.emitSubscriptionBytes(codec.encodeRequest(0x89, const [2]));

      await expectLater(authentication, throwsA(isA<FormatException>()));
      expect(transport.gattCacheClearDeviceIds, isEmpty);
      expect(transport.connectionOperations, <String>['disconnect']);
      expect(transport.writes, hasLength(1));
      expect(controller.state.phase, SessionPhase.interrupted);
    },
  );

  test(
    'ignores a matching device-info response delivered through the wrong characteristic',
    () async {
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

      var completed = false;
      final deviceInfo = controller.readDeviceInfo();
      deviceInfo.then<void>((_) {
        completed = true;
      });
      await _waitForCommand(transport, codec, command: 0x01);

      transport.emitSubscriptionBytesForCharacteristic(
        _fa19,
        _deviceInfoFrame(protocolVersion: 3),
      );
      await Future<void>.delayed(Duration.zero);

      expect(completed, isFalse);
      expect(controller.state.events, isEmpty);
      expect(controller.state.latestSnapshot, isNull);

      transport.emitSubscriptionBytesForCharacteristic(
        _fa11,
        _deviceInfoFrame(protocolVersion: 3),
      );
      expect((await deviceInfo).capabilities.protocolVersion, 3);
    },
  );

  test(
    'interrupts setup when the critical FA19 indication stream closes before V1 authentication',
    () async {
      final profile = _profileWithDeviceInfo();
      final transport = FakeBleTransport(
        profile: profile,
        deferRead: true,
        closeSubscriptionImmediatelyForCharacteristic: _fa19,
        services: _servicesFor(profile),
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
    'interrupts setup when the mandatory FF13 notification stream closes before V1 authentication',
    () async {
      final profile = _profileWithDeviceInfo();
      final transport = FakeBleTransport(
        profile: profile,
        deferRead: true,
        closeSubscriptionImmediatelyForCharacteristic: _ff13,
        services: _servicesFor(profile),
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
        transport.subscribedCharacteristics.map(
          (characteristic) => characteristic.characteristicUuid,
        ),
        contains(_ff13),
      );
      expect(
        transport.disconnectedDeviceIds,
        contains(FakeBleTransport.matchingCandidate.connectionId),
      );
    },
  );

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
    'reads configuration time through FA12 GATT Read without an empty 0x02 write',
    () async {
      final profile = _profileWithAuthoritativeStatusEndpoints();
      final codec = EvtProtocolCodec();
      final transport = FakeBleTransport(
        profile: profile,
        services: _servicesFor(profile),
        readValuesByCharacteristicUuid: {
          _fa12: codec.encodeRequest(0x82, const [0x80, 0x96, 0x98, 0x66]),
        },
      );
      final controller = SessionController(transport, profile, codec);
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);
      await _completeAuthenticatedSession(controller, transport);
      final writesBeforeRefresh = transport.writes.length;
      final readsBeforeRefresh = transport.readCharacteristics.length;

      final refreshed = controller.refreshDeviceDetails(const {
        DevicePermission.configuration,
      });
      await _respondToCommand(
        transport,
        codec,
        command: 0x06,
        subCommand: 0x03,
        response: codec.encodeRequest(0x86, const [0x03, 0, 1, 2]),
      );
      await refreshed;

      expect(
        transport.readCharacteristics
            .skip(readsBeforeRefresh)
            .map((characteristic) => characteristic.characteristicUuid),
        contains(_fa12),
      );
      final refreshFrames = transport.writes
          .skip(writesBeforeRefresh)
          .map((bytes) => codec.decode(bytes).value!)
          .toList();
      expect(refreshFrames.map((frame) => frame.command), <int>[0x06]);
      expect(
        refreshFrames.where(
          (frame) => frame.command == 0x02 && frame.content.isEmpty,
        ),
        isEmpty,
      );
    },
  );

  test('rejects GATT discovery when FA16 lacks Indicate', () async {
    final profile = _profileWithAuthoritativeStatusEndpoints();
    final transport = FakeBleTransport(
      profile: profile,
      services: _servicesFor(
        profile,
        operationOverrides: const {
          BleLogicalEndpoint.fa10Fa16: {BleOperation.write},
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
    expect(controller.state.failure?.detail, contains('fa10Fa16.indicate'));
    expect(transport.subscribedCharacteristics, isEmpty);
    expect(transport.writes, isEmpty);
    expect(
      transport.disconnectedDeviceIds,
      contains(FakeBleTransport.matchingCandidate.connectionId),
    );
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
      await _respondToCommand(
        transport,
        EvtProtocolCodec(),
        command: 0x01,
        response: _deviceInfoFrame(protocolVersion: 3),
      );
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
          _fa12: codec.encodeRequest(0x82, const [0x80, 0x96, 0x98, 0x66]),
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
      final configuration = await _waitForCommand(
        transport,
        codec,
        command: 0x02,
        minimumWriteCount: 2,
      );
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
    'authentication baseline configuration clears the EVT-reserved byte',
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
        response: _deviceInfoFrame(protocolVersion: 3),
      );
      final configuration = await _waitForCommand(
        transport,
        codec,
        command: 0x02,
        minimumWriteCount: 2,
      );
      expect(configuration.command, 0x02);
      expect(configuration.content[11], 0);

      transport.emitSubscriptionBytes(codec.encodeRequest(0x82, const [1]));
      await synchronized;
    },
  );

  test('rejects GATT discovery when FA12 lacks required operations', () async {
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
    expect(controller.state.failure?.kind.name, 'access');
    expect(controller.state.failure?.detail, contains('fa10Fa12'));
    expect(transport.subscribedCharacteristics, isEmpty);
    expect(
      transport.writes.map(
        (bytes) => EvtProtocolCodec().decode(bytes).value!.command,
      ),
      isEmpty,
    );
    expect(
      transport.disconnectedDeviceIds,
      contains(FakeBleTransport.matchingCandidate.connectionId),
    );
  });

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
    'allows queued status reads when only the EVT status permission remains',
    () async {
      final profile = _profileWithAuthoritativeStatusEndpoints();
      final codec = EvtProtocolCodec();
      final transport = FakeBleTransport(
        profile: profile,
        deferRead: true,
        services: _servicesFor(profile),
      );
      final permissionGate = _SelectivePermissionGate(
        allowed: const {
          DevicePermission.status,
          DevicePermission.configuration,
          DevicePermission.files,
        },
      );
      final controller = SessionController(
        transport,
        profile,
        codec,
        permissionGate: permissionGate,
      );
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);
      await _completeAuthenticatedSession(controller, transport);
      permissionGate.allowed = const {DevicePermission.status};

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
    'applies EVT state indications without replacing the recording snapshot with battery state',
    () async {
      final profile = _profileWithStateEventEndpoint();
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
      transport.emitSubscriptionBytesForCharacteristic(
        _fa17,
        codec.encodeRequest(0x87, const [1, 8, 7, 0, 0, 1, 2, 0]),
      );
      transport.emitSubscriptionBytesForCharacteristic(
        _fb11,
        codec.encodeRequest(0x91, const [76, 1, 1]),
      );
      transport.emitSubscriptionBytesForCharacteristic(
        _fa15,
        codec.encodeRequest(0x85, const [0, 1, 0, 0, 64, 0, 0, 0]),
      );
      transport.emitSubscriptionBytesForCharacteristic(
        _ff11,
        codec.encodeRequest(0xA1, const [7, 0]),
      );
      transport.emitSubscriptionBytesForCharacteristic(
        _fa16,
        codec.encodeRequest(0x86, const [0x80, 0, 5, 1, 15, 0, 1, 2]),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.latestSnapshot?.state, DeviceState.recording);
      expect(controller.state.deviceBattery?.percent, 76);
      expect(controller.state.deviceBattery?.isCharging, isTrue);
      expect(controller.state.deviceStorage?.totalMegabytes, 256);
      expect(controller.state.deviceStorage?.freeMegabytes, 64);
      expect(controller.state.fileCount, 7);
      expect(controller.state.deviceStatus?.privacy, isTrue);
      expect(controller.state.deviceStatus?.privacyRemainingMinutes, 15);

      final validSnapshot = controller.state.latestSnapshot;
      transport.emitSubscriptionBytesForCharacteristic(
        _fa17,
        codec.encodeRequest(0x87, const [1]),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.latestSnapshot, same(validSnapshot));
    },
  );

  test(
    'verifies EVT configuration SET values by reading the device state',
    () async {
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
      await _completeAuthenticatedSession(controller, transport);

      final setConsent = controller.setRecordConsent(true);
      await _respondToCommand(
        transport,
        codec,
        command: 0x06,
        subCommand: 0x02,
        response: codec.encodeRequest(0x86, const [0x02, 0, 0]),
      );
      await _respondToCommand(
        transport,
        codec,
        command: 0x06,
        subCommand: 0x01,
        response: codec.encodeRequest(0x86, const [0x01, 0, 5, 0, 0, 0, 1, 0]),
      );
      await setConsent;
      expect(controller.state.deviceStatus?.recordConsent, isTrue);

      final setPrivacy = controller.setPrivacyDuration(3);
      await _respondToCommand(
        transport,
        codec,
        command: 0x06,
        subCommand: 0x04,
        response: codec.encodeRequest(0x86, const [0x04, 0, 0]),
      );
      await _respondToCommand(
        transport,
        codec,
        command: 0x06,
        subCommand: 0x03,
        response: codec.encodeRequest(0x86, const [0x03, 0, 1, 2]),
      );
      await expectLater(setPrivacy, throwsA(isA<StateError>()));
      expect(controller.state.privacyDurationCode, 2);
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

  test('rejects GATT discovery when FA11 cannot indicate', () async {
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
    expect(controller.state.failure?.detail, contains('fa10Fa11.indicate'));
    expect(transport.subscribedCharacteristics, isEmpty);
    expect(transport.writes, isEmpty);
    expect(
      transport.disconnectedDeviceIds,
      contains(FakeBleTransport.matchingCandidate.connectionId),
    );
  });

  test('rejects GATT discovery when FF13 lacks Notify', () async {
    final profile = _profileWithDeviceInfo();
    final transport = FakeBleTransport(
      profile: profile,
      services: _servicesFor(
        profile,
        operationOverrides: const {
          BleLogicalEndpoint.ff10Ff13: {BleOperation.write},
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
    expect(controller.state.failure?.detail, contains('ff10Ff13.notify'));
    expect(transport.subscribedCharacteristics, isEmpty);
    expect(transport.writes, isEmpty);
    expect(
      transport.disconnectedDeviceIds,
      contains(FakeBleTransport.matchingCandidate.connectionId),
    );
  });

  test(
    'invalid authenticated device information interrupts the session',
    () async {
      final transport = FakeBleTransport.withGattReadyProfile();
      final codec = EvtProtocolCodec();
      final controller = SessionController(transport, transport.profile, codec);
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);
      final synchronized = controller.synchronizeAfterAuthentication(const {});
      await _respondToCommand(
        transport,
        codec,
        command: 0x01,
        response: codec.encodeRequest(0x81, const [3]),
      );
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

      expect(controller.state.phase, SessionPhase.authenticationReady);
      await _respondToCommand(
        transport,
        EvtProtocolCodec(),
        command: 0x01,
        response: _deviceInfoFrame(protocolVersion: 2),
      );
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
    'subscribes all EVT CCCs before authentication without duplicates afterwards',
    () async {
      final profile = _profileWithDeviceInfo();
      final transport = FakeBleTransport(
        profile: profile,
        services: _servicesFor(profile),
      );
      final controller = SessionController(
        transport,
        profile,
        EvtProtocolCodec(),
      );
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);
      final beforeAuthentication = transport.subscribedCharacteristics
          .map((characteristic) => characteristic.characteristicUuid)
          .toList();
      expect(beforeAuthentication, <String>[
        _fa19,
        _fa11,
        _fa12,
        _fa15,
        _fa16,
        _fa17,
        _fb11,
        _ff12,
        _ff13,
        _ff11,
      ]);

      await _completeAuthenticatedSession(controller, transport);

      final subscribedUuids = transport.subscribedCharacteristics
          .map((characteristic) => characteristic.characteristicUuid)
          .toList();
      expect(subscribedUuids, beforeAuthentication);
    },
  );

  test(
    'resets the session after a file-list timeout to reject late page responses',
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
        fileListResponseTimeout: const Duration(milliseconds: 10),
      );
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);
      await _completeAuthenticatedSession(controller, transport);

      await expectLater(controller.listFiles(), throwsA(isA<StateError>()));

      expect(controller.state.phase, SessionPhase.interrupted);
      expect(controller.state.failure?.message, contains('设备文件列表响应超时'));
      expect(transport.writes, hasLength(3));
      expect(
        transport.disconnectedDeviceIds,
        contains(FakeBleTransport.matchingCandidate.connectionId),
      );
    },
  );

  test(
    'forwards 0x23 file data without retaining it as a session event',
    () async {
      final profile = _profileWithFileDownload();
      final codec = EvtProtocolCodec();
      final transport = FakeBleTransport(
        profile: profile,
        deferRead: true,
        negotiatedMtu: 136,
        services: _servicesFor(profile),
      );
      final controller = SessionController(transport, profile, codec);
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);
      await _completeAuthenticatedSession(controller, transport);

      final eventsBeforeTransfer = controller.state.events;
      var listenerNotifications = 0;
      void listener() {
        listenerNotifications += 1;
      }

      controller.addListener(listener);
      addTearDown(() => controller.removeListener(listener));
      final transfer = controller
          .downloadEvtFile(nameSlot: _fileNameSlot)
          .toList();
      await _waitForCommand(transport, codec, command: 0x23);
      final notificationsBeforeData = listenerNotifications;

      transport.emitSubscriptionBytesForCharacteristic(
        _ff13,
        codec.encodeRequest(0x23, const [0, 0, 0, 0, 2, 0, 0xAA, 0xBB]),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.events, same(eventsBeforeTransfer));
      expect(listenerNotifications, notificationsBeforeData);
      expect(controller.state.failure, isNull);

      transport.emitSubscriptionBytesForCharacteristic(
        _ff13,
        codec.encodeRequest(0x23, const [2, 0, 0, 0, 0, 0]),
      );
      final events = await transfer;

      expect(events, hasLength(2));
      expect(events.first.bytes, <int>[0xAA, 0xBB]);
      expect(events.last.isTerminal, isTrue);
      expect(controller.state.events, same(eventsBeforeTransfer));
      expect(listenerNotifications, notificationsBeforeData);
    },
  );

  test(
    'allows an already-started EVT file transfer to finish after V1 authorization expires',
    () async {
      final profile = _profileWithFileDownload();
      final codec = EvtProtocolCodec();
      final transport = FakeBleTransport(
        profile: profile,
        deferRead: true,
        negotiatedMtu: 136,
        services: _servicesFor(profile),
      );
      final permissionGate = _MutablePermissionGate(allowed: true);
      final controller = SessionController(
        transport,
        profile,
        codec,
        permissionGate: permissionGate,
      );
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);
      await _completeAuthenticatedSession(controller, transport);

      final transfer = controller
          .downloadEvtFile(nameSlot: _fileNameSlot)
          .toList();
      await _waitForCommand(transport, codec, command: 0x23);
      permissionGate.allowed = false;

      transport.emitSubscriptionBytesForCharacteristic(
        _ff13,
        codec.encodeRequest(0x23, const [0, 0, 0, 0, 2, 0, 0xAA, 0xBB]),
      );
      transport.emitSubscriptionBytesForCharacteristic(
        _ff13,
        codec.encodeRequest(0x23, const [2, 0, 0, 0, 0, 0]),
      );

      final events = await transfer;
      expect(events.first.bytes, <int>[0xAA, 0xBB]);
      expect(events.last.isTerminal, isTrue);
      expect(controller.state.phase, SessionPhase.observable);
      expect(transport.disconnectedDeviceIds, isEmpty);
    },
  );

  test(
    'resets the session when an active EVT file transfer becomes idle',
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
        fileTransferIdleTimeout: const Duration(milliseconds: 10),
      );
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);
      await _completeAuthenticatedSession(controller, transport);

      await expectLater(
        controller.downloadEvtFile(nameSlot: _fileNameSlot).toList(),
        throwsA(isA<EvtCommandTimeoutException>()),
      );

      expect(controller.state.phase, SessionPhase.interrupted);
      expect(
        transport.disconnectedDeviceIds,
        contains(FakeBleTransport.matchingCandidate.connectionId),
      );
    },
  );

  test(
    'resets the session when a caller cancels an active EVT file transfer',
    () async {
      final profile = _profileWithFileDownload();
      final codec = EvtProtocolCodec();
      final transport = FakeBleTransport(
        profile: profile,
        deferRead: true,
        negotiatedMtu: 136,
        services: _servicesFor(profile),
      );
      final controller = SessionController(transport, profile, codec);
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);
      await _completeAuthenticatedSession(controller, transport);

      final subscription = controller
          .downloadEvtFile(nameSlot: _fileNameSlot)
          .listen((_) {});
      await _waitForCommand(transport, codec, command: 0x23);
      await subscription.cancel().timeout(const Duration(seconds: 1));

      expect(controller.state.phase, SessionPhase.interrupted);
      expect(
        transport.disconnectedDeviceIds,
        contains(FakeBleTransport.matchingCandidate.connectionId),
      );
    },
  );

  test(
    'does not write a device file command after EVT file permission expires',
    () async {
      final profile = _profileWithFileDownload();
      final transport = FakeBleTransport(
        profile: profile,
        deferRead: true,
        negotiatedMtu: 136,
        services: _servicesFor(profile),
      );
      final permissionGate = _MutablePermissionGate(allowed: true);
      final controller = SessionController(
        transport,
        profile,
        EvtProtocolCodec(),
        permissionGate: permissionGate,
      );
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);
      permissionGate.allowed = false;
      final writesBefore = transport.writes.length;

      await expectLater(
        controller.downloadEvtFile(nameSlot: _fileNameSlot).drain<void>(),
        throwsA(isA<StateError>()),
      );

      expect(transport.writes, hasLength(writesBefore));
    },
  );

  test(
    'does not write a queued EVT status command after V1 authorization expires',
    () async {
      final profile = _profileWithDeviceInfo();
      final transport = FakeBleTransport(
        profile: profile,
        deferRead: true,
        services: _servicesFor(profile),
      );
      final permissionGate = _MutablePermissionGate(allowed: true);
      final controller = SessionController(
        transport,
        profile,
        EvtProtocolCodec(),
        permissionGate: permissionGate,
      );
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);
      final first = controller.readDeviceInfo();
      final queued = controller.readDeviceInfo();
      await _waitForCommand(transport, EvtProtocolCodec(), command: 0x01);
      await Future<void>.delayed(Duration.zero);

      permissionGate.allowed = false;
      transport.emitSubscriptionBytesForCharacteristic(
        _fa11,
        _deviceInfoFrame(protocolVersion: 3),
      );

      await first;
      await expectLater(queued, throwsA(isA<StateError>()));
      expect(transport.writes, hasLength(1));
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

  test(
    'on iOS rejects a required EVT characteristic with both CCC modes before subscribing',
    () async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = previousPlatform;
      });
      final profile = _profileWithDeviceInfo();
      final transport = FakeBleTransport(
        profile: profile,
        deferRead: true,
        services: _servicesFor(
          profile,
          operationOverrides: const {
            BleLogicalEndpoint.fa10Fa19: {
              BleOperation.write,
              BleOperation.indicate,
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
      expect(controller.state.failure?.detail, contains('fa10Fa19.notify'));
      expect(transport.subscribedCharacteristics, isEmpty);
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

  test(
    'waits for an active native disconnect and does not close it twice during disposal',
    () async {
      final transport = FakeBleTransport.withGattReadyProfile(
        deferDisconnect: true,
      );
      final controller = SessionController(
        transport,
        transport.profile,
        EvtProtocolCodec(),
      );
      addTearDown(controller.dispose);

      await controller.connect(FakeBleTransport.matchingCandidate);
      final closing = controller.close();
      for (
        var attempt = 0;
        transport.disconnectedDeviceIds.isEmpty && attempt < 10;
        attempt += 1
      ) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(transport.disconnectedDeviceIds, <String>[
        FakeBleTransport.matchingCandidate.connectionId,
      ]);
      var closed = false;
      unawaited(closing.then<void>((_) => closed = true));
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);

      transport.completeDisconnect();
      await closing;
      controller.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(transport.disconnectedDeviceIds, <String>[
        FakeBleTransport.matchingCandidate.connectionId,
      ]);
    },
  );
}

DeviceProfile _profileWithDeviceInfo() {
  const fa10 = _fa10;
  return const DeviceProfile(
    namePrefix: 'AIPIN',
    manufacturerPrefixHex: 'A389',
    serviceUuid: '0000AF30-0000-1000-8000-00805F9B34FB',
    gattServiceUuid: fa10,
    endpoints: {
      BleLogicalEndpoint.fa10Fa11: BleEndpoint(
        serviceUuid: fa10,
        characteristicUuid: _fa11,
        operations: {BleOperation.write, BleOperation.indicate},
      ),
      BleLogicalEndpoint.fa10Fa12: BleEndpoint(
        serviceUuid: fa10,
        characteristicUuid: _fa12,
        operations: {
          BleOperation.read,
          BleOperation.write,
          BleOperation.indicate,
        },
      ),
      BleLogicalEndpoint.fa10Fa15: BleEndpoint(
        serviceUuid: fa10,
        characteristicUuid: _fa15,
        operations: {BleOperation.read, BleOperation.indicate},
      ),
      BleLogicalEndpoint.fa10Fa16: BleEndpoint(
        serviceUuid: fa10,
        characteristicUuid: _fa16,
        operations: {BleOperation.write, BleOperation.indicate},
      ),
      BleLogicalEndpoint.fa10Fa17: BleEndpoint(
        serviceUuid: fa10,
        characteristicUuid: _fa17,
        operations: {BleOperation.write, BleOperation.indicate},
      ),
      BleLogicalEndpoint.fa10Fa19: BleEndpoint(
        serviceUuid: fa10,
        characteristicUuid: _fa19,
        operations: {BleOperation.write, BleOperation.indicate},
      ),
      BleLogicalEndpoint.fb10Fb11: BleEndpoint(
        serviceUuid: _fb10Service,
        characteristicUuid: _fb11,
        operations: {BleOperation.read, BleOperation.indicate},
      ),
      BleLogicalEndpoint.ff10Ff11: BleEndpoint(
        serviceUuid: _ff10,
        characteristicUuid: _ff11,
        operations: {BleOperation.read, BleOperation.indicate},
      ),
      BleLogicalEndpoint.ff10Ff12: BleEndpoint(
        serviceUuid: _ff10,
        characteristicUuid: _ff12,
        operations: {BleOperation.write, BleOperation.indicate},
      ),
      BleLogicalEndpoint.ff10Ff13: BleEndpoint(
        serviceUuid: _ff10,
        characteristicUuid: _ff13,
        operations: {BleOperation.write, BleOperation.notify},
      ),
    },
  );
}

DeviceProfile _profileWithAuthoritativeStatusEndpoints() =>
    _profileWithDeviceInfo();

DeviceProfile _profileWithStateEventEndpoint() => _profileWithDeviceInfo();

DeviceProfile _profileWithFileDownload() => _profileWithDeviceInfo();

List<BleService> _servicesFor(
  DeviceProfile profile, {
  Map<BleLogicalEndpoint, Set<BleOperation>> operationOverrides = const {},
  Set<BleLogicalEndpoint> omittedEndpoints = const {},
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
        if (!omittedEndpoints.contains(BleLogicalEndpoint.fa10Fa11))
          BleDiscoveredCharacteristic(
            uuid: '0000FA11-1212-EFDE-1523-785FEABCD123',
            operations: operationsFor(BleLogicalEndpoint.fa10Fa11, const {
              BleOperation.write,
              BleOperation.indicate,
            }),
          ),
        if (!omittedEndpoints.contains(BleLogicalEndpoint.fa10Fa19))
          BleDiscoveredCharacteristic(
            uuid: '0000FA19-1212-EFDE-1523-785FEABCD123',
            operations: operationsFor(BleLogicalEndpoint.fa10Fa19, const {
              BleOperation.write,
              BleOperation.indicate,
            }),
          ),
        if (!omittedEndpoints.contains(BleLogicalEndpoint.fa10Fa16))
          BleDiscoveredCharacteristic(
            uuid: '0000FA16-1212-EFDE-1523-785FEABCD123',
            operations: operationsFor(BleLogicalEndpoint.fa10Fa16, const {
              BleOperation.write,
              BleOperation.indicate,
            }),
          ),
        if (!omittedEndpoints.contains(BleLogicalEndpoint.fa10Fa15))
          BleDiscoveredCharacteristic(
            uuid: _fa15,
            operations: operationsFor(BleLogicalEndpoint.fa10Fa15, const {
              BleOperation.read,
              BleOperation.indicate,
            }),
          ),
        if (!omittedEndpoints.contains(BleLogicalEndpoint.fa10Fa12))
          BleDiscoveredCharacteristic(
            uuid: _fa12,
            operations: operationsFor(BleLogicalEndpoint.fa10Fa12, const {
              BleOperation.read,
              BleOperation.write,
              BleOperation.indicate,
            }),
          ),
        if (!omittedEndpoints.contains(BleLogicalEndpoint.fa10Fa17))
          BleDiscoveredCharacteristic(
            uuid: _fa17,
            operations: operationsFor(BleLogicalEndpoint.fa10Fa17, const {
              BleOperation.write,
              BleOperation.indicate,
            }),
          ),
      ],
    ),
    BleService(
      uuid: _fb10Service,
      characteristics: [
        if (!omittedEndpoints.contains(BleLogicalEndpoint.fb10Fb11))
          BleDiscoveredCharacteristic(
            uuid: _fb11,
            operations: operationsFor(BleLogicalEndpoint.fb10Fb11, const {
              BleOperation.read,
              BleOperation.indicate,
            }),
          ),
      ],
    ),
    if ((profile.endpoints.containsKey(BleLogicalEndpoint.ff10Ff11) &&
            !omittedEndpoints.contains(BleLogicalEndpoint.ff10Ff11)) ||
        (profile.endpoints.containsKey(BleLogicalEndpoint.ff10Ff12) &&
            !omittedEndpoints.contains(BleLogicalEndpoint.ff10Ff12)) ||
        (profile.endpoints.containsKey(BleLogicalEndpoint.ff10Ff13) &&
            !omittedEndpoints.contains(BleLogicalEndpoint.ff10Ff13)))
      BleService(
        uuid: _ff10,
        characteristics: [
          if (profile.endpoints.containsKey(BleLogicalEndpoint.ff10Ff11) &&
              !omittedEndpoints.contains(BleLogicalEndpoint.ff10Ff11))
            BleDiscoveredCharacteristic(
              uuid: _ff11,
              operations: operationsFor(BleLogicalEndpoint.ff10Ff11, const {
                BleOperation.read,
                BleOperation.indicate,
              }),
            ),
          if (profile.endpoints.containsKey(BleLogicalEndpoint.ff10Ff12) &&
              !omittedEndpoints.contains(BleLogicalEndpoint.ff10Ff12))
            BleDiscoveredCharacteristic(
              uuid: _ff12,
              operations: operationsFor(BleLogicalEndpoint.ff10Ff12, const {
                BleOperation.write,
                BleOperation.indicate,
              }),
            ),
          if (profile.endpoints.containsKey(BleLogicalEndpoint.ff10Ff13) &&
              !omittedEndpoints.contains(BleLogicalEndpoint.ff10Ff13))
            BleDiscoveredCharacteristic(
              uuid: _ff13,
              operations: operationsFor(BleLogicalEndpoint.ff10Ff13, const {
                BleOperation.write,
                BleOperation.notify,
              }),
            ),
        ],
      ),
  ];
}

const _fa10 = '0000FA10-1212-EFDE-1523-785FEABCD123';
const _fa11 = '0000FA11-1212-EFDE-1523-785FEABCD123';
const _fa19 = '0000FA19-1212-EFDE-1523-785FEABCD123';
const _fa12 = '0000FA12-1212-EFDE-1523-785FEABCD123';
const _fa15 = '0000FA15-1212-EFDE-1523-785FEABCD123';
const _fa16 = '0000FA16-1212-EFDE-1523-785FEABCD123';
const _fa17 = '0000FA17-1212-EFDE-1523-785FEABCD123';
const _fb10Service = '0000FB10-1212-EFDE-1523-785FEABCD123';
const _fb11 = '0000FB11-1212-EFDE-1523-785FEABCD123';
const _ff10 = '0000FF10-1212-EFDE-1523-785FEABCD123';
const _ff11 = '0000FF11-1212-EFDE-1523-785FEABCD123';
const _ff12 = '0000FF12-1212-EFDE-1523-785FEABCD123';
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

class _MutablePermissionGate implements DevicePermissionGate {
  _MutablePermissionGate({required this.allowed});

  bool allowed;

  @override
  bool allows(DevicePermission permission) => allowed;
}

class _SelectivePermissionGate implements DevicePermissionGate {
  _SelectivePermissionGate({required this.allowed});

  Set<DevicePermission> allowed;

  @override
  bool allows(DevicePermission permission) => allowed.contains(permission);
}

List<int> _deviceInfoFrame({
  required int protocolVersion,
  int powerOff = 0,
  int chargingMode = 0,
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
  return EvtProtocolCodec().encodeRequest(0x81, content);
}

Future<void> _completeAuthenticatedSession(
  SessionController controller,
  FakeBleTransport transport,
) async {
  final synchronized = controller.synchronizeAfterAuthentication(const {});
  final codec = EvtProtocolCodec();
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
  await synchronized;
}

Future<EvtFrame> _waitForCommand(
  FakeBleTransport transport,
  EvtProtocolCodec codec, {
  required int command,
  int? subCommand,
  int minimumWriteCount = 1,
}) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (transport.writes.length >= minimumWriteCount) {
      final decoded = codec.decode(transport.writes.last);
      final request = decoded.value;
      if (request != null &&
          request.command == command &&
          (subCommand == null ||
              (request.content.isNotEmpty &&
                  request.content.first == subCommand))) {
        return request;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError(
    'Timed out waiting for command 0x${command.toRadixString(16)}.',
  );
}

Future<void> _waitForDiscoveryRequest(FakeBleTransport transport) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (transport.discoveryRequests.isNotEmpty) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('Timed out waiting for GATT service discovery.');
}

Future<void> _respondToCommand(
  FakeBleTransport transport,
  EvtProtocolCodec codec, {
  required int command,
  int? subCommand,
  required List<int> response,
}) async {
  await _waitForCommand(
    transport,
    codec,
    command: command,
    subCommand: subCommand,
  );
  transport.emitSubscriptionBytes(response);
}

class _CapturingLogger implements SafeAppLogger {
  final calls = <_LogCall>[];

  Iterable<String> get events => calls.map((call) => call.event);

  String get flattenedFields => calls
      .expand((call) => call.fields.entries)
      .map((entry) => '${entry.key}=${entry.value}')
      .join(' ');

  @override
  void error(
    String event, {
    DiagnosticTrace? trace,
    String? operation,
    String? stage,
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  }) => calls.add(_LogCall(event, fields, result: result));

  @override
  void info(
    String event, {
    DiagnosticTrace? trace,
    String? operation,
    String? stage,
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  }) => calls.add(_LogCall(event, fields, result: result));

  @override
  void warning(
    String event, {
    DiagnosticTrace? trace,
    String? operation,
    String? stage,
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  }) => calls.add(_LogCall(event, fields, result: result));
}

class _LogCall {
  const _LogCall(this.event, this.fields, {this.result});

  final String event;
  final Map<String, Object?> fields;
  final String? result;
}
