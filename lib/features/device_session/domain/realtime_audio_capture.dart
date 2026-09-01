import 'dart:typed_data';

class RealtimeAudioCapture {
  RealtimeAudioCapture({required Uint8List bytes, required this.capturedAt})
    : bytes = Uint8List.fromList(bytes);

  final Uint8List bytes;
  final DateTime capturedAt;

  String get exportFileName {
    final time = capturedAt.toLocal().toIso8601String().replaceAll(':', '-');
    return 'aipin-realtime-$time.bin';
  }
}
