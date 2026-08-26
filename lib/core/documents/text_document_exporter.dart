import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

abstract interface class TextDocumentExporter {
  Future<void> export({
    required String fileName,
    required String content,
    required String mimeType,
  });
}

class AppTextDocumentExporter implements TextDocumentExporter {
  const AppTextDocumentExporter();

  @override
  Future<void> export({
    required String fileName,
    required String content,
    required String mimeType,
  }) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');
    await file.writeAsString(content);
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(file.path, mimeType: mimeType)],
        title: fileName,
      ),
    );
  }
}
