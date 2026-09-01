import 'package:aipin/features/device_session/domain/archive_gateway.dart';

class UnconfiguredArchiveGateway implements ArchiveGateway {
  const UnconfiguredArchiveGateway();

  @override
  Future<void> archive(DeviceArchiveRequest request) {
    return Future<void>.error(const ArchiveGatewayUnavailableException());
  }
}
