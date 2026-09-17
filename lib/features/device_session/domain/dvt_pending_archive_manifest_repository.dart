import 'package:aipin/features/device_session/domain/dvt_pending_archive_manifest.dart';

/// Storage boundary for verified DVT files awaiting a terminal device archive
/// confirmation. It is deliberately separate from transfer checkpoints so a
/// lost final indication can be recovered without reading the device again.
abstract interface class DvtPendingArchiveManifestRepository {
  Future<void> save(DvtPendingArchiveManifest manifest);

  Future<List<DvtPendingArchiveManifest>> listForDevice(String deviceId);

  Future<void> remove(String checkpointId);
}
