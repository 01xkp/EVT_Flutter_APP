import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:aipin/core/ble/bluetooth_enable_gateway.dart';
import 'package:aipin/core/ble/ble_transport.dart';
import 'package:aipin/core/ble/reactive_ble_transport.dart';
import 'package:aipin/core/persistence/app_database.dart';
import 'package:aipin/core/permissions/app_permission_gateway.dart';
import 'package:aipin/core/permissions/permission_handler_gateway.dart';
import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/features/device_logs/application/app_log_logger.dart';
import 'package:aipin/features/device_logs/application/app_log_upload_controller.dart';
import 'package:aipin/features/device_logs/data/file_app_log_store.dart';
import 'package:aipin/features/device_logs/data/platform_public_diagnostic_log_sink.dart';
import 'package:aipin/features/device_logs/data/https_app_log_upload_port.dart';
import 'package:aipin/features/device_logs/data/unconfigured_app_log_upload_port.dart';
import 'package:aipin/features/device_logs/domain/app_log_upload_port.dart';
import 'package:aipin/features/device_session/data/drift_device_file_download_checkpoint_repository.dart';
import 'package:aipin/features/device_session/domain/device_file_download_checkpoint_repository.dart';
import 'package:aipin/features/device_session/data/shared_preferences_device_connection_history_repository.dart';
import 'package:aipin/features/device_session/domain/device_connection_history_repository.dart';
import 'package:aipin/features/evidence/data/drift_evidence_repository.dart';
import 'package:aipin/features/evidence/domain/evidence_repository.dart';
import 'package:aipin/features/onboarding/data/shared_preferences_onboarding_store.dart';
import 'package:aipin/features/onboarding/domain/onboarding_store.dart';
import 'package:aipin/features/local_recording/data/app_recording_file_store.dart';
import 'package:aipin/features/local_recording/data/drift_local_recording_repository.dart';
import 'package:aipin/features/local_recording/data/just_audio_player.dart';
import 'package:aipin/features/local_recording/domain/audio_player_port.dart';
import 'package:aipin/features/local_recording/domain/local_recording_repository.dart';
import 'package:aipin/features/local_recording/domain/recording_file_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appLogStoreProvider = Provider<FileAppLogStore>((ref) {
  final store = FileAppLogStore(
    publicDiagnosticLogSink: kDebugMode
        ? PlatformPublicDiagnosticLogSink()
        : null,
  );
  unawaited(store.initialize());
  ref.onDispose(store.dispose);
  return store;
});

final appLoggerProvider = Provider<SafeAppLogger>((ref) {
  return PersistentAppLogger(ref.watch(appLogStoreProvider));
});

final scopedAppLoggerProvider = Provider.family<SafeAppLogger, String>((
  ref,
  scope,
) {
  return PersistentAppLogger(ref.watch(appLogStoreProvider), scope: scope);
});

final appLogUploadPortProvider = Provider<AppLogUploadPort>((ref) {
  final configuration = EvtLogUploadServiceConfiguration.uploadConfiguration();
  if (configuration == null) {
    return const UnconfiguredAppLogUploadPort();
  }
  return HttpsAppLogUploadPort(
    configuration: configuration,
    snapshotValidator: ref.watch(appLogStoreProvider),
  );
});

final appLogUploadControllerProvider = Provider<AppLogUploadController>((ref) {
  return AppLogUploadController(
    store: ref.watch(appLogStoreProvider),
    uploader: ref.watch(appLogUploadPortProvider),
    logger: ref.watch(scopedAppLoggerProvider('STORAGE')),
  );
});

final bleTransportProvider = Provider<BleTransport>((ref) {
  final transport = ReactiveBleTransport(
    logger: ref.watch(scopedAppLoggerProvider('BLE')),
  );
  ref.onDispose(() => unawaited(transport.dispose()));
  return transport;
});

final bluetoothEnableGatewayProvider = Provider<BluetoothEnableGateway>((ref) {
  return const PlatformBluetoothEnableGateway();
});

final onboardingStoreProvider = Provider<OnboardingStore>((ref) {
  return SharedPreferencesOnboardingStore();
});

final appPermissionGatewayProvider = Provider<AppPermissionGateway>((ref) {
  return PermissionHandlerGateway();
});

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(() => unawaited(database.close()));
  return database;
});

final evidenceRepositoryProvider = Provider<EvidenceRepository>((ref) {
  return DriftEvidenceRepository(ref.watch(appDatabaseProvider));
});

final localRecordingRepositoryProvider = Provider<LocalRecordingRepository>((
  ref,
) {
  return DriftLocalRecordingRepository(ref.watch(appDatabaseProvider));
});

/// EVT `0x23` imports persist device-owned audio in the App-private directory.
/// This is storage for files received from the pendant, not a microphone API.
final recordingFileStoreProvider = Provider<RecordingFileStore>((ref) {
  return AppRecordingFileStore();
});

final deviceAudioPlayerFactoryProvider = Provider<AudioPlayerPort Function()>((
  ref,
) {
  final logger = ref.watch(scopedAppLoggerProvider('AUDIO'));
  return () => JustAudioPlayer(logger: logger);
});

final deviceFileDownloadCheckpointRepositoryProvider =
    Provider<DeviceFileDownloadCheckpointRepository>((ref) {
      return DriftDeviceFileDownloadCheckpointRepository(
        ref.watch(appDatabaseProvider),
      );
    });

final deviceConnectionHistoryRepositoryProvider =
    Provider<DeviceConnectionHistoryRepository>((ref) {
      return SharedPreferencesDeviceConnectionHistoryRepository();
    });
