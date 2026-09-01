import 'dart:typed_data';

/// Owns the firmware endpoints required for one realtime-audio session.
abstract interface class RealtimeAudioGateway {
  Stream<Uint8List> subscribeRealtimeAudio();

  Future<void> setAudioStreamEnabled(bool enabled);

  Future<void> setRealtimeRecording(bool active);
}
