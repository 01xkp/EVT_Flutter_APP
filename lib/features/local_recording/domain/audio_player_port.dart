enum AudioPlaybackState { idle, playing, paused, completed }

abstract interface class AudioPlayerPort {
  Stream<AudioPlaybackState> get states;
  Stream<Duration> get positions;
  Future<void> play(String absolutePath);
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> stop();
  Future<void> dispose();
}
