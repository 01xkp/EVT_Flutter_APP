import 'dart:async';

import 'package:evt_ble_app/features/local_recording/domain/audio_player_port.dart';

class FakeAudioPlayer implements AudioPlayerPort {
  final _states = StreamController<AudioPlaybackState>.broadcast();
  final _positions = StreamController<Duration>.broadcast();
  final List<String> playedPaths = [];

  String? activePath;
  bool disposed = false;

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

  @override
  Future<void> pause() async => _states.add(AudioPlaybackState.paused);

  @override
  Future<void> play(String absolutePath) async {
    activePath = absolutePath;
    playedPaths.add(absolutePath);
    _states.add(AudioPlaybackState.playing);
  }

  @override
  Future<void> stop() async {
    activePath = null;
    _states.add(AudioPlaybackState.idle);
  }
}
