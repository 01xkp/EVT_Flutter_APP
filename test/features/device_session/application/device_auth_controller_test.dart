import 'dart:typed_data';

import 'package:aipin/features/device_session/application/device_auth_controller.dart';
import 'package:aipin/features/device_session/domain/device_security_gateway.dart';
import 'package:aipin/features/device_session/domain/device_auth_state.dart';
import 'package:aipin/features/device_session/domain/ticket_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'authenticates through the documented begin and confirm actions',
    () async {
      final channel = _SecurityGateway();
      final controller = DeviceAuthController(
        ticketGateway: _TicketGateway(),
        transactionIdSource: () => 0x05060708,
        nonceSource: () => List<int>.generate(16, (index) => 0x10 + index),
      );

      await controller.authenticate(channel, deviceId: 'AIPIN-1234');

      expect(controller.state, DeviceAuthState.authenticated);
      expect(controller.grant?.bindingGeneration, 1);
      expect(controller.grant?.grantedScope, 0x3F);
      expect(channel.actions, [
        DeviceAuthAction.authenticate,
        DeviceAuthAction.authenticationResult,
      ]);
      expect(channel.requests.first.data.sublist(16), <int>[
        11,
        0,
        ...'TKT-AUTH-V2'.codeUnits,
      ]);
    },
  );

  test(
    'waits for user confirmation before starting and completing clear',
    () async {
      final channel = _ClearSecurityGateway();
      final tickets = _TicketGateway();
      final ids = <int>[0x05060708, 0x0A0B0C0D];
      final controller = DeviceAuthController(
        ticketGateway: tickets,
        transactionIdSource: () => ids.removeAt(0),
        nonceSource: () => List<int>.generate(16, (index) => 0x10 + index),
      );

      await controller.authenticate(channel, deviceId: 'AIPIN-1234');
      final preparation = await controller.prepareClear(
        channel,
        deviceId: 'AIPIN-1234',
      );

      expect(preparation.pendingFiles, 3);
      expect(preparation.effectiveClearScope, 0x3F);
      expect(controller.state, DeviceAuthState.clearConfirmationRequired);
      expect(tickets.actions, [DeviceAuthAction.authenticate]);
      expect(channel.actions, [
        DeviceAuthAction.authenticate,
        DeviceAuthAction.authenticationResult,
        DeviceAuthAction.clearRequest,
      ]);

      await controller.confirmClear(channel, deviceId: 'AIPIN-1234');

      expect(tickets.actions, [
        DeviceAuthAction.authenticate,
        DeviceAuthAction.clearConfirm,
      ]);
      expect(channel.actions, [
        DeviceAuthAction.authenticate,
        DeviceAuthAction.authenticationResult,
        DeviceAuthAction.clearRequest,
        DeviceAuthAction.clearConfirm,
        DeviceAuthAction.clearStatus,
      ]);
      expect(controller.grant, isNull);
      expect(controller.state, DeviceAuthState.unbound);
    },
  );
}

class _TicketGateway implements TicketGateway {
  final actions = <DeviceAuthAction>[];

  @override
  Future<TicketMaterial> issue(TicketRequest request) async {
    actions.add(request.action);
    return TicketMaterial(
      ticket: request.action == DeviceAuthAction.clearConfirm
          ? 'TKT-CLEAR-V2'.codeUnits
          : 'TKT-AUTH-V2'.codeUnits,
      proofKey: List<int>.generate(32, (index) => index),
    );
  }
}

class _SecurityGateway implements DeviceSecurityGateway {
  final actions = <DeviceAuthAction>[];
  final requests = <DeviceSecurityRequest>[];

  @override
  Future<DeviceSecurityResponse> execute(DeviceSecurityRequest request) async {
    actions.add(request.action);
    requests.add(request);
    if (request.action == DeviceAuthAction.authenticate) {
      return DeviceSecurityResponse(
        action: request.action,
        transactionId: request.transactionId,
        result: 0,
        data: Uint8List.fromList([
          ...List<int>.generate(16, (index) => 0x20 + index),
          16,
          0,
          0x8A,
          0x2E,
          0x1D,
          0x12,
          0xD9,
          0xAD,
          0x5C,
          0x16,
          0x76,
          0x8B,
          0xF3,
          0xF3,
          0x2F,
          0xF7,
          0x69,
          0xEF,
        ]),
      );
    }
    return DeviceSecurityResponse(
      action: request.action,
      transactionId: request.transactionId,
      result: 0,
      data: Uint8List.fromList([
        1,
        0,
        0,
        0,
        0x10,
        0x0E,
        0,
        0,
        0x44,
        0x33,
        0x22,
        0x11,
        0x3F,
        0,
        0,
        0,
      ]),
    );
  }
}

class _ClearSecurityGateway extends _SecurityGateway {
  @override
  Future<DeviceSecurityResponse> execute(DeviceSecurityRequest request) async {
    if (request.action == DeviceAuthAction.clearRequest) {
      actions.add(request.action);
      requests.add(request);
      return DeviceSecurityResponse(
        action: request.action,
        transactionId: request.transactionId,
        result: 0,
        data: Uint8List.fromList([
          3,
          0,
          ...List<int>.generate(16, (index) => 0x30 + index),
          0,
          0x20,
          0,
          0,
          0x3F,
          0,
          0,
          0,
          1,
          60,
          0,
        ]),
      );
    }
    if (request.action == DeviceAuthAction.clearConfirm) {
      actions.add(request.action);
      requests.add(request);
      return DeviceSecurityResponse(
        action: request.action,
        transactionId: request.transactionId,
        result: 0,
        data: Uint8List.fromList([2, 0, 0]),
      );
    }
    if (request.action == DeviceAuthAction.clearStatus) {
      actions.add(request.action);
      requests.add(request);
      return DeviceSecurityResponse(
        action: request.action,
        transactionId: request.transactionId,
        result: 0,
        data: Uint8List.fromList([100, 0, 3, 0, 0x3F, 0, 0, 0, 7]),
      );
    }
    return super.execute(request);
  }
}
