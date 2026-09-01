import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:aipin/core/ble/bluetooth_enable_gateway.dart';
import 'package:aipin/core/ble/ble_transport.dart';
import 'package:aipin/core/ble/reactive_ble_transport.dart';
import 'package:aipin/core/documents/binary_document_exporter.dart';
import 'package:aipin/core/persistence/app_database.dart';
import 'package:aipin/core/permissions/app_permission_gateway.dart';
import 'package:aipin/core/permissions/permission_handler_gateway.dart';
import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/features/device_logs/application/app_log_logger.dart';
import 'package:aipin/features/device_logs/data/file_app_log_store.dart';
import 'package:aipin/features/device_session/data/drift_device_file_download_checkpoint_repository.dart';
import 'package:aipin/features/device_session/domain/device_file_download_checkpoint_repository.dart';
import 'package:aipin/features/device_session/domain/ticket_gateway.dart';
import 'package:aipin/features/device_session/data/unconfigured_ticket_gateway.dart';
import 'package:aipin/features/device_session/domain/archive_gateway.dart';
import 'package:aipin/features/device_session/data/unconfigured_archive_gateway.dart';
import 'package:aipin/features/device_session/data/shared_preferences_firmware_update_checkpoint_repository.dart';
import 'package:aipin/features/device_session/data/unconfigured_firmware_package_gateway.dart';
import 'package:aipin/features/device_session/domain/firmware_package_gateway.dart';
import 'package:aipin/features/device_session/domain/firmware_update_checkpoint.dart';
import 'package:aipin/features/evidence/data/drift_evidence_repository.dart';
import 'package:aipin/features/evidence/domain/evidence_repository.dart';
import 'package:aipin/features/onboarding/data/shared_preferences_onboarding_store.dart';
import 'package:aipin/features/onboarding/domain/onboarding_store.dart';
import 'package:aipin/features/local_recording/data/app_recording_file_store.dart';
import 'package:aipin/features/local_recording/data/drift_local_recording_repository.dart';
import 'package:aipin/features/local_recording/data/foreground_recording_service.dart';
import 'package:aipin/features/local_recording/data/just_audio_player.dart';
import 'package:aipin/features/local_recording/data/record_audio_recorder.dart';
import 'package:aipin/features/local_recording/domain/audio_player_port.dart';
import 'package:aipin/features/local_recording/domain/audio_recorder_port.dart';
import 'package:aipin/features/local_recording/domain/local_recording_repository.dart';
import 'package:aipin/features/local_recording/domain/recording_background_port.dart';
import 'package:aipin/features/local_recording/domain/recording_file_store.dart';
import 'package:aipin/features/research_beta/application/research_capture_library_controller.dart';
import 'package:aipin/features/research_beta/application/research_capture_processing_controller.dart';
import 'package:aipin/features/research_beta/data/asr_generated_note_mapper.dart';
import 'package:aipin/features/research_beta/data/ai_voice_service_configuration.dart';
import 'package:aipin/features/research_beta/data/app_research_capture_file_store.dart';
import 'package:aipin/features/research_beta/data/drift_research_capture_repository.dart';
import 'package:aipin/features/research_beta/data/platform_m4a_audio_segmenter.dart';
import 'package:aipin/features/research_beta/data/shared_preferences_research_trial_store.dart';
import 'package:aipin/features/research_beta/data/temporary_asr_http_gateway.dart';
import 'package:aipin/features/research_beta/domain/research_capture_file_store.dart';
import 'package:aipin/features/research_beta/domain/research_capture_repository.dart';
import 'package:aipin/features/research_beta/domain/research_trial.dart';
import 'package:aipin/features/research_beta/domain/audio_segmenter.dart';
import 'package:aipin/features/research_beta/domain/temporary_asr_gateway.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appLogStoreProvider = Provider<FileAppLogStore>((ref) {
  final store = FileAppLogStore();
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

final bleTransportProvider = Provider<BleTransport>((ref) {
  return ReactiveBleTransport(
    logger: ref.watch(scopedAppLoggerProvider('BLE')),
  );
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

final audioRecorderProvider = Provider<AudioRecorderPort>((ref) {
  return RecordAudioRecorder();
});

final audioPlayerProvider = Provider<AudioPlayerPort>((ref) {
  return JustAudioPlayer();
});

final audioPlayerFactoryProvider = Provider<AudioPlayerPort Function()>((ref) {
  return JustAudioPlayer.new;
});

final recordingFileStoreProvider = Provider<RecordingFileStore>((ref) {
  return AppRecordingFileStore();
});

final binaryDocumentExporterProvider = Provider<BinaryDocumentExporter>((ref) {
  return AppBinaryDocumentExporter();
});

final deviceFileDownloadCheckpointRepositoryProvider =
    Provider<DeviceFileDownloadCheckpointRepository>((ref) {
      return DriftDeviceFileDownloadCheckpointRepository(
        ref.watch(appDatabaseProvider),
      );
    });

final ticketGatewayProvider = Provider<TicketGateway>((ref) {
  return UnconfiguredTicketGateway();
});

final archiveGatewayProvider = Provider<ArchiveGateway>((ref) {
  return const UnconfiguredArchiveGateway();
});

final firmwarePackageGatewayProvider = Provider<FirmwarePackageGateway>((ref) {
  return const UnconfiguredFirmwarePackageGateway();
});

final firmwareUpdateCheckpointRepositoryProvider =
    Provider<FirmwareUpdateCheckpointRepository>((ref) {
      return SharedPreferencesFirmwareUpdateCheckpointRepository();
    });

final recordingBackgroundProvider = Provider<RecordingBackgroundPort>((ref) {
  return ForegroundRecordingService();
});

final researchCaptureRepositoryProvider = Provider<ResearchCaptureRepository>((
  ref,
) {
  return DriftResearchCaptureRepository(ref.watch(appDatabaseProvider));
});

final researchCaptureFileStoreProvider = Provider<ResearchCaptureFileStore>((
  ref,
) {
  return AppResearchCaptureFileStore();
});

final audioSegmenterProvider = Provider<AudioSegmenter>((ref) {
  return PlatformM4aAudioSegmenter();
});

final researchTrialStoreProvider = Provider<ResearchTrialStore>((ref) {
  return SharedPreferencesResearchTrialStore();
});

final temporaryAsrGatewayProvider = Provider<TemporaryAsrGateway>((ref) {
  return TemporaryAsrHttpGateway(
    baseUrl: AiVoiceServiceConfiguration.resolveBaseUrl(),
    allowInsecureHttpForTesting: kDebugMode,
    verifiedNoteMapper: mapAsrGeneratedNote,
    logger: ref.watch(scopedAppLoggerProvider('AI')),
  );
});

final researchCaptureProcessingControllerProvider =
    Provider<ResearchCaptureProcessingController>((ref) {
      return ResearchCaptureProcessingController(
        repository: ref.watch(researchCaptureRepositoryProvider),
        researchFiles: ref.watch(researchCaptureFileStoreProvider),
        localFiles: ref.watch(recordingFileStoreProvider),
        gateway: ref.watch(temporaryAsrGatewayProvider),
        audioSegmenter: ref.watch(audioSegmenterProvider),
        trialStore: ref.watch(researchTrialStoreProvider),
      );
    });

final researchCaptureLibraryControllerProvider =
    Provider<ResearchCaptureLibraryController>((ref) {
      return ResearchCaptureLibraryController(
        repository: ref.watch(researchCaptureRepositoryProvider),
        trialStore: ref.watch(researchTrialStoreProvider),
      );
    });
