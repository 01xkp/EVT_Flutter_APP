import 'package:aipin/features/device_session/domain/firmware_package.dart';
import 'package:aipin/features/device_session/domain/firmware_package_gateway.dart';

class UnconfiguredFirmwarePackageGateway implements FirmwarePackageGateway {
  const UnconfiguredFirmwarePackageGateway();

  @override
  Future<FirmwarePackage> loadForDevice(String deviceId) =>
      Future<FirmwarePackage>.error(
        const FirmwarePackageUnavailableException(),
      );
}
