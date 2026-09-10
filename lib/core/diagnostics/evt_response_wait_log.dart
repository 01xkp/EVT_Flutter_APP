import 'dart:async';

import 'safe_app_logger.dart';

/// Observes a response wait without changing its timeout or retry policy.
class EvtResponseWaitLog {
  EvtResponseWaitLog({
    required this._logger,
    required Map<String, Object?> fields,
    required this._timeout,
  }) : _fields = Map.of(fields) {
    _emit('evt_response_wait_started', '【回包监听】【开始】响应等待已登记，先监听再写入设备');
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _emit(
        'evt_response_waiting',
        _writeCompleted
            ? '【回包监听】【等待中】尚未收到完整匹配响应，继续监听，不额外发送命令'
            : '【回包监听】【等待中】仍在等待系统写入完成，业务回包超时尚未开始计时',
      );
    });
  }

  static int _nextWaitId = 0;
  final int id = ++_nextWaitId;
  final SafeAppLogger _logger;
  final Map<String, Object?> _fields;
  final Duration _timeout;
  final Stopwatch _elapsed = Stopwatch()..start();
  final Stopwatch _idle = Stopwatch();
  Timer? _timer;
  bool _writeCompleted = false;
  bool _finished = false;
  int _responseCount = 0;

  void writeCompleted() {
    if (_finished) return;
    _writeCompleted = true;
    _idle.start();
    _emit('evt_response_wait_armed', '【回包监听】【计时开始】系统写入完成，开始计算业务响应超时');
  }

  void received({required bool terminal}) {
    if (_finished) return;
    _responseCount++;
    _idle.reset();
    if (terminal) {
      finish('success', reason: '【回包监听】【收到回包】已收到完整匹配响应，结束本次等待');
    }
  }

  void finish(String result, {required String reason}) {
    if (_finished) return;
    _finished = true;
    _timer?.cancel();
    _elapsed.stop();
    _idle.stop();
    _emit('evt_response_wait_finished', reason, result: result);
  }

  void _emit(String event, String reason, {String result = 'pending'}) {
    final remaining = _timeout.inMilliseconds - _idle.elapsedMilliseconds;
    try {
      _logger.info(
        event,
        stage: 'response',
        result: result,
        elapsed: _elapsed.elapsed,
        fields: {
          ..._fields,
          'wait_id': id,
          'reason': reason,
          'state': _finished
              ? result
              : (_writeCompleted ? 'waiting_response' : 'write_pending'),
          'elapsed_ms': _elapsed.elapsedMilliseconds,
          'timeout_ms': _timeout.inMilliseconds,
          'response_count': _responseCount,
          if (_writeCompleted) ...{
            'idle_ms': _idle.elapsedMilliseconds,
            'remaining_ms': remaining > 0 ? remaining : 0,
          },
        },
      );
    } on Object {
      // Diagnostic failures must never change GATT command execution.
    }
  }
}
