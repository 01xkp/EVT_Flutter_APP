import 'package:aipin/features/device_session/data/shared_preferences_dvt_pending_archive_manifest_repository.dart';
import 'package:aipin/features/device_session/domain/device_file.dart';
import 'package:aipin/features/device_session/domain/device_file_download_checkpoint.dart';
import 'package:aipin/features/device_session/domain/dvt_pending_archive_manifest.dart';
import 'package:aipin/features/local_recording/domain/local_recording.dart';
import 'package:flutter_test/flutter_test.dart';

const _storageKey = 'dvt.pending_archive_manifests.v1';
const _nameSlot = <int>[
  0x36,
  0x61,
  0x37,
  0x62,
  0x65,
  0x37,
  0x30,
  0x34,
  0x5f,
  0x30,
  0x30,
  0x31,
  0x2e,
  0x6f,
  0x67,
  0x67,
  0x00,
];

void main() {
  test(
    'persists one complete relative DVT archive recovery manifest',
    () async {
      final preferences = _Preferences();
      final repository = SharedPreferencesDvtPendingArchiveManifestRepository(
        preferences: preferences,
      );
      final manifest = _manifest();

      await repository.save(manifest);
      final restored = await repository.listForDevice('device-1');

      expect(restored, hasLength(1));
      expect(restored.single.checkpoint.id, manifest.checkpoint.id);
      expect(restored.single.metadata.recordingSessionId, 7);
      expect(restored.single.metadata.segmentIndex, 0);
      expect(restored.single.recording.relativePath, 'recording-1.ogg');
      expect(restored.single.validatedSizeBytes, 5);
      expect(preferences.values[_storageKey], isNot(contains('absolutePath')));
      expect(preferences.values[_storageKey], isNot(contains('C:\\')));
    },
  );

  test(
    'drops malformed persisted rows instead of fabricating metadata',
    () async {
      final preferences = _Preferences()
        ..values[_storageKey] =
            '{"version":1,"items":[{"checkpoint":{"id":"fake"}}]}';
      final repository = SharedPreferencesDvtPendingArchiveManifestRepository(
        preferences: preferences,
      );

      expect(await repository.listForDevice('device-1'), isEmpty);
    },
  );

  test('does not persist an inconsistent archive manifest', () {
    final repository = SharedPreferencesDvtPendingArchiveManifestRepository(
      preferences: _Preferences(),
    );
    final valid = _manifest();
    final inconsistent = DvtPendingArchiveManifest(
      checkpoint: valid.checkpoint,
      metadata: valid.metadata,
      recording: valid.recording.copyWith(title: 'renamed'),
      completedRelativePath: 'other.ogg',
      validatedSizeBytes: valid.validatedSizeBytes,
    );

    expect(
      () => repository.save(inconsistent),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'removes the manifest by checkpoint only after terminal cleanup',
    () async {
      final repository = SharedPreferencesDvtPendingArchiveManifestRepository(
        preferences: _Preferences(),
      );
      final manifest = _manifest();
      await repository.save(manifest);

      await repository.remove(manifest.checkpoint.id);

      expect(await repository.listForDevice('device-1'), isEmpty);
    },
  );
}

DvtPendingArchiveManifest _manifest() {
  final createdAt = DateTime.utc(2026, 9, 15, 10);
  final checkpoint = DeviceFileDownloadCheckpoint(
    id: DeviceFileDownloadCheckpoint.idFor(
      deviceId: 'device-1',
      nameSlot: _nameSlot,
    ),
    deviceId: 'device-1',
    nameSlot: _nameSlot,
    recordingId: 'recording-1',
    expectedLength: 5,
    expectedCrc32: 0x470B99F4,
    receivedBytes: 5,
    updatedAt: createdAt,
    phase: DeviceFileDownloadPhase.readyForArchive,
  );
  final metadata = DvtDeviceFileMetadata(
    name: '6a7be704_001.ogg',
    nameSlot: _nameSlot,
    startUtc: createdAt,
    recordingSessionId: 7,
    segmentIndex: 0,
    clockQuality: 1,
    utcCorrectionMilliseconds: 0,
    fileSize: 5,
    crc32: 0x470B99F4,
    state: DvtDeviceFileState.ready,
  );
  final recording = LocalRecording.saved(
    id: 'recording-1',
    title: metadata.name,
    relativePath: 'recording-1.ogg',
    createdAt: createdAt,
    completedAt: createdAt,
    duration: Duration.zero,
    sizeBytes: 5,
  );
  return DvtPendingArchiveManifest(
    checkpoint: checkpoint,
    metadata: metadata,
    recording: recording,
    completedRelativePath: 'recording-1.ogg',
    validatedSizeBytes: 5,
  );
}

class _Preferences implements DvtPendingArchiveManifestPreferences {
  final values = <String, String>{};

  @override
  String? getString(String key) => values[key];

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }

  @override
  Future<bool> setString(String key, String value) async {
    values[key] = value;
    return true;
  }
}
