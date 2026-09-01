import 'dart:typed_data';

/// Provides short-lived, opaque material created by the product security
/// service. The BLE layer must never derive or persist this material itself.
abstract interface class TicketGateway {
  Future<TicketMaterial> issue(TicketRequest request);
}

enum DeviceAuthAction {
  bindRequest(0x10),
  bindConfirm(0x11),
  authenticate(0x20),
  authenticationResult(0x21),
  clearRequest(0x30),
  clearConfirm(0x31),
  clearStatus(0x32);

  const DeviceAuthAction(this.wireValue);

  final int wireValue;
}

class TicketRequest {
  const TicketRequest({
    required this.deviceId,
    required this.action,
    required this.transactionId,
    this.devicePayload = const [],
  });

  final String deviceId;
  final DeviceAuthAction action;
  final int transactionId;
  final List<int> devicePayload;
}

class TicketMaterial {
  TicketMaterial({required List<int> ticket, required List<int> proofKey})
    : ticket = Uint8List.fromList(ticket),
      proofKey = Uint8List.fromList(proofKey);

  /// One-time opaque ticket that is valid only for the requested action.
  final Uint8List ticket;

  /// A 32-byte HTTPS-only proof key. It must never enter an App log or BLE
  /// characteristic payload.
  final Uint8List proofKey;
}

class TicketGatewayUnconfiguredException implements Exception {
  const TicketGatewayUnconfiguredException();

  @override
  String toString() => '认证服务未配置。';
}
