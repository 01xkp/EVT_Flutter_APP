import 'dart:async';

import 'package:evt_ble_app/features/local_recording/domain/audio_player_port.dart';
import 'package:evt_ble_app/features/local_recording/domain/local_recording.dart';
import 'package:evt_ble_app/features/local_recording/domain/local_recording_repository.dart';
import 'package:evt_ble_app/features/local_recording/domain/recording_file_store.dart';
import 'package:flutter/foundation.dart';

class RecordingLibraryState {
  const RecordingLibraryState({
    this.items = const [],
    this.isLoading = false,
    this.selectedPlaybackId,
    this.playbackState = AudioPlaybackState.idle,
    this.playbackPosition = Duration.zero,
    this.errorMessage,
  });

  static const _unset = Object();

  final List<LocalRecording> items;
  final bool isLoading;
  final String? selectedPlaybackId;
  final AudioPlaybackState playbackState;
  final Duration playbackPosition;
  final String? errorMessage;

  RecordingLibraryState copyWith({
    List<LocalRecording>? items,
    bool? isLoading,
    Object? selectedPlaybackId = _unset,
    AudioPlaybackState? playbackState,
    Duration? playbackPosition,
    Object? errorMessage = _unset,
  }) {
    return RecordingLibraryState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      selectedPlaybackId: identical(selectedPlaybackId, _unset)
          ? this.selectedPlaybackId
          : selectedPlaybackId as String?,
      playbackState: playbackState ?? this.playbackState,
      playbackPosition: playbackPosition ?? this.playbackPosition,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

class RecordingLibraryController extends ChangeNotifier {
  factory RecordingLibraryController({
    required LocalRecordingRepository repository,
    required RecordingFileStore files,
    required AudioPlayerPort player,
  }) {
    return RecordingLibraryController._(
      repository: repository,
      files: files,
      player: player,
    );
  }

  RecordingLibraryController._({
    required this._repository,
    required this._files,
    required this._player,
  }) {
    _playerStateSubscription = _player.states.listen(_onPlayerState);
    _positionSubscription = _player.positions.listen(_onPosition);
  }

  final LocalRecordingRepository _repository;
  final RecordingFileStore _files;
  final AudioPlayerPort _player;
  late final StreamSubscription<AudioPlaybackState> _playerStateSubscription;
  late final StreamSubscription<Duration> _positionSubscription;

  RecordingLibraryState _state = const RecordingLibraryState();
  RecordingLibraryState get state => _state;

  var _captureActive = false;
  var _closed = false;

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _playerStateSubscription.cancel();
    await _positionSubscription.cancel();
    await _player.dispose();
    super.dispose();
  }

  Future<void> delete(LocalRecording recording) async {
    await stopPlayback();
    String? errorMessage;
    try {
      await _files.delete(recording.relativePath);
      await _repository.delete(recording.id);
    } on RecordingFileException catch (error) {
      await _repository.update(recording.failed(error.message));
      errorMessage = '无法删除录音，可重试。';
    }
    await load();
    if (errorMessage != null) {
      _setState(_state.copyWith(errorMessage: errorMessage));
    }
  }

  Future<void> load() async {
    _setState(_state.copyWith(isLoading: true, errorMessage: null));
    try {
      final items = await _repository.all();
      _setState(
        _state.copyWith(
          items: List.unmodifiable(items),
          isLoading: false,
          errorMessage: null,
        ),
      );
    } catch (_) {
      _setState(
        _state.copyWith(isLoading: false, errorMessage: '本地录音暂时不可读取。'),
      );
    }
  }

  Future<void> pause() async {
    if (_state.selectedPlaybackId == null) {
      return;
    }
    await _player.pause();
  }

  Future<void> play(String id) async {
    if (_captureActive) {
      _setState(_state.copyWith(errorMessage: '录音进行中，结束后可播放。'));
      return;
    }
    final recording = _recordingFor(id);
    if (recording == null || !recording.isPlayable) {
      _setState(_state.copyWith(errorMessage: '这条录音暂时不可播放。'));
      return;
    }
    try {
      final absolutePath = await _files.absolutePathFor(recording.relativePath);
      await _player.play(absolutePath);
      _setState(
        _state.copyWith(
          selectedPlaybackId: id,
          playbackState: AudioPlaybackState.playing,
          playbackPosition: Duration.zero,
          errorMessage: null,
        ),
      );
    } on RecordingFileException catch (error) {
      _setState(_state.copyWith(errorMessage: error.message));
    } catch (_) {
      _setState(_state.copyWith(errorMessage: '无法播放这条录音。'));
    }
  }

  Future<void> rename(LocalRecording recording, String value) async {
    try {
      await _repository.update(recording.renamed(value));
      await load();
    } on ArgumentError {
      _setState(_state.copyWith(errorMessage: '录音标题不能为空。'));
    } catch (_) {
      _setState(_state.copyWith(errorMessage: '无法修改录音标题。'));
    }
  }

  void setCaptureActive(bool value) {
    _captureActive = value;
    if (value) {
      unawaited(stopPlayback());
    }
  }

  Future<void> stopPlayback() async {
    await _player.stop();
    _setState(
      _state.copyWith(
        selectedPlaybackId: null,
        playbackState: AudioPlaybackState.idle,
        playbackPosition: Duration.zero,
      ),
    );
  }

  LocalRecording? _recordingFor(String id) {
    for (final item in _state.items) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }

  void _onPlayerState(AudioPlaybackState playbackState) {
    if (!_closed && _state.selectedPlaybackId != null) {
      _setState(_state.copyWith(playbackState: playbackState));
    }
  }

  void _onPosition(Duration position) {
    if (!_closed && _state.selectedPlaybackId != null) {
      _setState(_state.copyWith(playbackPosition: position));
    }
  }

  void _setState(RecordingLibraryState value) {
    if (_closed) {
      return;
    }
    _state = value;
    notifyListeners();
  }
}
