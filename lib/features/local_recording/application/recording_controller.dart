import 'dart:async';

import 'package:evt_ble_app/features/local_recording/domain/audio_recorder_port.dart';
import 'package:evt_ble_app/features/local_recording/domain/local_recording.dart';
import 'package:evt_ble_app/features/local_recording/domain/local_recording_repository.dart';
import 'package:evt_ble_app/features/local_recording/domain/recording_background_port.dart';
import 'package:evt_ble_app/features/local_recording/domain/recording_file_store.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

enum ActiveRecordingPhase {
  idle,
  starting,
  recording,
  paused,
  stopping,
  permissionDenied,
  error,
}

class ActiveRecordingState {
  const ActiveRecordingState({
    required this.phase,
    this.recording,
    this.elapsed = Duration.zero,
    this.amplitude = 0,
    this.errorMessage,
  });

  const ActiveRecordingState.idle() : this(phase: ActiveRecordingPhase.idle);

  final ActiveRecordingPhase phase;
  final LocalRecording? recording;
  final Duration elapsed;
  final double amplitude;
  final String? errorMessage;

  bool get isCaptureActive =>
      phase == ActiveRecordingPhase.starting ||
      phase == ActiveRecordingPhase.recording ||
      phase == ActiveRecordingPhase.paused ||
      phase == ActiveRecordingPhase.stopping;

  ActiveRecordingState copyWith({
    ActiveRecordingPhase? phase,
    LocalRecording? recording,
    Duration? elapsed,
    double? amplitude,
    String? errorMessage,
  }) {
    return ActiveRecordingState(
      phase: phase ?? this.phase,
      recording: recording ?? this.recording,
      elapsed: elapsed ?? this.elapsed,
      amplitude: amplitude ?? this.amplitude,
      errorMessage: errorMessage,
    );
  }
}

class RecordingController extends ChangeNotifier {
  factory RecordingController({
    required LocalRecordingRepository repository,
    required AudioRecorderPort recorder,
    required RecordingFileStore files,
    required RecordingBackgroundPort background,
    String Function()? idGenerator,
    DateTime Function()? now,
  }) {
    return RecordingController._(
      repository: repository,
      recorder: recorder,
      files: files,
      background: background,
      idGenerator: idGenerator ?? const Uuid().v4,
      now: now ?? DateTime.now,
    );
  }

  RecordingController._({
    required this._repository,
    required this._recorder,
    required this._files,
    required this._background,
    required this._idGenerator,
    required this._now,
  }) {
    _signalSubscription = _recorder.signals.listen(_onSignal);
    _amplitudeSubscription = _recorder.amplitudes.listen(_onAmplitude);
  }

  final LocalRecordingRepository _repository;
  final AudioRecorderPort _recorder;
  final RecordingFileStore _files;
  final RecordingBackgroundPort _background;
  final String Function() _idGenerator;
  final DateTime Function() _now;
  late final StreamSubscription<RecorderSignal> _signalSubscription;
  late final StreamSubscription<double> _amplitudeSubscription;

  ActiveRecordingState _state = const ActiveRecordingState.idle();
  ActiveRecordingState get state => _state;

  PendingRecordingFile? _pending;
  LocalRecording? _activeRecording;
  Timer? _ticker;
  Future<void>? _finalizing;
  var _backgroundStarted = false;
  var _closed = false;

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _ticker?.cancel();
    await _signalSubscription.cancel();
    await _amplitudeSubscription.cancel();
    await _recorder.dispose();
    super.dispose();
  }

  Future<void> pause() async {
    if (_state.phase != ActiveRecordingPhase.recording) {
      return;
    }
    await _recorder.pause();
    _ticker?.cancel();
    _setState(_state.copyWith(phase: ActiveRecordingPhase.paused));
  }

  Future<void> resume() async {
    if (_state.phase != ActiveRecordingPhase.paused) {
      return;
    }
    await _recorder.resume();
    _setState(_state.copyWith(phase: ActiveRecordingPhase.recording));
    _startTicker();
  }

  Future<void> start() async {
    if (_state.isCaptureActive || _closed) {
      return;
    }
    _setState(const ActiveRecordingState(phase: ActiveRecordingPhase.starting));
    final permission = await _recorder.requestPermission();
    if (permission != RecorderPermission.granted) {
      _setState(
        const ActiveRecordingState(phase: ActiveRecordingPhase.permissionDenied),
      );
      return;
    }

    try {
      final pending = await _files.createPending(id: _idGenerator());
      final record = LocalRecording.inProgress(
        id: pending.id,
        title: _titleFor(_now()),
        relativePath: pending.relativePath,
        createdAt: _now(),
      );
      await _repository.save(record);
      _pending = pending;
      _activeRecording = record;
      await _background.start();
      _backgroundStarted = true;
      await _recorder.start(pending.temporaryPath);
      _setState(
        ActiveRecordingState(
          phase: ActiveRecordingPhase.recording,
          recording: record,
        ),
      );
      _startTicker();
    } catch (error) {
      await _failActive(error);
    }
  }

  Future<void> stop() => _finalize(LocalRecordingStatus.saved);

  Future<void> _finalize(
    LocalRecordingStatus status, {
    String? reason,
  }) {
    final current = _finalizing;
    if (current != null) {
      return current;
    }
    final work = _finalizeInternal(status, reason: reason);
    _finalizing = work;
    return work;
  }

  Future<void> _finalizeInternal(
    LocalRecordingStatus status, {
    String? reason,
  }) async {
    final record = _activeRecording;
    final pending = _pending;
    if (record == null || pending == null || !_state.isCaptureActive) {
      return;
    }
    _ticker?.cancel();
    _setState(_state.copyWith(phase: ActiveRecordingPhase.stopping));
    try {
      final captured = await _recorder.stop();
      final file = await _files.finalize(pending);
      final completed = record.completed(
        status: status,
        completedAt: _now(),
        duration: captured.duration,
        sizeBytes: file.sizeBytes,
        failureReason: reason,
      );
      await _repository.update(completed);
      _setState(const ActiveRecordingState.idle());
    } catch (error) {
      await _failActive(error);
    } finally {
      await _stopBackground();
      _pending = null;
      _activeRecording = null;
      _finalizing = null;
    }
  }

  Future<void> _failActive(Object error) async {
    final record = _activeRecording;
    if (record != null) {
      await _repository.update(record.failed(_errorMessage(error)));
    }
    await _stopBackground();
    _pending = null;
    _activeRecording = null;
    _setState(
      ActiveRecordingState(
        phase: ActiveRecordingPhase.error,
        errorMessage: _errorMessage(error),
      ),
    );
  }

  void _onAmplitude(double value) {
    if (_state.phase == ActiveRecordingPhase.recording) {
      _setState(_state.copyWith(amplitude: value));
    }
  }

  void _onSignal(RecorderSignal signal) {
    if (signal case RecorderInterrupted(:final reason)) {
      unawaited(_finalize(LocalRecordingStatus.interrupted, reason: reason));
    }
  }

  void _setState(ActiveRecordingState value) {
    if (_closed) {
      return;
    }
    _state = value;
    notifyListeners();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_state.phase != ActiveRecordingPhase.recording) {
        return;
      }
      final elapsed = _state.elapsed + const Duration(seconds: 1);
      _setState(_state.copyWith(elapsed: elapsed));
      unawaited(_background.updateElapsed(elapsed));
    });
  }

  Future<void> _stopBackground() async {
    if (!_backgroundStarted) {
      return;
    }
    _backgroundStarted = false;
    await _background.stop();
  }

  String _errorMessage(Object error) {
    return error is RecordingFileException ? error.message : '录音未能保存。';
  }

  String _titleFor(DateTime time) {
    String part(int value) => value.toString().padLeft(2, '0');
    return '录音 ${time.year}-${part(time.month)}-${part(time.day)} ${part(time.hour)}:${part(time.minute)}';
  }
}
