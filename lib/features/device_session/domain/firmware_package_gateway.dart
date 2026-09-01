import 'package:aipin/features/device_session/domain/firmware_package.dart';

abstract interface class FirmwarePackageGateway {
  Future<FirmwarePackage> loadForDevice(String deviceId);
}

class FirmwarePackageUnavailableException implements Exception {
  const FirmwarePackageUnavailableException();

  @override
  String toString() => '固件包服务未配置。';
}
