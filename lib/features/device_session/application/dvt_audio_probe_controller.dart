import 'dart:async';

import 'package:flutter/foundation.dart';

/// The parent session must complete FA18 Notify CCC setup before it writes a
/// full 0x02 configuration with `AudioStream=1` and resolves this callback.
typedef DvtAudioProbeStarter = Future<void> Function();

/// The parent session disables the stream with a full 0x02 configuration with
/// `AudioStream=0`. It owns recording state and only stops a recording that
/// the probe itself started.
typedef DvtAudioProbeStopper = Future<void> Function();

enum DvtAudioProbePhase {
  idle,
  starting,
  streaming,
  stopping,
  completed,
  failed,
}

/// Immutable DVT audio-validation metrics.
///
/// FA18/0x88 has no sequence number, application ACK, or retransmission
/// field. The counters intentionally describe only what the App received;
/// they do not attempt to infer packet loss.
class DvtAudioProbeState {
  const DvtAudioProbeState({
    this.phase = DvtAudioProbePhase.idle,
    this.frameCount = 0,
    this.byteCount = 0,
    this.elapsed = Duration.zero,
    this.failureMessage,
    this.mayRequireStop = false,
  });

  static const packetLossUnavailableMessage = '协议未提供序号字段，无法计算丢包率';

  final DvtAudioProbePhase phase;
  final int frameCount;
  final int byteCount;
  final Duration elapsed;
  final String? failureMessage;

  /// True after the session accepted a start request. It stays true following
  /// a notification error so an explicit stop can still clear device state.
  final bool mayRequireStop;

  bool get isBusy =>
      phase == DvtAudioProbePhase.starting ||
      phase == DvtAudioProbePhase.stopping;

  bool get isStreaming => phase == DvtAudioProbePhase.streaming;

  bool get canStart =>
      phase == DvtAudioProbePhase.idle ||
      phase == DvtAudioProbePhase.completed ||
      (phase == DvtAudioProbePhase.failed && !mayRequireStop);

  bool get canStop => mayRequireStop && phase != DvtAudioProbePhase.stopping;

  double get bytesPerSecond {
    final microseconds = elapsed.inMicroseconds;
    if (microseconds == 0) {
      return 0;
    }
    return byteCount * Duration.microsecondsPerSecond / microseconds;
  }
}

/// Presentation-facing companion for the DVT FA18 real-time audio probe.
///
/// [validatedAudioPayloads] must contain only successfully decoded `0x88`
/// Content bytes from the active authenticated connection. It deliberately
/// does not parse raw BLE packets or expose audio recording controls.
class DvtAudioProbeController extends ChangeNotifier {
  DvtAudioProbeController({
    required this.validatedAudioPayloads,
    required this.startDvtAudioProbe,
    required this.stopDvtAudioProbe,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Stream<Uint8List> validatedAudioPayloads;
  final DvtAudioProbeStarter startDvtAudioProbe;
  final DvtAudioProbeStopper stopDvtAudioProbe;
  final DateTime Function() _clock;

  DvtAudioProbeState _state = const DvtAudioProbeState();
  StreamSubscription<Uint8List>? _payloadSubscription;
  Timer? _elapsedTicker;
  DateTime? _startedAt;
  Future<void> _operation = Future<void>.value();
  var _probeStarted = false;
  var _disposed = false;
  Object? _startupError;

  DvtAudioProbeState get state => _state;

  /// Registers the payload listener before delegating to the session starter.
  /// The injected starter is responsible for CCC -> AudioStream=1 ordering.
  Future<void> start() => _enqueue(_start);

  /// Disables the probe stream through the parent session and retains the
  /// final counters as the completed validation result.
  Future<void> stop() => _enqueue(_stop);

  Future<void> _enqueue(Future<void> Function() action) {
    if (_disposed) {
      return Future<void>.value();
    }
    final next = _operation.then((_) async {
      if (!_disposed) {
        await action();
      }
    });
    _operation = next.then<void>((_) {}, onError: (error) {});
    return next;
  }

  Future<void> _start() async {
    if (!_state.canStart) {
      return;
    }
    await _cancelPayloadSubscription();
    _stopElapsedTicker();
    _startedAt = null;
    _probeStarted = false;
    _startupError = null;
    _setState(const DvtAudioProbeState(phase: DvtAudioProbePhase.starting));

    try {
      _payloadSubscription = validatedAudioPayloads.listen(
        _onPayload,
        onError: (Object error, StackTrace stackTrace) {
          _onPayloadStreamError(error);
        },
        onDone: _onPayloadStreamDone,
      );
      await startDvtAudioProbe();
      _probeStarted = true;
      if (_disposed) {
        return;
      }
      if (_startupError case final error?) {
        await stopDvtAudioProbe();
        _probeStarted = false;
        throw error;
      }
      _startedAt = _clock();
      _setState(
        DvtAudioProbeState(
          phase: DvtAudioProbePhase.streaming,
          frameCount: _state.frameCount,
          byteCount: _state.byteCount,
          mayRequireStop: true,
        ),
      );
      _elapsedTicker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _publishElapsed(),
      );
    } catch (error) {
      await _cancelPayloadSubscription();
      if (_disposed) {
        return;
      }
      _setState(
        DvtAudioProbeState(
          phase: DvtAudioProbePhase.failed,
          frameCount: _state.frameCount,
          byteCount: _state.byteCount,
          elapsed: _currentElapsed(),
          failureMessage: _failureMessage(error),
          // A successful start followed by failed cleanup still owns the
          // device stream. Keep Stop available instead of allowing a second
          // start over an unresolved first probe.
          mayRequireStop: _probeStarted,
        ),
      );
    }
  }

  Future<void> _stop() async {
    if (!_probeStarted) {
      await _cancelPayloadSubscription();
      _stopElapsedTicker();
      return;
    }
    final elapsed = _currentElapsed();
    _setState(
      DvtAudioProbeState(
        phase: DvtAudioProbePhase.stopping,
        frameCount: _state.frameCount,
        byteCount: _state.byteCount,
        elapsed: elapsed,
        mayRequireStop: true,
      ),
    );
    try {
      await stopDvtAudioProbe();
      _probeStarted = false;
      await _cancelPayloadSubscription();
      _stopElapsedTicker();
      if (_disposed) {
        return;
      }
      _setState(
        DvtAudioProbeState(
          phase: DvtAudioProbePhase.completed,
          frameCount: _state.frameCount,
          byteCount: _state.byteCount,
          elapsed: elapsed,
        ),
      );
    } catch (error) {
      await _cancelPayloadSubscription();
      _stopElapsedTicker();
      if (_disposed) {
        return;
      }
      _setState(
        DvtAudioProbeState(
          phase: DvtAudioProbePhase.failed,
          frameCount: _state.frameCount,
          byteCount: _state.byteCount,
          elapsed: elapsed,
          failureMessage: _failureMessage(error),
          mayRequireStop: true,
        ),
      );
    }
  }

  void _onPayload(Uint8List payload) {
    if (_disposed ||
        (!_state.isStreaming && _state.phase != DvtAudioProbePhase.starting)) {
      return;
    }
    // Count every validated frame; rebuild UI only on the one-second ticker.
    _state = DvtAudioProbeState(
      phase: _state.phase,
      frameCount: _state.frameCount + 1,
      byteCount: _state.byteCount + payload.length,
      elapsed: _currentElapsed(),
      mayRequireStop: true,
    );
  }

  void _onPayloadStreamError(Object error) {
    if (!_disposed && _state.phase == DvtAudioProbePhase.starting) {
      _startupError = error;
      return;
    }
    if (_disposed || !_probeStarted) {
      return;
    }
    _stopElapsedTicker();
    _setState(
      DvtAudioProbeState(
        phase: DvtAudioProbePhase.failed,
        frameCount: _state.frameCount,
        byteCount: _state.byteCount,
        elapsed: _currentElapsed(),
        failureMessage: _failureMessage(error),
        mayRequireStop: true,
      ),
    );
  }

  void _onPayloadStreamDone() {
    if (!_disposed && _state.phase == DvtAudioProbePhase.starting) {
      _startupError = StateError('实时音频通知通道已关闭。');
      return;
    }
    if (_disposed || !_probeStarted) {
      return;
    }
    _stopElapsedTicker();
    _setState(
      DvtAudioProbeState(
        phase: DvtAudioProbePhase.failed,
        frameCount: _state.frameCount,
        byteCount: _state.byteCount,
        elapsed: _currentElapsed(),
        failureMessage: '实时音频通知通道已关闭。',
        mayRequireStop: true,
      ),
    );
  }

  void _publishElapsed() {
    if (_disposed || !_state.isStreaming) {
      return;
    }
    _setState(
      DvtAudioProbeState(
        phase: DvtAudioProbePhase.streaming,
        frameCount: _state.frameCount,
        byteCount: _state.byteCount,
        elapsed: _currentElapsed(),
        mayRequireStop: true,
      ),
    );
  }

  Duration _currentElapsed() {
    final startedAt = _startedAt;
    if (startedAt == null) {
      return _state.elapsed;
    }
    final elapsed = _clock().difference(startedAt);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  Future<void> _cancelPayloadSubscription() async {
    final subscription = _payloadSubscription;
    _payloadSubscription = null;
    await subscription?.cancel();
  }

  void _stopElapsedTicker() {
    _elapsedTicker?.cancel();
    _elapsedTicker = null;
  }

  void _setState(DvtAudioProbeState next) {
    _state = next;
    if (!_disposed) {
      notifyListeners();
    }
  }

  String _failureMessage(Object error) {
    final message = error.toString().trim();
    return message.isEmpty ? '实时音频验证未完成。' : message;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stopElapsedTicker();
    unawaited(_cancelPayloadSubscription());
    // Cover route replacement/removal as well as normal back navigation.
    // Queue after any start so CCC/config cannot finish after this cleanup.
    unawaited(
      _operation.then((_) async {
        if (!_probeStarted) return;
        try {
          await stopDvtAudioProbe();
        } catch (_) {
          /* Session logs and disconnects. */
        }
      }),
    );
    super.dispose();
  }
}
