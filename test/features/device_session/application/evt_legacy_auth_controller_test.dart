import 'dart:async';

import 'package:aipin/core/diagnostics/diagnostic_trace.dart';
import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/features/device_session/application/evt_legacy_auth_controller.dart';
import 'package:aipin/features/device_session/domain/device_auth_state.dart';
import 'package:aipin/features/device_session/domain/device_permission.dart';
import 'package:aipin/features/device_session/domain/evt_legacy_security_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final lateSuccess in [false, true]) {
    test(
      'ignores old authentication result after reauthentication: $lateSuccess',
      () async {
        var timerCount = 0;
        final controller = EvtLegacyAuthController(
          authenticationExpiryTimer: (_, callback) {
            timerCount++;
            return Timer(const Duration(days: 1), callback);
          },
        );
        addTearDown(controller.dispose);
        final oldGateway = _DeferredSecurityGateway();
        final oldRequest = controller.authenticate(
          oldGateway,
          securityCode: '123456',
        );
        final oldResult = expectLater(oldRequest, throwsA(isA<StateError>()));
        controller.revokeForConnectionLoss();
        await controller.authenticate(
          _SecurityGateway(),
          securityCode: '654321',
        );
        var notifications = 0;
        controller.addListener(() => notifications++);

        if (lateSuccess) {
          oldGateway.result.complete(true);
        } else {
          oldGateway.result.completeError(StateError('old connection closed'));
        }
        await oldResult;

        expect(controller.state, DeviceAuthState.authenticated);
        expect(controller.error, isNull);
        expect(controller.allows(DevicePermission.files), isTrue);
        expect(notifications, 0);
        expect(timerCount, 0);
      },
    );

    test(
      'does not update disposed controller after result: $lateSuccess',
      () async {
        var timerCount = 0;
        final controller = EvtLegacyAuthController(
          authenticationExpiryTimer: (_, callback) {
            timerCount++;
            final timer = Timer(const Duration(days: 1), callback);
            return timer;
          },
        );
        addTearDown(controller.dispose);
        final gateway = _DeferredSecurityGateway();
        final request = controller.authenticate(
          gateway,
          securityCode: '123456',
        );
        final result = expectLater(request, throwsA(isA<StateError>()));
        controller.dispose();
        if (lateSuccess) {
          gateway.result.complete(true);
        } else {
          gateway.result.completeError(StateError('connection closed'));
        }
        await result;

        expect(timerCount, 0);
        expect(controller.isAuthenticated, isFalse);
      },
    );
  }

  test(
    'rejects new authentication after disposal without calling gateway',
    () async {
      final controller = EvtLegacyAuthController();
      final gateway = _SecurityGateway();
      controller.dispose();

      await expectLater(
        controller.authenticate(gateway, securityCode: '123456'),
        throwsA(isA<StateError>()),
      );
      expect(gateway.requests, isEmpty);
      expect(controller.revokeForConnectionLoss, returnsNormally);
    },
  );

  test('keeps authentication until the BLE connection is revoked', () async {
    var timerCount = 0;
    final controller = EvtLegacyAuthController(
      authenticationExpiryTimer: (_, callback) {
        timerCount++;
        return Timer(const Duration(days: 1), callback);
      },
    );
    addTearDown(controller.dispose);
    await controller.authenticate(_SecurityGateway(), securityCode: '123456');
    expect(controller.state, DeviceAuthState.authenticated);
    expect(timerCount, 0);

    // There is no local post-AUTH timer in V1.6. The connection lifecycle is
    // the sole revocation boundary.
    controller.revokeForConnectionLoss();
    expect(controller.state, DeviceAuthState.unbound);
  });

  test('does not expire authenticated permissions after 60 seconds', () async {
    var timerCount = 0;
    final controller = EvtLegacyAuthController(
      authenticationExpiryTimer: (_, callback) {
        timerCount++;
        return Timer(const Duration(days: 1), () {});
      },
    );
    addTearDown(controller.dispose);
    final gateway = _SecurityGateway();

    await controller.authenticate(gateway, securityCode: '123456');

    expect(controller.state, DeviceAuthState.authenticated);
    expect(controller.allows(DevicePermission.configuration), isTrue);
    expect(
      gateway.requests.single.action,
      EvtLegacySecurityAction.authenticate,
    );
    expect(timerCount, 0);
    expect(controller.state, DeviceAuthState.authenticated);
    expect(controller.allows(DevicePermission.configuration), isTrue);
  });

  test('unbind revokes permissions without relying on an auth timer', () async {
    var timerCount = 0;
    final controller = EvtLegacyAuthController(
      authenticationExpiryTimer: (_, callback) {
        timerCount++;
        return Timer(const Duration(days: 1), () {});
      },
    );
    addTearDown(controller.dispose);
    final gateway = _SecurityGateway();

    await controller.bind(gateway, securityCode: '123456');
    await controller.unbind(gateway, securityCode: '123456');

    expect(controller.state, DeviceAuthState.unbound);
    expect(controller.allows(DevicePermission.files), isFalse);
    expect(timerCount, 0);
    expect(
      gateway.requests.map((request) => request.action),
      <EvtLegacySecurityAction>[
        EvtLegacySecurityAction.bind,
        EvtLegacySecurityAction.authenticate,
        EvtLegacySecurityAction.unbind,
      ],
    );
  });

  test('normal unbind admission expires on connection loss', () async {
    final controller = EvtLegacyAuthController();
    addTearDown(controller.dispose);
    await controller.authenticate(_SecurityGateway(), securityCode: '123456');
    final gateway = _DeferredUnbindGateway();

    final unbind = controller.unbind(gateway, securityCode: '123456');
    final outcome = expectLater(unbind, throwsA(isA<StateError>()));
    await gateway.started.future;
    expect(controller.allowsPendingUnbind, isTrue);
    expect(controller.grantedPermissions, isEmpty);

    controller.revokeForConnectionLoss();
    expect(controller.allowsPendingUnbind, isFalse);
    gateway.result.complete(true);
    await outcome;
    expect(controller.hasUnbindRecoveryPending, isTrue);
  });

  test(
    'invalid local unbind code does not invent a pending device clear',
    () async {
      final controller = EvtLegacyAuthController();
      addTearDown(controller.dispose);
      final gateway = _SecurityGateway();
      await controller.authenticate(gateway, securityCode: '123456');

      await expectLater(
        controller.unbind(gateway, securityCode: 'invalid'),
        throwsA(isA<FormatException>()),
      );

      expect(gateway.requests, hasLength(1));
      expect(controller.isAuthenticated, isTrue);
      expect(controller.hasUnbindRecoveryPending, isFalse);
      expect(controller.allowsPendingUnbind, isFalse);
    },
  );

  test(
    'bind switches its transient action to AUTH after device confirmation',
    () async {
      final controller = EvtLegacyAuthController();
      addTearDown(controller.dispose);
      final gateway = _BindThenAuthenticateGateway();

      final binding = controller.bind(gateway, securityCode: '7A31C85E92B4');

      await gateway.bindStarted.future;
      expect(controller.state, DeviceAuthState.authenticating);
      expect(controller.activeAction, EvtLegacySecurityAction.bind);

      gateway.bindResult.complete(true);
      await gateway.authenticationStarted.future;
      expect(controller.state, DeviceAuthState.authenticating);
      expect(controller.activeAction, EvtLegacySecurityAction.authenticate);
      expect(
        gateway.requests.map((request) => request.action),
        <EvtLegacySecurityAction>[
          EvtLegacySecurityAction.bind,
          EvtLegacySecurityAction.authenticate,
        ],
      );

      gateway.authenticationResult.complete(true);
      await binding;

      expect(controller.state, DeviceAuthState.authenticated);
      expect(controller.activeAction, isNull);
    },
  );

  test(
    'records authentication steps without retaining the security code',
    () async {
      final logger = _CapturingLogger();
      var timerCount = 0;
      final controller = EvtLegacyAuthController(
        logger: logger,
        authenticationExpiryTimer: (_, callback) {
          timerCount++;
          return Timer(const Duration(days: 1), () {});
        },
      );
      addTearDown(controller.dispose);

      await controller.authenticate(_SecurityGateway(), securityCode: '123456');

      expect(
        logger.events,
        containsAll(<String>[
          'legacy_authentication_requested',
          'legacy_authentication_started',
          'legacy_authentication_protocol_dispatch',
          'legacy_authentication_connection_scope_started',
          'legacy_authentication_completed',
        ]),
      );
      expect(timerCount, 0);
      expect(
        logger.calls
            .firstWhere(
              (call) => call.event == 'legacy_authentication_requested',
            )
            .fields['length'],
        6,
      );
      expect(
        logger.calls.expand((call) => call.fields.values).join(' '),
        isNot(contains('123456')),
      );
    },
  );

  test(
    'keeps an explicit unbind recovery marker after a rejected request',
    () async {
      final controller = EvtLegacyAuthController();
      addTearDown(controller.dispose);
      final rejecting = _RejectingSecurityGateway();

      await expectLater(
        controller.unbind(rejecting, securityCode: '123456'),
        throwsA(isA<EvtLegacyAuthenticationException>()),
      );

      expect(controller.state, DeviceAuthState.unbindPending);
      expect(controller.hasUnbindRecoveryPending, isTrue);
      expect(controller.allows(DevicePermission.files), isFalse);
      expect(rejecting.requests.single.recovery, isFalse);

      await controller.unbindRecovery(
        _SecurityGateway(),
        securityCode: '123456',
      );
      expect(controller.state, DeviceAuthState.unbound);
      expect(controller.hasUnbindRecoveryPending, isFalse);
      expect(controller.grantedPermissions, isEmpty);
    },
  );

  test(
    'preserves unbind recovery intent when the connection is lost in flight',
    () async {
      final controller = EvtLegacyAuthController();
      addTearDown(controller.dispose);
      final gateway = _DeferredUnbindGateway();
      final request = controller.unbind(gateway, securityCode: '123456');

      // Wait until _execute has marked the Action=2 as dispatched before
      // simulating the BLE disconnect.
      await gateway.started.future;
      controller.revokeForConnectionLoss();
      expect(controller.state, DeviceAuthState.unbindPending);
      expect(controller.hasUnbindRecoveryPending, isTrue);

      gateway.result.completeError(StateError('connection closed'));
      await expectLater(request, throwsA(isA<StateError>()));
      expect(controller.state, DeviceAuthState.unbindPending);
      expect(controller.allows(DevicePermission.status), isFalse);
    },
  );

  test(
    'does not allow auth or bind while unbind recovery is pending',
    () async {
      final controller = EvtLegacyAuthController();
      addTearDown(controller.dispose);
      controller.markUnbindRecoveryPending();
      final gateway = _SecurityGateway();

      await expectLater(
        controller.authenticate(gateway, securityCode: '123456'),
        throwsA(isA<EvtLegacyAuthenticationException>()),
      );
      await expectLater(
        controller.bind(gateway, securityCode: '123456'),
        throwsA(isA<EvtLegacyAuthenticationException>()),
      );
      expect(gateway.requests, isEmpty);
      expect(controller.allows(DevicePermission.files), isFalse);
    },
  );

  test('recovery request is explicit and never grants permissions', () async {
    final controller = EvtLegacyAuthController(unbindRecoveryPending: true);
    addTearDown(controller.dispose);
    final gateway = _SecurityGateway();

    await controller.recoverUnbind(gateway, securityCode: '123456');

    expect(gateway.requests.single.recovery, isTrue);
    expect(gateway.requests.single.action, EvtLegacySecurityAction.unbind);
    expect(controller.state, DeviceAuthState.unbound);
    expect(controller.grantedPermissions, isEmpty);
    expect(controller.isAuthenticated, isFalse);
  });
}

class _SecurityGateway implements EvtLegacySecurityGateway {
  final requests = <EvtLegacySecurityRequest>[];

  @override
  Future<bool> executeEvtLegacySecurity(
    EvtLegacySecurityRequest request,
  ) async {
    requests.add(request);
    return true;
  }
}

class _DeferredSecurityGateway implements EvtLegacySecurityGateway {
  final result = Completer<bool>();

  @override
  Future<bool> executeEvtLegacySecurity(EvtLegacySecurityRequest request) =>
      result.future;
}

class _DeferredUnbindGateway implements EvtLegacySecurityGateway {
  final started = Completer<void>();
  final result = Completer<bool>();

  @override
  Future<bool> executeEvtLegacySecurity(EvtLegacySecurityRequest request) {
    if (!started.isCompleted) {
      started.complete();
    }
    return result.future;
  }
}

class _RejectingSecurityGateway implements EvtLegacySecurityGateway {
  final requests = <EvtLegacySecurityRequest>[];

  @override
  Future<bool> executeEvtLegacySecurity(
    EvtLegacySecurityRequest request,
  ) async {
    requests.add(request);
    return false;
  }
}

class _BindThenAuthenticateGateway implements EvtLegacySecurityGateway {
  final requests = <EvtLegacySecurityRequest>[];
  final bindStarted = Completer<void>();
  final bindResult = Completer<bool>();
  final authenticationStarted = Completer<void>();
  final authenticationResult = Completer<bool>();

  @override
  Future<bool> executeEvtLegacySecurity(EvtLegacySecurityRequest request) {
    requests.add(request);
    if (request.action == EvtLegacySecurityAction.bind) {
      bindStarted.complete();
      return bindResult.future;
    }
    authenticationStarted.complete();
    return authenticationResult.future;
  }
}

class _CapturingLogger implements SafeAppLogger {
  final calls = <_LogCall>[];

  Iterable<String> get events => calls.map((call) => call.event);

  @override
  void error(
    String event, {
    DiagnosticTrace? trace,
    String? operation,
    String? stage,
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  }) {
    calls.add(_LogCall(event, fields));
  }

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
    calls.add(_LogCall(event, fields));
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
  }) {
    calls.add(_LogCall(event, fields));
  }
}

class _LogCall {
  const _LogCall(this.event, this.fields);

  final String event;
  final Map<String, Object?> fields;
}
