import 'dart:typed_data';

import 'ticket_gateway.dart';

abstract interface class DeviceSecurityGateway {
  Future<DeviceSecurityResponse> execute(DeviceSecurityRequest request);
}

class DeviceSecurityRequest {
  const DeviceSecurityRequest({
    required this.action,
    required this.transactionId,
    required this.data,
  });

  final DeviceAuthAction action;
  final int transactionId;
  final List<int> data;
}

class DeviceSecurityResponse {
  DeviceSecurityResponse({
    required this.action,
    required this.transactionId,
    required this.result,
    required List<int> data,
  }) : data = Uint8List.fromList(data);

  final DeviceAuthAction action;
  final int transactionId;
  final int result;
  final Uint8List data;
}
