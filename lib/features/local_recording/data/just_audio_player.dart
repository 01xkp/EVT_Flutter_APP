import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/features/local_recording/domain/audio_player_port.dart';
import 'package:just_audio/just_audio.dart' as just_audio;

class JustAudioPlayer implements AudioPlayerPort {
  JustAudioPlayer({just_audio.AudioPlayer? player, SafeAppLogger? logger})
    : _player = player ?? just_audio.AudioPlayer(),
      _logger = logger ?? const DebugSafeAppLogger(scope: 'AUDIO');

  final just_audio.AudioPlayer _player;
  final SafeAppLogger _logger;
  String? _activePath;
  var _disposed = false;

  @override
  Stream<Duration> get positions => _player.positionStream;

  @override
  Stream<Duration?> get durations => _player.durationStream;

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
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<Duration?> load(String absolutePath) async {
    if (_disposed) {
      throw StateError('Audio player is disposed');
    }
    if (_activePath == absolutePath) {
      return _player.duration;
    }
    _activePath = null;
    _log('audio_load_started');
    try {
      await _player.stop();
      if (_disposed) {
        return null;
      }
      final duration = await _player.setFilePath(absolutePath);
      if (!_disposed) {
        _activePath = absolutePath;
        _log(
          'audio_load_completed',
          fields: {
            'duration_ms': duration?.inMilliseconds,
            'state': duration == null || duration <= Duration.zero
                ? 'duration_unknown'
                : 'ready',
          },
        );
      }
      return duration;
    } catch (error) {
      _log(
        'audio_load_failed',
        fields: {'error_type': error.runtimeType.toString()},
      );
      rethrow;
    }
  }

  @override
  Future<void> play(String absolutePath) async {
    await load(absolutePath);
    if (_disposed) {
      return;
    }
    try {
      _log('audio_play_requested');
      await _player.play();
    } catch (error) {
      _log(
        'audio_play_failed',
        fields: {'error_type': error.runtimeType.toString()},
      );
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    _activePath = null;
    await _player.stop();
  }

  void _log(String event, {Map<String, Object?> fields = const {}}) {
    try {
      _logger.info(
        event,
        operation: 'audio_playback',
        stage: 'playback',
        fields: fields,
      );
    } catch (_) {
      // Diagnostics must not affect playback; never record file paths or audio.
    }
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
