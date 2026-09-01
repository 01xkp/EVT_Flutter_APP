import 'package:aipin/features/device_session/data/unconfigured_ticket_gateway.dart';
import 'package:aipin/features/device_session/domain/ticket_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'unconfigured gateway rejects a ticket request without material',
    () async {
      final gateway = UnconfiguredTicketGateway();

      await expectLater(
        gateway.issue(
          const TicketRequest(
            deviceId: 'AIPIN-1234',
            action: DeviceAuthAction.authenticate,
            transactionId: 7,
          ),
        ),
        throwsA(isA<TicketGatewayUnconfiguredException>()),
      );
    },
  );
}
