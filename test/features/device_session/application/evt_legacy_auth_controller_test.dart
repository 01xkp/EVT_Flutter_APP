import 'dart:async';

import 'package:aipin/core/diagnostics/diagnostic_trace.dart';
import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/features/device_session/application/evt_legacy_auth_controller.dart';
import 'package:aipin/features/device_session/domain/device_auth_state.dart';
import 'package:aipin/features/device_session/domain/device_permission.dart';
import 'package:aipin/features/device_session/domain/evt_legacy_security_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('revokes V1 permissions when the 60-second session expires', () async {
    void Function()? expire;
    final controller = EvtLegacyAuthController(
      authenticationExpiryTimer: (_, callback) {
        expire = callback;
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

    expire!.call();

    expect(controller.state, DeviceAuthState.unbound);
    expect(controller.allows(DevicePermission.configuration), isFalse);
  });

  test('reset cancels the active V1 authentication window', () async {
    void Function()? expire;
    final controller = EvtLegacyAuthController(
      authenticationExpiryTimer: (_, callback) {
        expire = callback;
        return Timer(const Duration(days: 1), () {});
      },
    );
    addTearDown(controller.dispose);
    final gateway = _SecurityGateway();

    await controller.bind(gateway, securityCode: '123456');
    await controller.reset(gateway, securityCode: '123456');
    expire!.call();

    expect(controller.state, DeviceAuthState.unbound);
    expect(controller.allows(DevicePermission.files), isFalse);
    expect(
      gateway.requests.map((request) => request.action),
      <EvtLegacySecurityAction>[
        EvtLegacySecurityAction.bind,
        EvtLegacySecurityAction.reset,
      ],
    );
  });

  test(
    'records authentication steps without retaining the security code',
    () async {
      void Function()? expire;
      final logger = _CapturingLogger();
      final controller = EvtLegacyAuthController(
        logger: logger,
        authenticationExpiryTimer: (_, callback) {
          expire = callback;
          return Timer(const Duration(days: 1), () {});
        },
      );
      addTearDown(controller.dispose);

      await controller.authenticate(_SecurityGateway(), securityCode: '123456');
      expire!.call();

      expect(
        logger.events,
        containsAll(<String>[
          'legacy_authentication_requested',
          'legacy_authentication_started',
          'legacy_authentication_protocol_dispatch',
          'legacy_authentication_window_started',
          'legacy_authentication_completed',
          'legacy_authentication_expired',
        ]),
      );
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
