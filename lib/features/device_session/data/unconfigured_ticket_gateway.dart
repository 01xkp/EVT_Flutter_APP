import 'package:aipin/features/device_session/domain/ticket_gateway.dart';

/// Deliberate default: a production ticket service is required to bind or
/// authenticate a device. Returning synthetic bytes here would be unsafe.
class UnconfiguredTicketGateway implements TicketGateway {
  @override
  Future<TicketMaterial> issue(TicketRequest request) {
    return Future<TicketMaterial>.error(
      const TicketGatewayUnconfiguredException(),
    );
  }
}
