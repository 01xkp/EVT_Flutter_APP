import 'device_file.dart';

class DeviceArchiveRequest {
  const DeviceArchiveRequest({
    required this.deviceId,
    required this.metadata,
    required this.absolutePath,
    required this.sizeBytes,
    required this.crc32,
  });

  final String deviceId;
  final DeviceFileMetadata metadata;
  final String absolutePath;
  final int sizeBytes;
  final int crc32;
}

abstract interface class ArchiveGateway {
  Future<void> archive(DeviceArchiveRequest request);
}

class ArchiveGatewayUnavailableException implements Exception {
  const ArchiveGatewayUnavailableException();

  @override
  String toString() => '云端归档服务未配置。设备文件已保留，可在服务配置后重试。';
}
