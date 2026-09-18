import 'dart:async';
import 'dart:math' as math;

import 'package:aipin/core/design_system/widgets/app_toast.dart';
import 'package:aipin/features/local_recording/domain/audio_player_port.dart';
import 'package:aipin/features/local_recording/presentation/playback_waveform.dart';
import 'package:flutter/material.dart';

class AudioPlaybackPanel extends StatefulWidget {
  const AudioPlaybackPanel({
    super.key,
    required this.duration,
    required this.resolvePath,
    required this.audioPlayerFactory,
    required this.playbackErrorMessage,
    this.progressKey,
    this.waveformKey,
    this.onPrevious,
    this.onNext,
  });

  final Duration duration;
  final Future<String> Function() resolvePath;
  final AudioPlayerPort Function() audioPlayerFactory;
  final String playbackErrorMessage;
  final Key? progressKey;
  final Key? waveformKey;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  State<AudioPlaybackPanel> createState() => _AudioPlaybackPanelState();
}

class _AudioPlaybackPanelState extends State<AudioPlaybackPanel> {
  late final AudioPlayerPort _audioPlayer;
  late final StreamSubscription<AudioPlaybackState> _stateSubscription;
  late final StreamSubscription<Duration> _positionSubscription;
  late final StreamSubscription<Duration?> _durationSubscription;
  Timer? _progressTimer;
  bool _loading = true;
  bool _loadFailed = false;
  String? _loadedPath;

  var _playbackState = AudioPlaybackState.idle;
  var _position = Duration.zero;
  late Duration _duration;
  Duration? _scrubPosition;

  static const _progressTick = Duration(milliseconds: 180);

  @override
  void initState() {
    super.initState();
    _duration = widget.duration;
    _audioPlayer = widget.audioPlayerFactory();
    _stateSubscription = _audioPlayer.states.listen(_onPlaybackState);
    _positionSubscription = _audioPlayer.positions.listen((position) {
      if (mounted && _scrubPosition == null) {
        setState(() => _position = _clamp(position));
      }
    });
    _durationSubscription = _audioPlayer.durations.listen((duration) {
      if (mounted && duration != null && duration > Duration.zero) {
        setState(() {
          _duration = duration;
          _position = _clamp(_position);
        });
        _syncProgressTimer();
      }
    });
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant AudioPlaybackPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration &&
        widget.duration > Duration.zero) {
      setState(() {
        _duration = widget.duration;
        _position = _clamp(_position);
      });
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    unawaited(_stateSubscription.cancel());
    unawaited(_positionSubscription.cancel());
    unawaited(_durationSubscription.cancel());
    unawaited(_audioPlayer.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final position = _scrubPosition ?? _position;
    final maximum = _duration.inMilliseconds.toDouble();
    final progress = maximum == 0
        ? 0.0
        : (position.inMilliseconds / maximum).clamp(0.0, 1.0);
    final canSeek = !_loading && _duration > Duration.zero;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PlaybackWaveform(
              key: widget.waveformKey,
              progress: progress,
              isPlaying: _playbackState == AudioPlaybackState.playing,
            ),
            const SizedBox(height: 4),
            Text(
              _loading
                  ? '正在读取录音…'
                  : _loadFailed
                  ? '录音加载失败，请点击播放重试。'
                  : switch (_playbackState) {
                      AudioPlaybackState.playing => '正在播放',
                      AudioPlaybackState.paused => '已暂停',
                      AudioPlaybackState.completed => '播放结束',
                      AudioPlaybackState.idle => '点击播放按钮开始',
                    },
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _ProgressSlider(
                progressKey: widget.progressKey,
                maximum: maximum,
                position: position,
                onChanged: canSeek
                    ? (value) => setState(
                        () => _scrubPosition = Duration(
                          milliseconds: value.round(),
                        ),
                      )
                    : null,
                onChangeEnd: canSeek
                    ? (value) => unawaited(
                        _seek(Duration(milliseconds: value.round())),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Text(_format(position)),
                const Spacer(),
                SizedBox(
                  width: 42,
                  child: Text(
                    _duration > Duration.zero
                        ? _format(_duration)
                        : _loading
                        ? '读取中'
                        : '时长未知',
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _PlaybackControls(
              playbackState: _playbackState,
              onPrevious: widget.onPrevious,
              onTogglePlayback: _loading
                  ? null
                  : () => unawaited(_togglePlayback()),
              onNext: widget.onNext,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadFailed = false;
      });
    }
    try {
      final path = await widget.resolvePath();
      if (!mounted) {
        return;
      }
      final duration = await _audioPlayer.load(path);
      if (!mounted) {
        return;
      }
      setState(() {
        _loadedPath = path;
        if (duration != null && duration > Duration.zero) {
          _duration = duration;
          _position = _clamp(_position);
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loadFailed = true);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _togglePlayback() async {
    if (_loading) {
      return;
    }
    try {
      if (_playbackState == AudioPlaybackState.playing) {
        await _audioPlayer.pause();
        _setPlaybackState(AudioPlaybackState.paused);
        return;
      }
      if (_loadedPath == null) {
        await _load();
        if (!mounted || _loadedPath == null) {
          return;
        }
      }
      if (_playbackState == AudioPlaybackState.completed) {
        await _audioPlayer.seek(Duration.zero);
        if (mounted) {
          setState(() => _position = Duration.zero);
        }
      }
      _setPlaybackState(AudioPlaybackState.playing);
      await _audioPlayer.play(_loadedPath!);
    } catch (_) {
      _setPlaybackState(AudioPlaybackState.idle);
      if (mounted) {
        AppToast.show(context, message: widget.playbackErrorMessage);
      }
    }
  }

  Future<void> _seek(Duration position) async {
    if (_loading || _duration <= Duration.zero) {
      return;
    }
    final target = _clamp(position);
    setState(() {
      _position = target;
      _scrubPosition = null;
    });
    try {
      await _audioPlayer.seek(target);
    } catch (_) {
      if (mounted) {
        AppToast.show(context, message: '无法调整录音播放进度。');
      }
    }
  }

  void _onPlaybackState(AudioPlaybackState state) {
    if (!mounted) {
      return;
    }
    setState(() {
      _playbackState = state;
      if (state == AudioPlaybackState.completed && _duration > Duration.zero) {
        _position = _duration;
      }
    });
    _syncProgressTimer();
  }

  void _setPlaybackState(AudioPlaybackState state) {
    if (!mounted) {
      return;
    }
    setState(() => _playbackState = state);
    _syncProgressTimer();
  }

  void _syncProgressTimer() {
    if (_playbackState != AudioPlaybackState.playing ||
        _duration <= Duration.zero) {
      _progressTimer?.cancel();
      _progressTimer = null;
      return;
    }
    _progressTimer ??= Timer.periodic(_progressTick, (_) {
      if (!mounted ||
          _playbackState != AudioPlaybackState.playing ||
          _duration <= Duration.zero ||
          _scrubPosition != null ||
          _position >= _duration) {
        if (_duration <= Duration.zero || _position >= _duration) {
          _progressTimer?.cancel();
          _progressTimer = null;
        }
        return;
      }
      setState(() => _position = _clamp(_position + _progressTick));
    });
  }

  Duration _clamp(Duration value) {
    if (value <= Duration.zero) {
      return Duration.zero;
    }
    return _duration > Duration.zero && value >= _duration ? _duration : value;
  }

  String _format(Duration value) {
    final totalSeconds = value.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _PlaybackControls extends StatelessWidget {
  const _PlaybackControls({
    required this.playbackState,
    required this.onPrevious,
    required this.onTogglePlayback,
    required this.onNext,
  });

  final AudioPlaybackState playbackState;
  final VoidCallback? onPrevious;
  final VoidCallback? onTogglePlayback;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final isPlaying = playbackState == AudioPlaybackState.playing;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: '上一条录音',
          onPressed: onPrevious,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        const SizedBox(width: 16),
        IconButton.filled(
          tooltip: isPlaying ? '暂停录音' : '播放录音',
          onPressed: onTogglePlayback,
          iconSize: 32,
          constraints: const BoxConstraints.tightFor(width: 56, height: 56),
          icon: Icon(
            isPlaying ? Icons.pause_outlined : Icons.play_arrow_outlined,
          ),
        ),
        const SizedBox(width: 16),
        IconButton(
          tooltip: '下一条录音',
          onPressed: onNext,
          icon: const Icon(Icons.skip_next_rounded),
        ),
      ],
    );
  }
}

class _ProgressSlider extends StatelessWidget {
  const _ProgressSlider({
    required this.progressKey,
    required this.maximum,
    required this.position,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final Key? progressKey;
  final double maximum;
  final Duration position;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final max = math.max(1.0, maximum).toDouble();
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3,
        activeTrackColor: colors.primary,
        inactiveTrackColor: colors.surface.withValues(alpha: 0.84),
        thumbColor: colors.primary,
        overlayColor: colors.primary.withValues(alpha: 0.12),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
      ),
      child: Slider(
        key: progressKey,
        value: maximum <= 0
            ? 0
            : math.min(max, position.inMilliseconds.toDouble()),
        max: max,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
      ),
    );
  }
}
