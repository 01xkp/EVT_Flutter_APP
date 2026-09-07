import 'package:aipin/features/device_session/data/https_device_service_support.dart';

class DeviceIntegrationServiceConfiguration {
  const DeviceIntegrationServiceConfiguration._();

  static const ticketApiBaseUrlKey = 'DEVICE_TICKET_API_BASE_URL';
  static const archiveApiBaseUrlKey = 'DEVICE_ARCHIVE_API_BASE_URL';
  static const firmwarePackageApiBaseUrlKey = 'FIRMWARE_PACKAGE_API_BASE_URL';

  static const _ticketApiBaseUrl = String.fromEnvironment(ticketApiBaseUrlKey);
  static const _archiveApiBaseUrl = String.fromEnvironment(
    archiveApiBaseUrlKey,
  );
  static const _firmwarePackageApiBaseUrl = String.fromEnvironment(
    firmwarePackageApiBaseUrlKey,
  );

  static Uri? ticketBaseUri() =>
      DeviceServiceEndpoint.tryParseConfiguredHttpsUrl(_ticketApiBaseUrl);

  static Uri? archiveBaseUri() =>
      DeviceServiceEndpoint.tryParseConfiguredHttpsUrl(_archiveApiBaseUrl);

  static Uri? firmwarePackageBaseUri() =>
      DeviceServiceEndpoint.tryParseConfiguredHttpsUrl(
        _firmwarePackageApiBaseUrl,
      );
}
