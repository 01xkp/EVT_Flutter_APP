import 'dart:async';

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
