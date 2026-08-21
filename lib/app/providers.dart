import 'dart:async';

import 'package:evt_ble_app/core/ble/ble_transport.dart';
import 'package:evt_ble_app/core/ble/reactive_ble_transport.dart';
import 'package:evt_ble_app/core/persistence/app_database.dart';
import 'package:evt_ble_app/features/evidence/data/drift_evidence_repository.dart';
import 'package:evt_ble_app/features/evidence/domain/evidence_repository.dart';
import 'package:evt_ble_app/features/local_recording/data/app_recording_file_store.dart';
import 'package:evt_ble_app/features/local_recording/data/drift_local_recording_repository.dart';
import 'package:evt_ble_app/features/local_recording/data/foreground_recording_service.dart';
import 'package:evt_ble_app/features/local_recording/data/just_audio_player.dart';
import 'package:evt_ble_app/features/local_recording/data/record_audio_recorder.dart';
import 'package:evt_ble_app/features/local_recording/domain/audio_player_port.dart';
import 'package:evt_ble_app/features/local_recording/domain/audio_recorder_port.dart';
import 'package:evt_ble_app/features/local_recording/domain/local_recording_repository.dart';
import 'package:evt_ble_app/features/local_recording/domain/recording_background_port.dart';
import 'package:evt_ble_app/features/local_recording/domain/recording_file_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final bleTransportProvider = Provider<BleTransport>((ref) {
  return ReactiveBleTransport();
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

final recordingFileStoreProvider = Provider<RecordingFileStore>((ref) {
  return AppRecordingFileStore();
});

final recordingBackgroundProvider = Provider<RecordingBackgroundPort>((ref) {
  return ForegroundRecordingService();
});
