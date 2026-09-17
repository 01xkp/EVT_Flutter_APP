import 'dart:io';

import 'package:aipin/features/device_session/data/dvt_crc32.dart';
import 'package:aipin/features/device_session/domain/dvt_archive_gateway.dart';

/// Android/iOS implementation of the final local-file verification boundary.
class IoDvtLocalFileVerifier implements DvtLocalFileVerifier {
  const IoDvtLocalFileVerifier();

  @override
  Future<DvtVerifiedLocalFile> verify(String absolutePath) async {
    final file = File(absolutePath);
    try {
      if (!await file.exists()) {
        throw const DvtLocalFileVerificationException('本地已校验文件不存在。');
      }
      final sizeBytes = await file.length();
      if (sizeBytes <= 0) {
        throw const DvtLocalFileVerificationException('本地已校验文件为空。');
      }
      final checksum = DvtCrc32Accumulator();
      await for (final bytes in file.openRead()) {
        checksum.add(bytes);
      }
      return DvtVerifiedLocalFile(sizeBytes: sizeBytes, crc32: checksum.value);
    } on FileSystemException catch (error) {
      throw DvtLocalFileVerificationException('无法读取本地已校验文件：${error.message}');
    }
  }
}

class DvtLocalFileVerificationException implements Exception {
  const DvtLocalFileVerificationException(this.message);

  final String message;

  @override
  String toString() => message;
}
