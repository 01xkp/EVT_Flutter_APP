/// Immutable progress for a device-file import.
///
/// This belongs to the shared file-transfer domain rather than a particular
/// EVT import implementation, so presentation code does not depend on a
/// retired archive flow.
class DeviceFileImportProgress {
  const DeviceFileImportProgress({required this.received, required this.total});

  final int received;
  final int total;

  double get fraction => total <= 0 ? 0 : (received / total).clamp(0, 1);
}
