import 'dart:typed_data';

import 'package:aipin/core/diagnostics/diagnostic_trace.dart';
import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/features/device_session/data/evt_device_file_import_service.dart';
import 'package:aipin/features/device_session/domain/device_file.dart';
import 'package:aipin/features/device_session/domain/device_file_download_checkpoint.dart';
import 'package:aipin/features/device_session/domain/device_file_download_checkpoint_repository.dart';
import 'package:aipin/features/device_session/domain/device_file_transfer_gateway.dart';
import 'package:aipin/features/local_recording/domain/recording_file_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_local_recording_repository.dart';

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
    'uses one continuous EVT file-transfer stream and saves after completion',
    () async {
      final gateway = _TransferGateway(<EvtDeviceFileTransferEvent>[
        _data(<int>[1, 2]),
        _data(<int>[3, 4]),
        _data(<int>[5]),
        EvtDeviceFileTransferEvent.terminal(),
      ]);
      final files = _RecordingFiles();
      final checkpoints = _Checkpoints();
      final recordings = FakeLocalRecordingRepository();
      final service = _service(
        gateway: gateway,
        files: files,
        checkpoints: checkpoints,
        recordings: recordings,
      );

      final recording = await service.import(_file);

      expect(gateway.requests, hasLength(1));
      expect(gateway.requests.single.nameSlot, _nameSlot);
      expect(gateway.requests.single.startOffset, 0);
      expect(gateway.requests.single.chunkSize, 0);
      expect(files.finalizeCalls, 1);
      expect(files.completedBytes(recording.relativePath), <int>[
        1,
        2,
        3,
        4,
        5,
      ]);
      expect(recordings.values, hasLength(1));
      expect(recordings.values.single.title, _file.name);
      expect(recordings.values.single.sizeBytes, 5);
      expect(recordings.values.single.duration, Duration.zero);
      expect(checkpoints.items, isEmpty);
    },
  );

  test(
    'records safe import stages without retaining the device file name',
    () async {
      final logger = _CapturingLogger();
      final service = _service(
        gateway: _TransferGateway(<EvtDeviceFileTransferEvent>[
          _data(<int>[1, 2, 3, 4, 5]),
          EvtDeviceFileTransferEvent.terminal(),
        ]),
        files: _RecordingFiles(),
        checkpoints: _Checkpoints(),
        recordings: FakeLocalRecordingRepository(),
        logger: logger,
      );

      await service.import(_file);

      expect(
        logger.events,
        containsAll(<String>[
          'device_file_import_requested',
          'device_file_import_new_transfer',
          'device_file_import_transfer_started',
          'device_file_import_progress',
          'device_file_import_completed',
        ]),
      );
      expect(
        logger.calls.expand((call) => call.fields.values).join(' '),
        isNot(contains(_file.name)),
      );
    },
  );

  test(
    'resumes one continuous stream from the persisted local offset',
    () async {
      final gateway = _TransferGateway(<EvtDeviceFileTransferEvent>[
        _data(<int>[3, 4]),
        _data(<int>[5]),
        EvtDeviceFileTransferEvent.terminal(),
      ]);
      final files = _RecordingFiles();
      files.seedPending('device-existing.ogg', <int>[1, 2]);
      final checkpoints = _Checkpoints()
        ..items.add(
          DeviceFileDownloadCheckpoint(
            id: DeviceFileDownloadCheckpoint.idFor(
              deviceId: 'device-1',
              nameSlot: _nameSlot,
            ),
            deviceId: 'device-1',
            nameSlot: _nameSlot,
            recordingId: 'device-existing',
            expectedLength: _file.length,
            expectedCrc32: 0,
            receivedBytes: 2,
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );
      final recordings = FakeLocalRecordingRepository();
      final service = _service(
        gateway: gateway,
        files: files,
        checkpoints: checkpoints,
        recordings: recordings,
      );

      final recording = await service.import(_file);

      expect(gateway.requests, hasLength(1));
      expect(gateway.requests.single.startOffset, 2);
      expect(gateway.requests.single.chunkSize, 0);
      expect(recording.relativePath, 'device-existing.ogg');
      expect(files.recoverPartialCalls, 0);
      expect(files.completedBytes(recording.relativePath), <int>[
        1,
        2,
        3,
        4,
        5,
      ]);
      expect(recordings.values, hasLength(1));
      expect(checkpoints.items, isEmpty);
    },
  );

  test(
    'rejects an EVT terminal frame before the declared length arrives',
    () async {
      final gateway = _TransferGateway(<EvtDeviceFileTransferEvent>[
        _data(<int>[1, 2]),
        _data(<int>[3, 4]),
        EvtDeviceFileTransferEvent.terminal(),
      ]);
      final files = _RecordingFiles();
      final checkpoints = _Checkpoints();
      final recordings = FakeLocalRecordingRepository();
      gateway.beforeChunk = () => expect(recordings.values, isEmpty);
      final service = _service(
        gateway: gateway,
        files: files,
        checkpoints: checkpoints,
        recordings: recordings,
      );

      await expectLater(
        service.import(_file),
        throwsA(isA<EvtDeviceFileImportException>()),
      );

      expect(files.finalizeCalls, 0);
      expect(recordings.values, isEmpty);
      expect(checkpoints.items, hasLength(1));
      expect(checkpoints.items.single.receivedBytes, 4);
    },
  );

  test(
    'rejects exact-length data when the mandatory EVT terminal frame is missing',
    () async {
      final gateway = _TransferGateway(<EvtDeviceFileTransferEvent>[
        _data(<int>[1, 2]),
        _data(<int>[3, 4]),
        _data(<int>[5]),
      ]);
      final files = _RecordingFiles();
      final checkpoints = _Checkpoints();
      final recordings = FakeLocalRecordingRepository();
      final service = _service(
        gateway: gateway,
        files: files,
        checkpoints: checkpoints,
        recordings: recordings,
      );

      await expectLater(
        service.import(_file),
        throwsA(isA<EvtDeviceFileImportException>()),
      );

      expect(files.finalizeCalls, 0);
      expect(recordings.values, isEmpty);
      expect(checkpoints.items, hasLength(1));
      expect(checkpoints.items.single.receivedBytes, _file.length);
    },
  );

  test(
    'rejects a duplicate EVT terminal frame without finalizing or persisting',
    () async {
      final gateway = _TransferGateway(<EvtDeviceFileTransferEvent>[
        _data(<int>[1, 2]),
        _data(<int>[3, 4]),
        _data(<int>[5]),
        EvtDeviceFileTransferEvent.terminal(),
        EvtDeviceFileTransferEvent.terminal(),
      ]);
      final files = _RecordingFiles();
      final checkpoints = _Checkpoints();
      final recordings = FakeLocalRecordingRepository();
      final service = _service(
        gateway: gateway,
        files: files,
        checkpoints: checkpoints,
        recordings: recordings,
      );

      await expectLater(
        service.import(_file),
        throwsA(isA<EvtDeviceFileImportException>()),
      );

      expect(files.finalizeCalls, 0);
      expect(recordings.values, isEmpty);
      expect(checkpoints.items, hasLength(1));
      expect(checkpoints.items.single.receivedBytes, _file.length);
    },
  );

  test(
    'rejects data after the EVT terminal frame without finalizing or persisting',
    () async {
      final gateway = _TransferGateway(<EvtDeviceFileTransferEvent>[
        _data(<int>[1, 2]),
        _data(<int>[3, 4]),
        _data(<int>[5]),
        EvtDeviceFileTransferEvent.terminal(),
        _data(<int>[6]),
      ]);
      final files = _RecordingFiles();
      final checkpoints = _Checkpoints();
      final recordings = FakeLocalRecordingRepository();
      final service = _service(
        gateway: gateway,
        files: files,
        checkpoints: checkpoints,
        recordings: recordings,
      );

      await expectLater(
        service.import(_file),
        throwsA(isA<EvtDeviceFileImportException>()),
      );

      expect(files.finalizeCalls, 0);
      expect(recordings.values, isEmpty);
      expect(checkpoints.items, hasLength(1));
      expect(checkpoints.items.single.receivedBytes, _file.length);
    },
  );

  test('rejects a non-17-byte name slot before starting transfer', () async {
    final gateway = _TransferGateway(<EvtDeviceFileTransferEvent>[
      _data(<int>[1, 2, 3, 4, 5]),
    ]);
    final files = _RecordingFiles();
    final checkpoints = _Checkpoints();
    final recordings = FakeLocalRecordingRepository();
    final service = _service(
      gateway: gateway,
      files: files,
      checkpoints: checkpoints,
      recordings: recordings,
    );
    const invalidFile = DeviceFile(
      name: '6a7be704_001.ogg',
      nameSlot: <int>[
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
      ],
      length: 5,
    );

    await expectLater(
      service.import(invalidFile),
      throwsA(isA<EvtDeviceFileImportException>()),
    );

    expect(gateway.requests, isEmpty);
    expect(files.createPendingCalls, 0);
    expect(checkpoints.findCalls, 0);
    expect(recordings.values, isEmpty);
  });
}

EvtDeviceFileImportService _service({
  required _TransferGateway gateway,
  required _RecordingFiles files,
  required _Checkpoints checkpoints,
  required FakeLocalRecordingRepository recordings,
  SafeAppLogger? logger,
}) {
  return EvtDeviceFileImportService(
    deviceId: 'device-1',
    gateway: gateway,
    files: files,
    checkpoints: checkpoints,
    recordings: recordings,
    now: () => DateTime.utc(2026, 1, 1),
    logger: logger,
  );
}

class _DownloadRequest {
  const _DownloadRequest({
    required this.nameSlot,
    required this.startOffset,
    required this.chunkSize,
  });

  final List<int> nameSlot;
  final int startOffset;
  final int chunkSize;
}

EvtDeviceFileTransferEvent _data(List<int> bytes) =>
    EvtDeviceFileTransferEvent.data(Uint8List.fromList(bytes));

class _TransferGateway implements DeviceFileTransferGateway {
  _TransferGateway(this.events);

  final List<EvtDeviceFileTransferEvent> events;
  final requests = <_DownloadRequest>[];
  void Function()? beforeChunk;

  @override
  Stream<EvtDeviceFileTransferEvent> downloadEvtFile({
    required List<int> nameSlot,
    int startOffset = 0,
    int chunkSize = 0,
  }) async* {
    requests.add(
      _DownloadRequest(
        nameSlot: List<int>.from(nameSlot),
        startOffset: startOffset,
        chunkSize: chunkSize,
      ),
    );
    for (final event in events) {
      if (!event.isTerminal) {
        beforeChunk?.call();
      }
      yield event;
    }
  }
}

class _RecordingFiles implements RecordingFileStore {
  final _pending = <String, List<int>>{};
  final _completed = <String, List<int>>{};
  var createPendingCalls = 0;
  var finalizeCalls = 0;
  var recoverPartialCalls = 0;

  void seedPending(String relativePath, List<int> bytes) {
    _pending[relativePath] = List<int>.from(bytes);
  }

  List<int> completedBytes(String relativePath) =>
      List<int>.from(_completed[relativePath] ?? const <int>[]);

  @override
  Future<PendingRecordingFile> createPending({
    required String id,
    String extension = '.m4a',
  }) async {
    createPendingCalls += 1;
    return PendingRecordingFile(
      id: id,
      temporaryPath: '/$id.part$extension',
      relativePath: '$id$extension',
    );
  }

  @override
  Future<void> append(PendingRecordingFile pending, List<int> bytes) async {
    _pending.putIfAbsent(pending.relativePath, () => <int>[]).addAll(bytes);
  }

  @override
  Future<int> pendingLength(PendingRecordingFile pending) async =>
      _pending[pending.relativePath]?.length ?? 0;

  @override
  Stream<List<int>> readPending(PendingRecordingFile pending) async* {
    final bytes = _pending[pending.relativePath] ?? const <int>[];
    if (bytes.isNotEmpty) {
      yield List<int>.from(bytes);
    }
  }

  @override
  Future<CompletedRecordingFile> finalize(PendingRecordingFile pending) async {
    finalizeCalls += 1;
    final bytes = List<int>.from(
      _pending.remove(pending.relativePath) ?? const <int>[],
    );
    _completed[pending.relativePath] = bytes;
    return CompletedRecordingFile(
      relativePath: pending.relativePath,
      absolutePath: '/${pending.relativePath}',
      sizeBytes: bytes.length,
    );
  }

  @override
  Future<void> discard(PendingRecordingFile pending) async {
    _pending.remove(pending.relativePath);
  }

  @override
  Future<CompletedRecordingFile?> recoverPartial(String relativePath) async {
    recoverPartialCalls += 1;
    final completed = _completed[relativePath];
    if (completed != null) {
      return _completedFile(relativePath, completed);
    }
    final partial = _pending.remove(relativePath);
    if (partial == null) {
      return null;
    }
    _completed[relativePath] = partial;
    return _completedFile(relativePath, partial);
  }

  @override
  Future<CompletedRecordingFile> importBytes({
    required String id,
    String extension = '.m4a',
    required Stream<List<int>> chunks,
  }) => throw UnimplementedError();

  @override
  Future<String> absolutePathFor(String relativePath) async => '/$relativePath';

  @override
  Future<bool> exists(String relativePath) async =>
      _completed.containsKey(relativePath);

  @override
  Future<void> delete(String relativePath) async {
    _pending.remove(relativePath);
    _completed.remove(relativePath);
  }

  @override
  Future<void> cleanupOrphanedTemporaryFiles({
    Iterable<String> protectedRecordingIds = const [],
  }) async {}

  CompletedRecordingFile _completedFile(String relativePath, List<int> bytes) =>
      CompletedRecordingFile(
        relativePath: relativePath,
        absolutePath: '/$relativePath',
        sizeBytes: bytes.length,
      );
}

class _Checkpoints implements DeviceFileDownloadCheckpointRepository {
  final items = <DeviceFileDownloadCheckpoint>[];
  var findCalls = 0;

  @override
  Future<List<DeviceFileDownloadCheckpoint>> allDownloading() async {
    return List<DeviceFileDownloadCheckpoint>.unmodifiable(items);
  }

  @override
  Future<DeviceFileDownloadCheckpoint?> find({
    required String deviceId,
    required List<int> nameSlot,
  }) async {
    findCalls += 1;
    for (final item in items) {
      if (item.deviceId == deviceId && _sameBytes(item.nameSlot, nameSlot)) {
        return item;
      }
    }
    return null;
  }

  @override
  Future<void> save(DeviceFileDownloadCheckpoint checkpoint) async {
    await remove(checkpoint.id);
    items.add(checkpoint);
  }

  @override
  Future<void> remove(String id) async {
    items.removeWhere((item) => item.id == id);
  }

  @override
  Future<void> removeAllForDevice(String deviceId) async {
    items.removeWhere((item) => item.deviceId == deviceId);
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
}

class _CapturingLogger implements SafeAppLogger {
  final calls = <_LogCall>[];

  Iterable<String> get events => calls.map((call) => call.event);

  @override
  void error(
    String event, {
    DiagnosticTrace? trace,
    String? operation,
    String? stage,
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  }) => calls.add(_LogCall(event, fields));

  @override
  void info(
    String event, {
    DiagnosticTrace? trace,
    String? operation,
    String? stage,
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  }) => calls.add(_LogCall(event, fields));

  @override
  void warning(
    String event, {
    DiagnosticTrace? trace,
    String? operation,
    String? stage,
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  }) => calls.add(_LogCall(event, fields));
}

class _LogCall {
  const _LogCall(this.event, this.fields);

  final String event;
  final Map<String, Object?> fields;
}
