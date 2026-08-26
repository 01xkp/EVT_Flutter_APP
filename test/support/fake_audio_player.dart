import 'dart:async';

import 'package:aipin/features/local_recording/domain/audio_player_port.dart';

class FakeAudioPlayer implements AudioPlayerPort {
  final _states = StreamController<AudioPlaybackState>.broadcast();
  final _positions = StreamController<Duration>.broadcast();
  final List<String> playedPaths = [];
  final List<Duration> seekedPositions = [];

  String? activePath;
  bool disposed = false;
  Object? playError;

  @override
  Stream<Duration> get positions => _positions.stream;

  @override
  Stream<AudioPlaybackState> get states => _states.stream;

  @override
  Future<void> dispose() async {
    disposed = true;
    await _states.close();
    await _positions.close();
  }

  void emitPosition(Duration value) => _positions.add(value);

  void emitState(AudioPlaybackState value) => _states.add(value);

  @override
  Future<void> pause() async => _states.add(AudioPlaybackState.paused);

  @override
  Future<void> play(String absolutePath) async {
    if (playError case final error?) {
      throw error;
    }
    activePath = absolutePath;
    playedPaths.add(absolutePath);
    _states.add(AudioPlaybackState.playing);
  }

  @override
  Future<void> seek(Duration position) async {
    seekedPositions.add(position);
    _positions.add(position);
  }

  @override
  Future<void> stop() async {
    activePath = null;
    _states.add(AudioPlaybackState.idle);
  }
}
