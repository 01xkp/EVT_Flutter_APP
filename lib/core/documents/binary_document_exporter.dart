import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

abstract interface class BinaryDocumentExporter {
  Future<void> export({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  });
}

class AppBinaryDocumentExporter implements BinaryDocumentExporter {
  AppBinaryDocumentExporter({
    Future<Directory> Function()? temporaryDirectory,
    Future<ShareResult> Function(ShareParams params)? share,
  }) : _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory,
       _share = share ?? SharePlus.instance.share;

  final Future<Directory> Function() _temporaryDirectory;
  final Future<ShareResult> Function(ShareParams params) _share;

  @override
  Future<void> export({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    if (fileName.trim().isEmpty || fileName.contains(RegExp(r'[\\/]'))) {
      throw ArgumentError.value(fileName, 'fileName', 'must be a file name');
    }
    final directory = await _temporaryDirectory();
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await _share(
      ShareParams(
        files: <XFile>[XFile(file.path, mimeType: mimeType)],
        title: fileName,
      ),
    );
  }
}
