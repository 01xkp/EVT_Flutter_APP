import 'dart:io';

import 'package:aipin/features/local_recording/domain/recording_file_store.dart';
import 'package:path_provider/path_provider.dart';

class AppRecordingFileStore implements RecordingFileStore {
  AppRecordingFileStore() : _rootDirectory = getApplicationDocumentsDirectory;

  AppRecordingFileStore.forTesting({required Directory root})
    : _rootDirectory = (() async => root);

  static final _validRelativePath = RegExp(r'^[A-Za-z0-9-]+\.m4a$');
  static final _validTemporaryFileName = RegExp(r'^[A-Za-z0-9-]+\.part\.m4a$');

  final Future<Directory> Function() _rootDirectory;

  @override
  Future<String> absolutePathFor(String relativePath) async {
    _validateRelativePath(relativePath);
    final directory = await _recordingsDirectory();
    return '${directory.path}${Platform.pathSeparator}$relativePath';
  }

  @override
  Future<PendingRecordingFile> createPending({required String id}) async {
    final relativePath = '$id.m4a';
    _validateRelativePath(relativePath);
    final directory = await _recordingsDirectory();
    return PendingRecordingFile(
      id: id,
      temporaryPath: '${directory.path}${Platform.pathSeparator}$id.part.m4a',
      relativePath: relativePath,
    );
  }

  @override
  Future<void> discard(PendingRecordingFile pending) async {
    _validateRelativePath(pending.relativePath);
    final expectedPath = _temporaryPathFor(
      await absolutePathFor(pending.relativePath),
    );
    if (pending.temporaryPath != expectedPath) {
      throw const RecordingFileException('录音临时文件路径无效。');
    }
    final file = File(expectedPath);
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException catch (error) {
      throw RecordingFileException('无法删除录音临时文件：${error.message}');
    }
  }

  @override
  Future<void> delete(String relativePath) async {
    final file = File(await absolutePathFor(relativePath));
    if (!await file.exists()) {
      throw const RecordingFileException('录音文件不存在。');
    }
    try {
      await file.delete();
    } on FileSystemException catch (error) {
      throw RecordingFileException('无法删除录音文件：${error.message}');
    }
  }

  @override
  Future<bool> exists(String relativePath) async {
    return File(await absolutePathFor(relativePath)).exists();
  }

  @override
  Future<void> cleanupOrphanedTemporaryFiles() async {
    final directory = await _recordingsDirectory();
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) {
          continue;
        }
        final fileName = entity.path.split(Platform.pathSeparator).last;
        if (_validTemporaryFileName.hasMatch(fileName)) {
          await entity.delete();
        }
      }
    } on FileSystemException catch (error) {
      throw RecordingFileException('无法清理临时录音文件：${error.message}');
    }
  }

  @override
  Future<CompletedRecordingFile> finalize(PendingRecordingFile pending) async {
    _validateRelativePath(pending.relativePath);
    final source = File(pending.temporaryPath);
    final sizeBytes = await _readNonEmptySize(source);
    final destination = File(await absolutePathFor(pending.relativePath));
    try {
      await source.rename(destination.path);
    } on FileSystemException catch (error) {
      throw RecordingFileException('无法完成录音文件：${error.message}');
    }
    return CompletedRecordingFile(
      relativePath: pending.relativePath,
      absolutePath: destination.path,
      sizeBytes: sizeBytes,
    );
  }

  @override
  Future<CompletedRecordingFile?> recoverPartial(String relativePath) async {
    _validateRelativePath(relativePath);
    final finalPath = await absolutePathFor(relativePath);
    final finalized = File(finalPath);
    if (await finalized.exists()) {
      final sizeBytes = await _readNonEmptySize(finalized);
      return CompletedRecordingFile(
        relativePath: relativePath,
        absolutePath: finalPath,
        sizeBytes: sizeBytes,
      );
    }

    final temporary = File(_temporaryPathFor(finalPath));
    if (!await temporary.exists()) {
      return null;
    }
    final sizeBytes = await _readNonEmptySize(temporary);
    try {
      await temporary.rename(finalPath);
    } on FileSystemException catch (error) {
      throw RecordingFileException('无法恢复录音文件：${error.message}');
    }
    return CompletedRecordingFile(
      relativePath: relativePath,
      absolutePath: finalPath,
      sizeBytes: sizeBytes,
    );
  }

  Future<Directory> _recordingsDirectory() async {
    final root = await _rootDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}recordings',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<int> _readNonEmptySize(File file) async {
    try {
      if (!await file.exists()) {
        throw const RecordingFileException('录音文件不存在。');
      }
      final sizeBytes = await file.length();
      if (sizeBytes == 0) {
        throw const RecordingFileException('录音文件为空。');
      }
      return sizeBytes;
    } on FileSystemException catch (error) {
      throw RecordingFileException('无法读取录音文件：${error.message}');
    }
  }

  String _temporaryPathFor(String finalPath) {
    return finalPath.replaceFirst(RegExp(r'\.m4a$'), '.part.m4a');
  }

  void _validateRelativePath(String relativePath) {
    if (!_validRelativePath.hasMatch(relativePath)) {
      throw RecordingFileException('录音文件路径无效。');
    }
  }
}
