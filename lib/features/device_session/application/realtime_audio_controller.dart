import 'dart:async';
import 'dart:typed_data';

import 'package:aipin/core/protocol/evt_protocol_codec.dart';
import 'package:aipin/features/device_session/domain/realtime_audio_capture.dart';
import 'package:aipin/features/device_session/domain/realtime_audio_gateway.dart';
import 'package:flutter/foundation.dart';

enum RealtimeAudioPhase {
  idle,
  starting,
  capturing,
  stopping,
  completed,
  failed,
}

class RealtimeAudioState {
  const RealtimeAudioState({
    required this.phase,
    this.receivedBytes = 0,
    this.error,
  });

  const RealtimeAudioState.idle() : this(phase: RealtimeAudioPhase.idle);

  final RealtimeAudioPhase phase;
  final int receivedBytes;
  final String? error;

  bool get isActive =>
      phase == RealtimeAudioPhase.starting ||
      phase == RealtimeAudioPhase.capturing ||
      phase == RealtimeAudioPhase.stopping;

  bool get canExportRaw => receivedBytes > 0;

  RealtimeAudioState copyWith({
    RealtimeAudioPhase? phase,
    int? receivedBytes,
    String? error,
    bool clearError = false,
  }) => RealtimeAudioState(
    phase: phase ?? this.phase,
    receivedBytes: receivedBytes ?? this.receivedBytes,
    error: clearError ? null : error ?? this.error,
  );
}

class RealtimeAudioController implements ValueListenable<RealtimeAudioState> {
  RealtimeAudioController({
    required this.gateway,
    required this.codec,
    this.maximumCaptureBytes = 64 * 1024 * 1024,
  }) : _state = ValueNotifier(const RealtimeAudioState.idle()) {
    if (maximumCaptureBytes <= 0) {
      throw ArgumentError.value(
        maximumCaptureBytes,
        'maximumCaptureBytes',
        'must be positive',
      );
    }
  }

  final RealtimeAudioGateway gateway;
  final EvtProtocolCodec codec;
  final int maximumCaptureBytes;
  final ValueNotifier<RealtimeAudioState> _state;
  final BytesBuilder _capture = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _subscription;
  Future<void>? _cleanup;
  Future<void>? _disposeFuture;
  DateTime? _capturedAt;
  bool _streamRequested = false;
  bool _recordingRequested = false;

  RealtimeAudioState get state => _state.value;

  @override
  RealtimeAudioState get value => state;

  @override
  void addListener(VoidCallback listener) => _state.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _state.removeListener(listener);

  Future<void> start() async {
    if (state.isActive) {
      throw StateError('实时音频采集正在执行。');
    }
    _capture.clear();
    _capturedAt = DateTime.now();
    _streamRequested = false;
    _recordingRequested = false;
    _setState(
      const RealtimeAudioState(
        phase: RealtimeAudioPhase.starting,
        receivedBytes: 0,
      ),
    );
    try {
      _subscription = gateway.subscribeRealtimeAudio().listen(
        _onFrame,
        onError: _onStreamError,
      );
      _streamRequested = true;
      await gateway.setAudioStreamEnabled(true);
      _recordingRequested = true;
      await gateway.setRealtimeRecording(true);
      _setState(const RealtimeAudioState(phase: RealtimeAudioPhase.capturing));
    } catch (error) {
      await _disableDeviceStream();
      await _cancelSubscription();
      _setFailure('无法启动实时音频：$error');
      rethrow;
    }
  }

  Future<void> stop() async {
    if (!state.isActive) {
      return;
    }
    _setState(state.copyWith(phase: RealtimeAudioPhase.stopping));
    try {
      await _disableDeviceStream();
      await _cancelSubscription();
      _setState(
        state.copyWith(phase: RealtimeAudioPhase.completed, clearError: true),
      );
    } catch (error) {
      await _cancelSubscription();
      _setFailure('无法停止实时音频：$error');
      rethrow;
    }
  }

  Uint8List captureBytes() => Uint8List.fromList(_capture.toBytes());

  RealtimeAudioCapture? capture() {
    final capturedAt = _capturedAt;
    if (capturedAt == null || _capture.length == 0) {
      return null;
    }
    return RealtimeAudioCapture(bytes: captureBytes(), capturedAt: capturedAt);
  }

  void _onFrame(Uint8List bytes) {
    if (state.phase != RealtimeAudioPhase.capturing) {
      return;
    }
    final result = codec.decode(bytes);
    if (!result.isSuccess || result.value!.command != 0x08) {
      return;
    }
    final payload = result.value!.content;
    if (_capture.length + payload.length > maximumCaptureBytes) {
      unawaited(_stopForCaptureLimit());
      return;
    }
    _capture.add(payload);
    _setState(state.copyWith(receivedBytes: _capture.length));
  }

  void _onStreamError(Object error, StackTrace stackTrace) {
    unawaited(_stopForFailure('实时音频通知异常：$error'));
  }

  Future<void> _stopForCaptureLimit() =>
      _stopForFailure('实时音频数据超过本机保存上限，请停止后导出。');

  Future<void> _stopForFailure(String error) {
    final pending = _cleanup;
    if (pending != null) {
      return pending;
    }
    _setFailure(error);
    final work = _finishFailedCapture();
    _cleanup = work.whenComplete(() => _cleanup = null);
    return _cleanup!;
  }

  Future<void> _finishFailedCapture() async {
    try {
      await _disableDeviceStream();
    } catch (_) {
      // The first failure stays user-visible; the session can still be retried.
    }
    await _cancelSubscription();
  }

  Future<void> _disableDeviceStream() async {
    Object? failure;
    if (_streamRequested) {
      try {
        await gateway.setAudioStreamEnabled(false);
      } catch (error) {
        failure = error;
      } finally {
        _streamRequested = false;
      }
    }
    if (_recordingRequested) {
      try {
        await gateway.setRealtimeRecording(false);
      } catch (error) {
        failure ??= error;
      } finally {
        _recordingRequested = false;
      }
    }
    if (failure != null) {
      throw failure;
    }
  }

  Future<void> _cancelSubscription() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }

  void _setFailure(String error) {
    _setState(state.copyWith(phase: RealtimeAudioPhase.failed, error: error));
  }

  void _setState(RealtimeAudioState next) {
    if (_disposeFuture == null) {
      _state.value = next;
    }
  }

  Future<void> dispose() {
    final pending = _disposeFuture;
    if (pending != null) {
      return pending;
    }
    final work = _dispose();
    _disposeFuture = work;
    return work;
  }

  Future<void> _dispose() async {
    if (state.isActive) {
      try {
        await stop();
      } catch (_) {
        // Dispose still releases the local subscription after a transport error.
      }
    } else {
      await _cancelSubscription();
    }
    _state.dispose();
  }
}
