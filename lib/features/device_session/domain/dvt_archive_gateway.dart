import 'device_file.dart';

/// A durable cloud archive request for one already-validated device file.
///
/// Implementations must complete only after the content and immutable file
/// triple have been persisted durably. This avoids telling the device it may
/// delete a source file after a best-effort upload.
class DvtArchiveRequest {
  const DvtArchiveRequest({
    required this.deviceId,
    required this.metadata,
    required this.absolutePath,
    required this.sizeBytes,
    required this.crc32,
  });

  final String deviceId;
  final DvtDeviceFileMetadata metadata;
  final String absolutePath;
  final int sizeBytes;
  final int crc32;
}

/// The byte-level result of re-reading the local completed file immediately
/// before it is handed to an archive gateway.
class DvtVerifiedLocalFile {
  const DvtVerifiedLocalFile({required this.sizeBytes, required this.crc32});

  final int sizeBytes;
  final int crc32;
}

/// Verifies the final local file rather than trusting an earlier transfer
/// result. The mobile implementation lives in the data layer; tests can
/// inject a deterministic verifier without touching the filesystem.
abstract interface class DvtLocalFileVerifier {
  Future<DvtVerifiedLocalFile> verify(String absolutePath);
}

abstract interface class DvtArchiveGateway {
  Future<void> archive(DvtArchiveRequest request);
}

/// The default is deliberately non-successful until a real archive endpoint
/// is configured for DVT. It must never stand in for cloud persistence.
class UnconfiguredDvtArchiveGateway implements DvtArchiveGateway {
  const UnconfiguredDvtArchiveGateway();

  @override
  Future<void> archive(DvtArchiveRequest request) async {
    throw const DvtArchiveGatewayUnavailableException();
  }
}

class DvtArchiveGatewayUnavailableException implements Exception {
  const DvtArchiveGatewayUnavailableException();

  @override
  String toString() => 'DVT 云端归档服务未配置。本地文件保留，本次不发送设备归档确认。';
}
