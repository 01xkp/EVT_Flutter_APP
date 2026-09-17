import 'dart:typed_data';

import 'package:aipin/features/device_session/data/dvt_device_file_archive_service.dart';
import 'package:aipin/features/device_session/data/dvt_device_file_import_service.dart';
import 'package:aipin/features/device_session/domain/device_file.dart';
import 'package:aipin/features/device_session/domain/device_file_download_checkpoint.dart';
import 'package:aipin/features/device_session/domain/device_file_download_checkpoint_repository.dart';
import 'package:aipin/features/device_session/domain/device_file_transfer_gateway.dart';
import 'package:aipin/features/device_session/domain/dvt_archive_gateway.dart';
import 'package:aipin/features/device_session/domain/dvt_device_file_metadata_gateway.dart';
import 'package:aipin/features/device_session/domain/dvt_pending_archive_manifest.dart';
import 'package:aipin/features/device_session/domain/dvt_pending_archive_manifest_repository.dart';
import 'package:aipin/features/local_recording/domain/local_recording.dart';
import 'package:aipin/features/local_recording/domain/local_recording_repository.dart';
import 'package:aipin/features/local_recording/domain/recording_file_store.dart';
import 'package:flutter_test/flutter_test.dart';

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

const _file = DeviceFile(
  name: '6a7be704_001.ogg',
  nameSlot: _nameSlot,
  length: 5,
);

void main() {
  test(
    'locally validates a DVT file and leaves it ready for separate archive',
    () async {
      final fixture = _Fixture();

      final imported = await fixture.importer.import(_file);

      expect(fixture.transfer.requests, hasLength(1));
      expect(fixture.transfer.requests.single.startOffset, 0);
      expect(fixture.transfer.requests.single.chunkSize, 0);
      expect(imported.recording.title, _file.name);
      expect(imported.recording.duration, Duration.zero);
      expect(imported.completedFile.sizeBytes, 5);
      expect(fixture.records.values, hasLength(1));
      expect(fixture.checkpoints.items, hasLength(1));
      expect(fixture.manifests.items, hasLength(1));
      expect(
        fixture.checkpoints.items.single.phase,
        DeviceFileDownloadPhase.readyForArchive,
      );
    },
  );

  test(
    'does not send device confirmation when cloud archive is unavailable',
    () async {
      final fixture = _Fixture();
      final imported = await fixture.importer.import(_file);
      final archive = DvtDeviceFileArchiveService(
        metadataGateway: fixture.metadata,
        archiveGateway: const UnconfiguredDvtArchiveGateway(),
        checkpoints: fixture.checkpoints,
        pendingArchives: fixture.manifests,
        localFileVerifier: _Verifier(),
      );

      await expectLater(
        archive.archiveAndConfirm(imported),
        throwsA(isA<DvtArchiveGatewayUnavailableException>()),
      );

      expect(fixture.metadata.confirmations, isEmpty);
      expect(fixture.checkpoints.items, hasLength(1));
      expect(fixture.manifests.items, hasLength(1));
      expect(
        fixture.files.completedBytes(imported.completedFile.relativePath),
        [1, 2, 3, 4, 5],
      );
    },
  );

  test(
    're-verifies final local bytes before cloud then confirms DELETE',
    () async {
      final fixture = _Fixture();
      final imported = await fixture.importer.import(_file);
      final calls = <String>[];
      final archiveGateway = _ArchiveGateway(calls: calls);
      final archive = DvtDeviceFileArchiveService(
        metadataGateway: fixture.metadata,
        archiveGateway: archiveGateway,
        checkpoints: fixture.checkpoints,
        pendingArchives: fixture.manifests,
        localFileVerifier: _Verifier(calls: calls),
      );

      final result = await archive.archiveAndConfirm(imported);

      expect(calls, ['verify', 'archive']);
      expect(result.deviceConfirmation.state, DvtDeviceFileState.deleted);
      expect(fixture.metadata.confirmations, hasLength(1));
      expect(fixture.metadata.confirmations.single.fileSize, 5);
      expect(fixture.metadata.confirmations.single.crc32, 0x470B99F4);
      expect(archiveGateway.requests.single.sizeBytes, 5);
      expect(archiveGateway.requests.single.crc32, 0x470B99F4);
      expect(fixture.checkpoints.items, isEmpty);
      expect(fixture.manifests.items, isEmpty);
    },
  );

  test(
    'keeps the archive checkpoint if final local bytes no longer match',
    () async {
      final fixture = _Fixture();
      final imported = await fixture.importer.import(_file);
      final archiveGateway = _ArchiveGateway();
      final archive = DvtDeviceFileArchiveService(
        metadataGateway: fixture.metadata,
        archiveGateway: archiveGateway,
        checkpoints: fixture.checkpoints,
        pendingArchives: fixture.manifests,
        localFileVerifier: _Verifier(sizeBytes: 4, crc32: 0x12345678),
      );

      await expectLater(
        archive.archiveAndConfirm(imported),
        throwsA(isA<DvtDeviceFileArchiveException>()),
      );

      expect(archiveGateway.requests, isEmpty);
      expect(fixture.metadata.confirmations, isEmpty);
      expect(fixture.checkpoints.items, hasLength(1));
      expect(fixture.manifests.items, hasLength(1));
      expect(
        fixture.checkpoints.items.single.phase,
        DeviceFileDownloadPhase.readyForArchive,
      );
    },
  );

  test('retries the same triple after a non-terminal device result', () async {
    final fixture = _Fixture(
      confirmationStates: <DvtDeviceFileState>[
        DvtDeviceFileState.ready,
        DvtDeviceFileState.deleted,
      ],
    );
    final imported = await fixture.importer.import(_file);
    final archive = DvtDeviceFileArchiveService(
      metadataGateway: fixture.metadata,
      archiveGateway: _ArchiveGateway(),
      checkpoints: fixture.checkpoints,
      pendingArchives: fixture.manifests,
      localFileVerifier: _Verifier(),
    );

    await expectLater(
      archive.archiveAndConfirm(imported),
      throwsA(isA<DvtDeviceFileArchiveException>()),
    );
    expect(fixture.checkpoints.items, hasLength(1));
    expect(fixture.manifests.items, hasLength(1));

    final result = await archive.archiveAndConfirm(imported);

    expect(result.deviceConfirmation.deviceDeleted, isTrue);
    expect(fixture.metadata.confirmations, hasLength(2));
    expect(
      fixture.metadata.confirmations.map((value) => value.nameSlot),
      everyElement(_nameSlot),
    );
    expect(
      fixture.metadata.confirmations.map((value) => value.fileSize),
      everyElement(5),
    );
    expect(
      fixture.metadata.confirmations.map((value) => value.crc32),
      everyElement(0x470B99F4),
    );
    expect(fixture.transfer.requests, hasLength(1));
    expect(fixture.checkpoints.items, isEmpty);
    expect(fixture.manifests.items, isEmpty);
  });

  test(
    'resumes a locally verified file without downloading or saving twice',
    () async {
      final fixture = _Fixture();
      await fixture.importer.import(_file);

      final recovered = await fixture.importer.import(_file);

      expect(
        recovered.checkpoint.phase,
        DeviceFileDownloadPhase.readyForArchive,
      );
      expect(fixture.transfer.requests, hasLength(1));
      expect(fixture.records.values, hasLength(1));
    },
  );

  test(
    'restores a ready archive result without reading metadata or transferring',
    () async {
      final fixture = _Fixture();
      final imported = await fixture.importer.import(_file);
      final metadataRequestsBeforeRestore =
          fixture.metadata.metadataRequests.length;
      final transferRequestsBeforeRestore = fixture.transfer.requests.length;

      final restored = await fixture.freshImporter().restoreReadyImports();

      expect(restored, hasLength(1));
      expect(restored.single.recording.id, imported.recording.id);
      expect(
        restored.single.completedFile.relativePath,
        imported.completedFile.relativePath,
      );
      expect(restored.single.metadata.crc32, imported.metadata.crc32);
      expect(
        fixture.metadata.metadataRequests.length,
        metadataRequestsBeforeRestore,
      );
      expect(fixture.transfer.requests.length, transferRequestsBeforeRestore);
      expect(fixture.metadata.confirmations, isEmpty);
    },
  );

  test(
    'does not restore or archive a corrupt ready file after process restart',
    () async {
      final fixture = _Fixture();
      await fixture.importer.import(_file);
      final metadataRequestsBeforeRestore =
          fixture.metadata.metadataRequests.length;
      final transferRequestsBeforeRestore = fixture.transfer.requests.length;
      final archiveGateway = _ArchiveGateway();

      final restored = await fixture
          .freshImporter(
            localFileVerifier: _Verifier(sizeBytes: 5, crc32: 0x12345678),
          )
          .restoreReadyImports();

      expect(restored, isEmpty);
      expect(
        fixture.metadata.metadataRequests.length,
        metadataRequestsBeforeRestore,
      );
      expect(fixture.transfer.requests.length, transferRequestsBeforeRestore);
      expect(fixture.metadata.confirmations, isEmpty);
      expect(archiveGateway.requests, isEmpty);
      expect(fixture.manifests.items, hasLength(1));
      expect(fixture.checkpoints.items, hasLength(1));
    },
  );

  test(
    'clears ready manifest and checkpoint after reclaimable confirmation',
    () async {
      final fixture = _Fixture(
        confirmationStates: const <DvtDeviceFileState>[
          DvtDeviceFileState.reclaimable,
        ],
      );
      final imported = await fixture.importer.import(_file);
      final archive = DvtDeviceFileArchiveService(
        metadataGateway: fixture.metadata,
        archiveGateway: _ArchiveGateway(),
        checkpoints: fixture.checkpoints,
        pendingArchives: fixture.manifests,
        localFileVerifier: _Verifier(),
      );

      final result = await archive.archiveAndConfirm(imported);

      expect(result.deviceConfirmation.state, DvtDeviceFileState.reclaimable);
      expect(fixture.manifests.items, isEmpty);
      expect(fixture.checkpoints.items, isEmpty);
    },
  );

  test(
    'cleans an untrusted partial file when full CRC-32 validation fails',
    () async {
      final fixture = _Fixture(metadata: _metadata(crc32: 0));

      await expectLater(
        fixture.importer.import(_file),
        throwsA(isA<DvtDeviceFileIntegrityException>()),
      );

      expect(fixture.records.values, isEmpty);
      expect(fixture.checkpoints.items, isEmpty);
      expect(fixture.files.pending, isEmpty);
      expect(fixture.files.completed, isEmpty);
    },
  );
}

class _Fixture {
  _Fixture({
    DvtDeviceFileMetadata? metadata,
    List<DvtDeviceFileState>? confirmationStates,
  }) : metadata = _MetadataGateway(
         metadata ?? _metadata(),
         confirmationStates: confirmationStates,
       ),
       transfer = _Transfer(<EvtDeviceFileTransferEvent>[
         _data([1, 2]),
         _data([3, 4]),
         _data([5]),
         EvtDeviceFileTransferEvent.terminal(),
       ]),
       files = _Files(),
       checkpoints = _Checkpoints(),
       records = _Records(),
       manifests = _PendingArchives() {
    importer = DvtDeviceFileImportService(
      deviceId: 'device-1',
      metadataGateway: this.metadata,
      transferGateway: transfer,
      files: files,
      checkpoints: checkpoints,
      recordings: records,
      pendingArchives: manifests,
      localFileVerifier: _Verifier(),
      now: () => DateTime.utc(2026, 9, 15),
    );
  }

  final _MetadataGateway metadata;
  final _Transfer transfer;
  final _Files files;
  final _Checkpoints checkpoints;
  final _Records records;
  final _PendingArchives manifests;
  late final DvtDeviceFileImportService importer;

  DvtDeviceFileImportService freshImporter({
    DvtLocalFileVerifier? localFileVerifier,
  }) {
    return DvtDeviceFileImportService(
      deviceId: 'device-1',
      metadataGateway: metadata,
      transferGateway: transfer,
      files: files,
      checkpoints: checkpoints,
      recordings: records,
      pendingArchives: manifests,
      localFileVerifier: localFileVerifier ?? _Verifier(),
      now: () => DateTime.utc(2026, 9, 15),
    );
  }
}

DvtDeviceFileMetadata _metadata({int crc32 = 0x470B99F4}) =>
    DvtDeviceFileMetadata(
      name: _file.name,
      nameSlot: _nameSlot,
      startUtc: DateTime.utc(2026, 9, 15),
      recordingSessionId: 7,
      segmentIndex: 0,
      clockQuality: 1,
      utcCorrectionMilliseconds: 0,
      fileSize: _file.length,
      crc32: crc32,
      state: DvtDeviceFileState.ready,
    );

EvtDeviceFileTransferEvent _data(List<int> bytes) =>
    EvtDeviceFileTransferEvent.data(Uint8List.fromList(bytes));

class _MetadataGateway implements DvtDeviceFileMetadataGateway {
  _MetadataGateway(
    this.metadata, {
    List<DvtDeviceFileState>? confirmationStates,
  }) : _confirmationStates = List<DvtDeviceFileState>.from(
         confirmationStates ?? const [DvtDeviceFileState.deleted],
       );

  final DvtDeviceFileMetadata metadata;
  final List<DvtDeviceFileState> _confirmationStates;
  final confirmations = <DvtDeviceArchiveConfirmation>[];
  final metadataRequests = <List<int>>[];

  @override
  Future<DvtDeviceArchiveConfirmationResult> confirmDvtArchive({
    required DvtDeviceArchiveConfirmation confirmation,
  }) async {
    confirmations.add(confirmation);
    return DvtDeviceArchiveConfirmationResult(_confirmationStates.removeAt(0));
  }

  @override
  Future<DvtDeviceFileMetadata> readDvtFileMetadata({
    required List<int> nameSlot,
  }) async {
    metadataRequests.add(List<int>.from(nameSlot));
    return metadata;
  }
}

class _TransferRequest {
  const _TransferRequest({
    required this.nameSlot,
    required this.startOffset,
    required this.chunkSize,
    required this.expectedFileLength,
  });

  final List<int> nameSlot;
  final int startOffset;
  final int chunkSize;
  final int? expectedFileLength;
}

class _Transfer implements DeviceFileTransferGateway {
  _Transfer(this.events);

  final List<EvtDeviceFileTransferEvent> events;
  final requests = <_TransferRequest>[];

  @override
  Stream<EvtDeviceFileTransferEvent> downloadEvtFile({
    required List<int> nameSlot,
    int startOffset = 0,
    int chunkSize = 0,
    int? expectedFileLength,
  }) async* {
    requests.add(
      _TransferRequest(
        nameSlot: List<int>.from(nameSlot),
        startOffset: startOffset,
        chunkSize: chunkSize,
        expectedFileLength: expectedFileLength,
      ),
    );
    yield* Stream<EvtDeviceFileTransferEvent>.fromIterable(events);
  }
}

class _Files implements RecordingFileStore {
  final pending = <String, List<int>>{};
  final completed = <String, List<int>>{};

  List<int> completedBytes(String relativePath) =>
      List<int>.from(completed[relativePath] ?? const <int>[]);

  @override
  Future<void> append(PendingRecordingFile file, List<int> bytes) async {
    pending.putIfAbsent(file.relativePath, () => <int>[]).addAll(bytes);
  }

  @override
  Future<String> absolutePathFor(String relativePath) async => '/$relativePath';

  @override
  Future<void> cleanupOrphanedTemporaryFiles({
    Iterable<String> protectedRecordingIds = const [],
  }) async {}

  @override
  Future<PendingRecordingFile> createPending({
    required String id,
    String extension = '.m4a',
  }) async => PendingRecordingFile(
    id: id,
    temporaryPath: '/$id.part$extension',
    relativePath: '$id$extension',
  );

  @override
  Future<void> delete(String relativePath) async {
    completed.remove(relativePath);
  }

  @override
  Future<void> discard(PendingRecordingFile file) async {
    pending.remove(file.relativePath);
  }

  @override
  Future<bool> exists(String relativePath) async =>
      completed.containsKey(relativePath);

  @override
  Future<CompletedRecordingFile> finalize(PendingRecordingFile file) async {
    final bytes = List<int>.from(pending.remove(file.relativePath) ?? const []);
    completed[file.relativePath] = bytes;
    return _completedFile(file.relativePath, bytes);
  }

  @override
  Future<CompletedRecordingFile> importBytes({
    required String id,
    String extension = '.m4a',
    required Stream<List<int>> chunks,
  }) => throw UnimplementedError();

  @override
  Future<int> pendingLength(PendingRecordingFile file) async =>
      pending[file.relativePath]?.length ?? 0;

  @override
  Stream<List<int>> readPending(PendingRecordingFile file) async* {
    final bytes = pending[file.relativePath] ?? const <int>[];
    if (bytes.isNotEmpty) {
      yield List<int>.from(bytes);
    }
  }

  @override
  Future<CompletedRecordingFile?> recoverPartial(String relativePath) async {
    final bytes = completed[relativePath];
    if (bytes == null) {
      return null;
    }
    return _completedFile(relativePath, bytes);
  }

  CompletedRecordingFile _completedFile(String relativePath, List<int> bytes) =>
      CompletedRecordingFile(
        relativePath: relativePath,
        absolutePath: '/$relativePath',
        sizeBytes: bytes.length,
      );
}

class _Checkpoints implements DeviceFileDownloadCheckpointRepository {
  final items = <DeviceFileDownloadCheckpoint>[];

  @override
  Future<List<DeviceFileDownloadCheckpoint>> allDownloading() async =>
      List<DeviceFileDownloadCheckpoint>.from(items);

  @override
  Future<DeviceFileDownloadCheckpoint?> find({
    required String deviceId,
    required List<int> nameSlot,
  }) async {
    for (final item in items) {
      if (item.deviceId == deviceId && _sameBytes(item.nameSlot, nameSlot)) {
        return item;
      }
    }
    return null;
  }

  @override
  Future<void> remove(String id) async {
    items.removeWhere((item) => item.id == id);
  }

  @override
  Future<void> removeAllForDevice(String deviceId) async {
    items.removeWhere((item) => item.deviceId == deviceId);
  }

  @override
  Future<void> save(DeviceFileDownloadCheckpoint checkpoint) async {
    await remove(checkpoint.id);
    items.add(checkpoint);
  }
}

class _Records implements LocalRecordingRepository {
  final values = <LocalRecording>[];

  @override
  Future<List<LocalRecording>> all() async => List<LocalRecording>.from(values);

  @override
  Future<void> delete(String id) async {
    values.removeWhere((item) => item.id == id);
  }

  @override
  Future<void> save(LocalRecording recording) async {
    values.add(recording);
  }

  @override
  Future<void> update(LocalRecording recording) async {}
}

class _PendingArchives implements DvtPendingArchiveManifestRepository {
  final items = <DvtPendingArchiveManifest>[];

  @override
  Future<List<DvtPendingArchiveManifest>> listForDevice(String deviceId) async {
    return items
        .where((item) => item.checkpoint.deviceId == deviceId)
        .toList(growable: false);
  }

  @override
  Future<void> remove(String checkpointId) async {
    items.removeWhere((item) => item.checkpoint.id == checkpointId);
  }

  @override
  Future<void> save(DvtPendingArchiveManifest manifest) async {
    await remove(manifest.checkpoint.id);
    items.add(manifest);
  }
}

class _ArchiveGateway implements DvtArchiveGateway {
  _ArchiveGateway({this.calls});

  final List<String>? calls;
  final requests = <DvtArchiveRequest>[];

  @override
  Future<void> archive(DvtArchiveRequest request) async {
    calls?.add('archive');
    requests.add(request);
  }
}

class _Verifier implements DvtLocalFileVerifier {
  _Verifier({this.sizeBytes = 5, this.crc32 = 0x470B99F4, this.calls});

  final int sizeBytes;
  final int crc32;
  final List<String>? calls;

  @override
  Future<DvtVerifiedLocalFile> verify(String absolutePath) async {
    calls?.add('verify');
    return DvtVerifiedLocalFile(sizeBytes: sizeBytes, crc32: crc32);
  }
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
