import 'package:aipin/features/device_session/domain/device_file.dart';
import 'package:aipin/features/device_session/domain/device_file_download_checkpoint.dart';
import 'package:aipin/features/local_recording/domain/local_recording.dart';

/// Durable evidence that a DVT file has already passed local verification and
/// may need an `ARCHIVE_CONFIRM` retry after the App process is restarted.
///
/// The manifest intentionally stores a relative file pointer only. An absolute
/// path is platform-specific and must never be persisted or emitted in logs.
class DvtPendingArchiveManifest {
  const DvtPendingArchiveManifest({
    required this.checkpoint,
    required this.metadata,
    required this.recording,
    required this.completedRelativePath,
    required this.validatedSizeBytes,
  });

  final DeviceFileDownloadCheckpoint checkpoint;
  final DvtDeviceFileMetadata metadata;
  final LocalRecording recording;
  final String completedRelativePath;
  final int validatedSizeBytes;

  /// A malformed persisted row must never become eligible for archive retry.
  bool get isReadyForRestore {
    if (checkpoint.phase != DeviceFileDownloadPhase.readyForArchive ||
        checkpoint.id !=
            DeviceFileDownloadCheckpoint.idFor(
              deviceId: checkpoint.deviceId,
              nameSlot: checkpoint.nameSlot,
            ) ||
        checkpoint.nameSlot.length != 17 ||
        metadata.nameSlot.length != 17 ||
        !_sameBytes(checkpoint.nameSlot, metadata.nameSlot) ||
        checkpoint.expectedLength != metadata.fileSize ||
        checkpoint.expectedCrc32 != metadata.crc32 ||
        checkpoint.receivedBytes != metadata.fileSize ||
        checkpoint.recordingId != recording.id ||
        recording.relativePath != completedRelativePath ||
        recording.status != LocalRecordingStatus.saved ||
        recording.completedAt == null ||
        recording.sizeBytes != validatedSizeBytes ||
        validatedSizeBytes != metadata.fileSize ||
        !metadata.startUtc.isAtSameMomentAs(recording.createdAt) ||
        metadata.name.trim().isEmpty ||
        completedRelativePath.isEmpty ||
        !_validRelativePath.hasMatch(completedRelativePath) ||
        metadata.fileSize <= 0 ||
        metadata.crc32 < 0 ||
        metadata.crc32 > 0xFFFFFFFF ||
        !_validBytes(checkpoint.nameSlot) ||
        !_validBytes(metadata.nameSlot)) {
      return false;
    }
    return true;
  }

  Map<String, Object?> toJson() {
    if (!isReadyForRestore) {
      throw const FormatException('DVT 待归档清单字段不一致。');
    }
    return <String, Object?>{
      'checkpoint': <String, Object?>{
        'id': checkpoint.id,
        'deviceId': checkpoint.deviceId,
        'nameSlot': List<int>.from(checkpoint.nameSlot),
        'recordingId': checkpoint.recordingId,
        'expectedLength': checkpoint.expectedLength,
        'expectedCrc32': checkpoint.expectedCrc32,
        'receivedBytes': checkpoint.receivedBytes,
        'updatedAt': checkpoint.updatedAt.toUtc().toIso8601String(),
        'phase': checkpoint.phase.name,
      },
      'metadata': <String, Object?>{
        'name': metadata.name,
        'nameSlot': List<int>.from(metadata.nameSlot),
        'startUtc': metadata.startUtc.toUtc().toIso8601String(),
        'recordingSessionId': metadata.recordingSessionId,
        'segmentIndex': metadata.segmentIndex,
        'clockQuality': metadata.clockQuality,
        'utcCorrectionMilliseconds': metadata.utcCorrectionMilliseconds,
        'fileSize': metadata.fileSize,
        'crc32': metadata.crc32,
        'state': metadata.state.wireValue,
      },
      'recording': <String, Object?>{
        'id': recording.id,
        'title': recording.title,
        'relativePath': recording.relativePath,
        'createdAt': recording.createdAt.toUtc().toIso8601String(),
        'status': recording.status.name,
        'completedAt': recording.completedAt?.toUtc().toIso8601String(),
        'durationMilliseconds': recording.duration?.inMilliseconds,
        'sizeBytes': recording.sizeBytes,
        'failureReason': recording.failureReason,
      },
      'completedRelativePath': completedRelativePath,
      'validatedSizeBytes': validatedSizeBytes,
    };
  }

  /// Returns null for every malformed row. In particular, this never fills in
  /// metadata from a file name or a checkpoint because that could authorize an
  /// archive confirmation for a different physical file.
  static DvtPendingArchiveManifest? tryFromJson(Object? source) {
    try {
      if (source is! Map) {
        return null;
      }
      final checkpointMap = _map(source['checkpoint']);
      final metadataMap = _map(source['metadata']);
      final recordingMap = _map(source['recording']);
      if (checkpointMap == null ||
          metadataMap == null ||
          recordingMap == null) {
        return null;
      }
      final checkpoint = DeviceFileDownloadCheckpoint(
        id: _string(checkpointMap, 'id'),
        deviceId: _string(checkpointMap, 'deviceId'),
        nameSlot: _bytes(checkpointMap, 'nameSlot'),
        recordingId: _string(checkpointMap, 'recordingId'),
        expectedLength: _integer(checkpointMap, 'expectedLength'),
        expectedCrc32: _integer(checkpointMap, 'expectedCrc32'),
        receivedBytes: _integer(checkpointMap, 'receivedBytes'),
        updatedAt: _dateTime(checkpointMap, 'updatedAt'),
        phase: DeviceFileDownloadPhase.fromStorageValue(
          _string(checkpointMap, 'phase'),
        ),
      );
      if (checkpoint.phase.name != _string(checkpointMap, 'phase')) {
        return null;
      }
      final metadata = DvtDeviceFileMetadata(
        name: _string(metadataMap, 'name'),
        nameSlot: _bytes(metadataMap, 'nameSlot'),
        startUtc: _dateTime(metadataMap, 'startUtc'),
        recordingSessionId: _integer(metadataMap, 'recordingSessionId'),
        segmentIndex: _integer(metadataMap, 'segmentIndex'),
        clockQuality: _integer(metadataMap, 'clockQuality'),
        utcCorrectionMilliseconds: _integer(
          metadataMap,
          'utcCorrectionMilliseconds',
        ),
        fileSize: _integer(metadataMap, 'fileSize'),
        crc32: _integer(metadataMap, 'crc32'),
        state: DvtDeviceFileState.fromWireValue(_integer(metadataMap, 'state')),
      );
      final statusName = _string(recordingMap, 'status');
      final recording = LocalRecording(
        id: _string(recordingMap, 'id'),
        title: _string(recordingMap, 'title'),
        relativePath: _string(recordingMap, 'relativePath'),
        createdAt: _dateTime(recordingMap, 'createdAt'),
        status: LocalRecordingStatus.values.byName(statusName),
        completedAt: _nullableDateTime(recordingMap, 'completedAt'),
        duration: _nullableDuration(recordingMap, 'durationMilliseconds'),
        sizeBytes: _nullableInteger(recordingMap, 'sizeBytes'),
        failureReason: _nullableString(recordingMap, 'failureReason'),
      );
      final manifest = DvtPendingArchiveManifest(
        checkpoint: checkpoint,
        metadata: metadata,
        recording: recording,
        completedRelativePath: _string(source, 'completedRelativePath'),
        validatedSizeBytes: _integer(source, 'validatedSizeBytes'),
      );
      return manifest.isReadyForRestore ? manifest : null;
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    } on TypeError {
      return null;
    }
  }
}

final RegExp _validRelativePath = RegExp(r'^[A-Za-z0-9-]+\.(m4a|ogg)$');

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

bool _validBytes(List<int> bytes) =>
    bytes.every((value) => value >= 0 && value <= 0xFF);

Map<dynamic, dynamic>? _map(Object? value) => value is Map ? value : null;

String _string(Map<dynamic, dynamic> source, String key) {
  final value = source[key];
  if (value is! String || value.isEmpty) {
    throw const FormatException('DVT 待归档清单字符串字段无效。');
  }
  return value;
}

String? _nullableString(Map<dynamic, dynamic> source, String key) {
  final value = source[key];
  if (value == null || value is String) {
    return value as String?;
  }
  throw const FormatException('DVT 待归档清单可选字符串字段无效。');
}

int _integer(Map<dynamic, dynamic> source, String key) {
  final value = source[key];
  if (value is! int) {
    throw const FormatException('DVT 待归档清单数字字段无效。');
  }
  return value;
}

int? _nullableInteger(Map<dynamic, dynamic> source, String key) {
  final value = source[key];
  if (value == null || value is int) {
    return value as int?;
  }
  throw const FormatException('DVT 待归档清单可选数字字段无效。');
}

List<int> _bytes(Map<dynamic, dynamic> source, String key) {
  final value = source[key];
  if (value is! List) {
    throw const FormatException('DVT 待归档清单字节字段无效。');
  }
  final bytes = <int>[];
  for (final item in value) {
    if (item is! int || item < 0 || item > 0xFF) {
      throw const FormatException('DVT 待归档清单字节值无效。');
    }
    bytes.add(item);
  }
  return List<int>.unmodifiable(bytes);
}

DateTime _dateTime(Map<dynamic, dynamic> source, String key) {
  final value = source[key];
  if (value is! String) {
    throw const FormatException('DVT 待归档清单时间字段无效。');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw const FormatException('DVT 待归档清单时间字段格式无效。');
  }
  return parsed.toUtc();
}

DateTime? _nullableDateTime(Map<dynamic, dynamic> source, String key) {
  final value = source[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw const FormatException('DVT 待归档清单可选时间字段无效。');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw const FormatException('DVT 待归档清单可选时间字段格式无效。');
  }
  return parsed.toUtc();
}

Duration? _nullableDuration(Map<dynamic, dynamic> source, String key) {
  final value = _nullableInteger(source, key);
  if (value == null) {
    return null;
  }
  if (value < 0) {
    throw const FormatException('DVT 待归档清单时长字段无效。');
  }
  return Duration(milliseconds: value);
}
