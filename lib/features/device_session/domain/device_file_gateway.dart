import 'dart:typed_data';

import 'package:aipin/features/device_session/domain/device_file.dart';

abstract interface class DeviceFileGateway {
  Future<DeviceFileMetadata> readFileMetadata(List<int> nameSlot);

  Future<Uint8List> readFileChunk({
    required List<int> nameSlot,
    int startOffset,
    int chunkSize,
  });

  Future<int> confirmArchive({
    required List<int> nameSlot,
    required int fileSize,
    required int crc32,
  });
}
