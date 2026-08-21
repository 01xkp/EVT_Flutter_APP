import 'package:evt_ble_app/features/local_recording/domain/audio_player_port.dart';
import 'package:just_audio/just_audio.dart' as just_audio;

class JustAudioPlayer implements AudioPlayerPort {
  JustAudioPlayer({just_audio.AudioPlayer? player})
    : _player = player ?? just_audio.AudioPlayer();

  final just_audio.AudioPlayer _player;
  String? _activePath;
  var _disposed = false;

  @override
  Stream<Duration> get positions => _player.positionStream;

  @override
  Stream<AudioPlaybackState> get states =>
      _player.playerStateStream.map(_mapState).distinct();

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _player.dispose();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> play(String absolutePath) async {
    if (_activePath != absolutePath) {
      await _player.stop();
      await _player.setFilePath(absolutePath);
      _activePath = absolutePath;
    }
    await _player.play();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    _activePath = null;
  }

  AudioPlaybackState _mapState(just_audio.PlayerState state) {
    if (state.processingState == just_audio.ProcessingState.completed) {
      return AudioPlaybackState.completed;
    }
    if (state.playing) {
      return AudioPlaybackState.playing;
    }
    return state.processingState == just_audio.ProcessingState.idle
        ? AudioPlaybackState.idle
        : AudioPlaybackState.paused;
  }
}
