import 'dart:io';

import 'package:aipin/features/research_beta/domain/research_capture_file_store.dart';
import 'package:path_provider/path_provider.dart';

class AppResearchCaptureFileStore implements ResearchCaptureFileStore {
  AppResearchCaptureFileStore()
    : _rootDirectory = getApplicationDocumentsDirectory;

  AppResearchCaptureFileStore.forTesting({required Directory root})
    : _rootDirectory = (() async => root);

  static final _validRelativePath = RegExp(
    r'^[A-Za-z0-9-]+(?:\.segment-\d{4})?\.m4a$',
  );

  final Future<Directory> Function() _rootDirectory;

  @override
  Future<String> absolutePathFor(String relativePath) async {
    _validateRelativePath(relativePath);
    final directory = await _capturesDirectory();
    return '${directory.path}${Platform.pathSeparator}$relativePath';
  }

  @override
  Future<String> absoluteSegmentPathFor({
    required String captureId,
    required int index,
  }) async => absolutePathFor(
    await relativeSegmentPathFor(captureId: captureId, index: index),
  );

  @override
  Future<String> segmentOutputPathPrefixFor({required String captureId}) async {
    final firstSegmentPath = await absoluteSegmentPathFor(
      captureId: captureId,
      index: 0,
    );
    return firstSegmentPath.replaceFirst(RegExp(r'0000\.m4a$'), '');
  }

  @override
  Future<CompletedResearchCaptureFile> copyFromLocal({
    required String id,
    required String sourcePath,
  }) async {
    final relativePath = '$id.m4a';
    _validateRelativePath(relativePath);
    final source = File(sourcePath);
    await _readNonEmptySize(source);
    final destination = File(await absolutePathFor(relativePath));
    try {
      await source.copy(destination.path);
    } on FileSystemException catch (error) {
      throw ResearchCaptureFileException('无法复制研究录音：${error.message}');
    }
    final sizeBytes = await _readNonEmptySize(destination);
    return CompletedResearchCaptureFile(
      relativePath: relativePath,
      absolutePath: destination.path,
      sizeBytes: sizeBytes,
    );
  }

  @override
  Future<PendingResearchCaptureFile> createPending({required String id}) async {
    final relativePath = '$id.m4a';
    _validateRelativePath(relativePath);
    final directory = await _capturesDirectory();
    return PendingResearchCaptureFile(
      id: id,
      temporaryPath: '${directory.path}${Platform.pathSeparator}$id.part.m4a',
      relativePath: relativePath,
    );
  }

  @override
  Future<String> relativeSegmentPathFor({
    required String captureId,
    required int index,
  }) async {
    if (index < 0 || index > 9999) {
      throw ArgumentError.value(index, 'index', '研究录音分段索引无效。');
    }
    final relativePath =
        '$captureId.segment-${index.toString().padLeft(4, '0')}.m4a';
    _validateRelativePath(relativePath);
    return relativePath;
  }

  @override
  Future<void> delete(String relativePath) async {
    final file = File(await absolutePathFor(relativePath));
    if (!await file.exists()) {
      throw const ResearchCaptureFileException('研究录音文件不存在。');
    }
    try {
      await file.delete();
    } on FileSystemException catch (error) {
      throw ResearchCaptureFileException('无法删除研究录音文件：${error.message}');
    }
  }

  @override
  Future<void> deleteAll() async {
    final directory = await _capturesDirectory();
    try {
      await for (final child in directory.list()) {
        await child.delete(recursive: true);
      }
    } on FileSystemException catch (error) {
      throw ResearchCaptureFileException('无法删除研究录音文件：${error.message}');
    }
  }

  @override
  Future<void> discard(PendingResearchCaptureFile pending) async {
    _validateRelativePath(pending.relativePath);
    final expectedPath = _temporaryPathFor(
      await absolutePathFor(pending.relativePath),
    );
    if (pending.temporaryPath != expectedPath) {
      throw const ResearchCaptureFileException('研究录音临时文件路径无效。');
    }
    final file = File(expectedPath);
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException catch (error) {
      throw ResearchCaptureFileException('无法删除研究录音临时文件：${error.message}');
    }
  }

  @override
  Future<CompletedResearchCaptureFile> finalize(
    PendingResearchCaptureFile pending,
  ) async {
    _validateRelativePath(pending.relativePath);
    final expectedPath = _temporaryPathFor(
      await absolutePathFor(pending.relativePath),
    );
    if (pending.temporaryPath != expectedPath) {
      throw const ResearchCaptureFileException('研究录音临时文件路径无效。');
    }
    final source = File(expectedPath);
    final sizeBytes = await _readNonEmptySize(source);
    final destination = File(await absolutePathFor(pending.relativePath));
    try {
      await source.rename(destination.path);
    } on FileSystemException catch (error) {
      throw ResearchCaptureFileException('无法完成研究录音：${error.message}');
    }
    return CompletedResearchCaptureFile(
      relativePath: pending.relativePath,
      absolutePath: destination.path,
      sizeBytes: sizeBytes,
    );
  }

  Future<Directory> _capturesDirectory() async {
    final root = await _rootDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}research_captures',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<int> _readNonEmptySize(File file) async {
    try {
      if (!await file.exists()) {
        throw const ResearchCaptureFileException('研究录音文件不存在。');
      }
      final sizeBytes = await file.length();
      if (sizeBytes == 0) {
        throw const ResearchCaptureFileException('研究录音文件为空。');
      }
      return sizeBytes;
    } on FileSystemException catch (error) {
      throw ResearchCaptureFileException('无法读取研究录音文件：${error.message}');
    }
  }

  String _temporaryPathFor(String finalPath) {
    return finalPath.replaceFirst(RegExp(r'\.m4a$'), '.part.m4a');
  }

  void _validateRelativePath(String relativePath) {
    if (!_validRelativePath.hasMatch(relativePath)) {
      throw ResearchCaptureFileException('研究录音文件路径无效。');
    }
  }
}
