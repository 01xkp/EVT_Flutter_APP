import 'dart:io';
import 'dart:typed_data';

import 'package:aipin/core/documents/binary_document_exporter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  test(
    'writes raw capture bytes before opening the system share sheet',
    () async {
      final directory = await Directory.systemTemp.createTemp('aipin-export-');
      ShareParams? shared;
      addTearDown(() => directory.delete(recursive: true));
      final exporter = AppBinaryDocumentExporter(
        temporaryDirectory: () async => directory,
        share: (params) async {
          shared = params;
          return ShareResult('test', ShareResultStatus.success);
        },
      );

      await exporter.export(
        fileName: 'capture.bin',
        bytes: Uint8List.fromList(const [1, 2, 3]),
        mimeType: 'application/octet-stream',
      );

      final output = File(
        '${directory.path}${Platform.pathSeparator}capture.bin',
      );
      expect(await output.readAsBytes(), Uint8List.fromList(const [1, 2, 3]));
      expect(shared?.title, 'capture.bin');
      expect(shared!.files!.single.mimeType, 'application/octet-stream');
    },
  );
}
