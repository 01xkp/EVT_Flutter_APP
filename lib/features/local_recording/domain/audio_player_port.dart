enum AudioPlaybackState { idle, playing, paused, completed }

abstract interface class AudioPlayerPort {
  Stream<AudioPlaybackState> get states;
  Stream<Duration> get positions;

  /// Emits the duration parsed from the active audio file, when available.
  ///
  /// EVT file-list frames do not include duration metadata, so a device
  /// recording can initially be saved with [Duration.zero]. The player is the
  /// authoritative source once the local file has been opened.
  Stream<Duration?> get durations;

  Future<void> play(String absolutePath);
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> stop();
  Future<void> dispose();
}
