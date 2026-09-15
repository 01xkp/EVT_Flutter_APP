import 'dart:async';
import 'dart:typed_data';

import 'package:aipin/core/ble/ble_transport.dart';
import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/diagnostics/evt_packet_log_summary.dart';
import 'package:aipin/core/diagnostics/evt_response_wait_log.dart';
import 'package:aipin/core/diagnostics/safe_app_logger.dart';
import 'package:aipin/core/protocol/evt_frame.dart';
import 'package:aipin/core/protocol/evt_frame_assembler.dart';
import 'package:aipin/core/protocol/evt_protocol_contract.dart';
import 'package:aipin/core/protocol/evt_protocol_codec.dart';

typedef EvtResponseMatcher = bool Function(EvtFrame frame);
typedef EvtStreamTerminalMatcher = bool Function(EvtFrame frame);

/// Synchronously admits a command immediately before it is written to BLE.
///
/// Throwing from this callback aborts the queued command without writing any
/// bytes. It deliberately stays synchronous so an authorization decision
/// cannot become stale in an await gap between the check and the write.
typedef EvtCommandWriteAdmission = void Function(EvtCommandRequest request);

class EvtCommandRequest {
  const EvtCommandRequest({
    required this.command,
    required this.writeCharacteristic,
    this.content = const [],
    this.allowUnauthenticatedUnbindRecovery = false,
    this.expectedResponseCommand,
    this.expectedSubCommand,
    this.expectedSequence,
    this.sequenceOffset,
    this.responseMatcher,
    this.timeout = const Duration(seconds: 2),
    this.maxRetries = 1,
  });

  final int command;
  final List<int> content;
  final BleCharacteristic writeCharacteristic;

  /// Internal admission hint for the V1.6 UNBIND recovery exception.
  ///
  /// This flag never changes the wire frame.  It is consumed by the session
  /// permission gate immediately before the write and is only set by the
  /// explicit Action=2 recovery path.  No other command may use it.
  final bool allowUnauthenticatedUnbindRecovery;
  final int? expectedResponseCommand;
  final int? expectedSubCommand;
  final int? expectedSequence;
  final int? sequenceOffset;
  final EvtResponseMatcher? responseMatcher;
  final Duration timeout;
  final int maxRetries;
}

class EvtCommandResponse {
  const EvtCommandResponse({required this.frame, required this.attempts});

  final EvtFrame frame;
  final int attempts;
}

class EvtCommandTimeoutException implements Exception {
  const EvtCommandTimeoutException(this.command, this.attempts);

  final int command;
  final int attempts;

  @override
  String toString() =>
      'EvtCommandTimeoutException(command=0x${command.toRadixString(16)}, attempts=$attempts)';
}

class EvtCommandClient {
  EvtCommandClient({
    required this._transport,
    required this._codec,
    required Stream<Uint8List> responses,
    this._beforeWrite,
    SafeAppLogger? logger,
  }) : _logger = logger ?? const DebugSafeAppLogger(scope: 'CMD') {
    _responseSubscription = responses.listen(
      _onBytes,
      onError: _onTransportError,
    );
    _logInfo(
      'evt_command_client_opened',
      stage: 'initialization',
      result: 'success',
      fields: const {'state': 'listening'},
    );
  }

  final BleTransport _transport;
  final EvtProtocolCodec _codec;
  final EvtCommandWriteAdmission? _beforeWrite;
  final SafeAppLogger _logger;
  final StreamController<EvtFrame> _events =
      StreamController<EvtFrame>.broadcast();
  final EvtFrameAssembler _frameAssembler = EvtFrameAssembler();
  StreamSubscription<Uint8List>? _responseSubscription;
  Future<void> _queue = Future<void>.value();
  _PendingRequest? _pending;
  Object? _transportError;
  StackTrace? _transportErrorStackTrace;
  var _closed = false;

  Stream<EvtFrame> get events => _events.stream;

  Future<EvtCommandResponse> execute(EvtCommandRequest request) {
    if (_closed) {
      _logWarning(
        'evt_command_rejected',
        stage: 'request',
        result: 'failed',
        fields: _requestFields(request, reason: 'client_closed'),
      );
      return Future<EvtCommandResponse>.error(StateError('命令客户端已关闭。'));
    }
    final transportError = _transportError;
    if (transportError != null) {
      _logWarning(
        'evt_command_rejected',
        stage: 'request',
        result: 'failed',
        fields: _requestFields(
          request,
          reason: 'response_stream_failed',
          errorType: transportError.runtimeType.toString(),
        ),
      );
      return Future<EvtCommandResponse>.error(
        transportError,
        _transportErrorStackTrace,
      );
    }
    final unavailable = _unavailableCommandError(request);
    if (unavailable != null) {
      return Future<EvtCommandResponse>.error(
        unavailable.error,
        unavailable.stackTrace,
      );
    }
    _logInfo(
      'evt_command_queued',
      stage: 'request',
      result: 'pending',
      fields: _requestFields(request),
    );
    final result = _queue.then((_) => _run(request));
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  /// Sends one request and keeps the command slot exclusively assigned until
  /// the protocol's terminal response frame arrives.
  Stream<EvtFrame> executeStreaming(
    EvtCommandRequest request, {
    required EvtStreamTerminalMatcher isTerminal,
    Duration idleTimeout = const Duration(seconds: 15),
  }) {
    if (_closed) {
      _logWarning(
        'evt_stream_command_rejected',
        stage: 'request',
        result: 'failed',
        fields: _requestFields(request, reason: 'client_closed'),
      );
      return Stream<EvtFrame>.error(StateError('命令客户端已关闭。'));
    }
    final transportError = _transportError;
    if (transportError != null) {
      _logWarning(
        'evt_stream_command_rejected',
        stage: 'request',
        result: 'failed',
        fields: _requestFields(
          request,
          timeout: idleTimeout,
          reason: 'response_stream_failed',
          errorType: transportError.runtimeType.toString(),
        ),
      );
      return Stream<EvtFrame>.error(transportError, _transportErrorStackTrace);
    }
    final unavailable = _unavailableCommandError(
      request,
      timeout: idleTimeout,
      streaming: true,
    );
    if (unavailable != null) {
      return Stream<EvtFrame>.error(unavailable.error, unavailable.stackTrace);
    }
    late final StreamController<EvtFrame> controller;
    _PendingStreamingCommand? active;
    controller = StreamController<EvtFrame>(
      onListen: () {
        _logInfo(
          'evt_stream_command_queued',
          stage: 'request',
          result: 'pending',
          fields: _requestFields(
            request,
            timeout: idleTimeout,
            reason: 'streaming',
          ),
        );
        final scheduled = _queue.then((_) async {
          _PendingStreamingCommand? pending;
          final stopwatch = Stopwatch();
          try {
            _ensureUsable();
            _admitWrite(request);
            stopwatch.start();
            _logInfo(
              'evt_stream_command_admitted',
              stage: 'write',
              result: 'accepted',
              fields: _requestFields(
                request,
                timeout: idleTimeout,
                reason: 'streaming',
              ),
            );
            pending = _PendingStreamingCommand(
              request: request,
              controller: controller,
              isTerminal: isTerminal,
              idleTimeout: idleTimeout,
              waitLog: EvtResponseWaitLog(
                logger: _logger,
                fields: _requestFields(request, attempt: 1),
                timeout: idleTimeout,
              ),
            );
            // Observe early errors while awaiting the write. Awaiting done
            // below still propagates the original failure to the caller.
            pending.done.ignore();
            active = pending;
            _pending = pending;
            final bytes = _codec.encodeRequest(
              request.command,
              request.content,
            );
            final packet = EvtPacketLogSummary.fromWireBytes(bytes);
            _logInfo(
              'evt_stream_command_transmit_started',
              stage: 'write',
              result: 'pending',
              fields: {
                ...packet.fields,
                ..._requestFields(request, timeout: idleTimeout),
                'wait_id': pending.waitLog.id,
                'reason': 'streaming',
              },
            );
            await _transport.write(request.writeCharacteristic, bytes);
            _logInfo(
              'evt_stream_command_transmit_completed',
              stage: 'write',
              result: 'success',
              elapsed: stopwatch.elapsed,
              fields: {
                ...packet.fields,
                ..._requestFields(request, timeout: idleTimeout),
                'wait_id': pending.waitLog.id,
                'reason': 'streaming',
              },
            );
            // Keep replies that precede the write callback, but do not count
            // native write latency against the initial response idle timeout.
            pending.start();
            pending.waitLog.writeCompleted();
            await pending.done;
            _logInfo(
              'evt_stream_command_completed',
              stage: 'response',
              result: 'completed',
              elapsed: stopwatch.elapsed,
              fields: _requestFields(
                request,
                timeout: idleTimeout,
                reason: 'streaming_terminal_frame',
              ),
            );
          } on EvtCommandTimeoutException catch (error, stackTrace) {
            _logWarning(
              'evt_stream_command_timeout',
              stage: 'response',
              result: 'failed',
              elapsed: stopwatch.elapsed,
              fields: _requestFields(
                request,
                timeout: idleTimeout,
                reason: 'idle_timeout',
                attempt: error.attempts,
              ),
            );
            if (!controller.isClosed) {
              controller.addError(error, stackTrace);
            }
          } catch (error, stackTrace) {
            _logError(
              'evt_stream_command_error',
              stage: 'response',
              result: 'failed',
              elapsed: stopwatch.elapsed,
              fields: _requestFields(
                request,
                timeout: idleTimeout,
                reason: 'stream_failed',
                errorType: error.runtimeType.toString(),
              ),
            );
            if (!controller.isClosed) {
              controller.addError(error, stackTrace);
            }
          } finally {
            if (pending != null && !pending.waitLog.isFinished) {
              pending.waitLog.finish(
                'cancelled',
                reason: '【回包监听】【结束】连续命令已退出，停止剩余等待日志',
              );
            }
            if (pending != null && identical(_pending, pending)) {
              _pending = null;
            }
            pending?.dispose();
            if (!controller.isClosed) {
              await controller.close();
            }
          }
        });
        _queue = scheduled.then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        );
      },
      onCancel: () {
        final pending = active;
        if (pending != null && identical(_pending, pending)) {
          _logInfo(
            'evt_stream_command_cancelled',
            stage: 'response',
            result: 'cancelled',
            fields: _requestFields(request, reason: 'stream_cancelled'),
          );
          pending.waitLog.finish('cancelled', reason: '【回包监听】【取消】用户已取消连续命令');
          pending.completeError(StateError('连续命令已取消。'));
        }
      },
    );
    return controller.stream;
  }

  Future<EvtCommandResponse> _run(EvtCommandRequest request) async {
    try {
      _ensureUsable();
    } catch (error, stackTrace) {
      _logError(
        'evt_command_unavailable',
        stage: 'request',
        result: 'failed',
        fields: _requestFields(
          request,
          reason: _closed ? 'client_closed' : 'response_stream_failed',
          errorType: error.runtimeType.toString(),
        ),
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
    late final Uint8List bytes;
    try {
      bytes = _codec.encodeRequest(request.command, request.content);
    } catch (error, stackTrace) {
      _logError(
        'evt_command_encode_failed',
        stage: 'request',
        result: 'failed',
        fields: _requestFields(
          request,
          reason: 'encode_failed',
          errorType: error.runtimeType.toString(),
        ),
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
    final packet = EvtPacketLogSummary.fromWireBytes(bytes);
    final expectedCommand =
        request.expectedResponseCommand ?? ((request.command | 0x80) & 0xFF);
    final attempts = request.maxRetries < 0 ? 0 : request.maxRetries;
    Object? lastError;
    for (var retry = 0; retry <= attempts; retry += 1) {
      final attempt = retry + 1;
      final stopwatch = Stopwatch();
      try {
        _admitWrite(request);
      } catch (error, stackTrace) {
        _logError(
          'evt_command_admission_failed',
          stage: 'write',
          result: 'failed',
          fields: _requestFields(
            request,
            attempt: attempt,
            reason: 'write_admission_rejected',
            errorType: error.runtimeType.toString(),
          ),
        );
        Error.throwWithStackTrace(error, stackTrace);
      }
      stopwatch.start();
      _logInfo(
        'evt_command_admitted',
        stage: 'write',
        result: 'accepted',
        fields: _requestFields(request, attempt: attempt),
      );
      final pending = _PendingCommand(
        command: expectedCommand,
        subCommand: request.expectedSubCommand,
        sequence: request.expectedSequence,
        sequenceOffset: request.sequenceOffset,
        responseMatcher: request.responseMatcher,
        waitLog: EvtResponseWaitLog(
          logger: _logger,
          fields: _requestFields(request, attempt: attempt),
          timeout: request.timeout,
        ),
      );
      // A receive failure can precede the native write callback. Attach an
      // error observer now; the await below still receives the same failure.
      pending.future.ignore();
      _pending = pending;
      try {
        _logInfo(
          'evt_command_transmit_started',
          stage: 'write',
          result: 'pending',
          fields: {
            ...packet.fields,
            ..._requestFields(request, attempt: attempt),
            'wait_id': pending.waitLog.id,
          },
        );
        await _transport.write(request.writeCharacteristic, bytes);
        _logInfo(
          'evt_command_transmit_completed',
          stage: 'write',
          result: 'success',
          elapsed: stopwatch.elapsed,
          fields: {
            ...packet.fields,
            ..._requestFields(request, attempt: attempt),
            'wait_id': pending.waitLog.id,
          },
        );
        pending.waitLog.writeCompleted();
        final frame = await pending.future.timeout(request.timeout);
        _logInfo(
          'evt_command_completed',
          stage: 'response',
          result: 'completed',
          elapsed: stopwatch.elapsed,
          fields: {
            ..._requestFields(request, attempt: attempt),
            'actual_command': _commandHex(frame.command),
          },
        );
        return EvtCommandResponse(frame: frame, attempts: attempt);
      } on TimeoutException {
        lastError = EvtCommandTimeoutException(request.command, attempt);
        pending.waitLog.finish('failed', reason: '【回包监听】【超时】未在规定时间内收到匹配响应');
        _logWarning(
          'evt_command_timeout',
          stage: 'response',
          result: retry < attempts && _transportError == null
              ? 'retrying'
              : 'failed',
          elapsed: stopwatch.elapsed,
          fields: _requestFields(
            request,
            attempt: attempt,
            reason: 'response_timeout',
          ),
        );
      } catch (error) {
        lastError = error;
        pending.waitLog.finish('failed', reason: '【回包监听】【中断】写入或命令处理异常，停止等待');
        _logError(
          'evt_command_error',
          stage: 'response',
          result: retry < attempts && _transportError == null
              ? 'retrying'
              : 'failed',
          elapsed: stopwatch.elapsed,
          fields: _requestFields(
            request,
            attempt: attempt,
            reason: 'command_failed',
            errorType: error.runtimeType.toString(),
          ),
        );
      } finally {
        if (!pending.waitLog.isFinished) {
          pending.waitLog.finish(
            'cancelled',
            reason: '【回包监听】【结束】命令已退出，停止剩余等待日志',
          );
        }
        if (identical(_pending, pending)) {
          _pending = null;
        }
      }
      if (_transportError != null) {
        throw _transportError!;
      }
    }
    throw lastError ??
        EvtCommandTimeoutException(request.command, attempts + 1);
  }

  void _admitWrite(EvtCommandRequest request) {
    _ensureUsable();
    _beforeWrite?.call(request);
    _ensureUsable();
  }

  _CommandRejection? _unavailableCommandError(
    EvtCommandRequest request, {
    Duration? timeout,
    bool streaming = false,
  }) {
    try {
      EvtProtocolContract.requireBusinessCommand(request.command);
      // 0x11 is part of the EVT command vocabulary, but V1.6 exposes it only
      // as a native GATT Read.  Keep this guard in the lowest framed-write
      // layer as well as SessionController so an independently constructed
      // command client cannot accidentally put a read-only operation on a
      // characteristic write queue.
      if (EvtProtocolContract.writeEndpointForCommand(request.command) ==
          null) {
        throw EvtProtocolUnavailableException(
          'EVT 命令 0x${request.command.toRadixString(16).padLeft(2, '0').toUpperCase()} '
          '仅支持 GATT Read，不允许通过业务写入发送。',
        );
      }
      // Keep fixed V1.6 payload validation at the shared client entrance.
      // SessionController also validates its own requests, but the command
      // client is independently constructible in integration code and tests.
      // A direct caller must not be able to put an invalid frame on GATT.
      EvtProtocolContract.validateWritePayload(
        request.command,
        request.content,
      );
      return null;
    } catch (error, stackTrace) {
      _logWarning(
        streaming ? 'evt_stream_command_rejected' : 'evt_command_rejected',
        stage: 'request',
        result: 'failed',
        fields: _requestFields(
          request,
          timeout: timeout,
          reason: error is EvtProtocolUnavailableException
              ? 'command_not_enabled_for_evt'
              : 'request_payload_invalid',
          errorType: error.runtimeType.toString(),
        ),
      );
      return _CommandRejection(error, stackTrace);
    }
  }

  void _onBytes(Uint8List bytes) {
    if (_closed) {
      return;
    }
    final assembled = _frameAssembler.add(bytes);
    _logInfo(
      'evt_command_response_chunk_received',
      stage: 'response',
      result: 'pending',
      fields: {
        'bytes': bytes.length,
        'count': assembled.frames.length,
        'length': assembled.bufferedByteCount,
        'reason': 'ble_value_assembled',
      },
    );
    for (final rejected in assembled.rejectedFrames) {
      final packet = EvtPacketLogSummary.fromWireBytes(rejected);
      _logWarning(
        'evt_command_response_decode_failed',
        stage: 'response',
        result: 'failed',
        fields: {
          ...packet.fields,
          'event_kind': 'decode_failed',
          'failure_kind': 'protocol',
          'reason': 'frame_assembly_rejected',
        },
      );
    }
    for (final frameBytes in assembled.frames) {
      _onFrameBytes(frameBytes);
    }
  }

  void _onFrameBytes(Uint8List bytes) {
    final packet = EvtPacketLogSummary.fromWireBytes(bytes);
    final result = _codec.decode(bytes);
    if (!result.isSuccess) {
      _logWarning(
        'evt_command_response_decode_failed',
        stage: 'response',
        result: 'failed',
        fields: {
          ...packet.fields,
          'event_kind': 'decode_failed',
          'failure_kind': result.failure?.kind.name ?? 'protocol',
          'reason': 'decode_failed',
        },
      );
      return;
    }
    final frame = result.value!;
    final pending = _pending;
    final fields = <String, Object?>{
      ...packet.fields,
      'actual_command': _commandHex(frame.command),
      ..._pendingExpectedCommandField(pending),
    };
    _logInfo(
      'evt_command_frame_decoded',
      stage: 'response',
      result: 'success',
      fields: {...fields, 'event_kind': 'frame_decoded'},
    );
    _logInfo(
      'evt_command_response_received',
      stage: 'response',
      result: 'accepted',
      fields: {...fields, 'event_kind': 'response_received'},
    );
    bool matches = false;
    if (pending != null) {
      try {
        matches = pending.matches(frame);
      } catch (error, stackTrace) {
        _logError(
          'evt_command_response_match_failed',
          stage: 'response',
          result: 'failed',
          fields: {
            ...fields,
            'reason': 'response_matcher_failed',
            'error_type': error.runtimeType.toString(),
          },
        );
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
    if (matches) {
      _logInfo(
        'evt_command_response_matched',
        stage: 'response',
        result: 'success',
        fields: {...fields, 'event_kind': 'acknowledged'},
      );
      pending!.accept(frame);
      pending.waitLog.received(terminal: pending.isCompleted);
      return;
    }
    _logInfo(
      'evt_command_response_unmatched',
      stage: 'response',
      result: 'pending',
      fields: {
        ...fields,
        'event_kind': pending == null ? 'unsolicited' : 'unmatched_response',
        'reason': pending == null
            ? 'no_pending_command'
            : 'response_not_expected',
      },
    );
    if (!_events.isClosed) {
      _events.add(frame);
    }
  }

  void _onTransportError(Object error, StackTrace stackTrace) {
    if (_closed || _transportError != null) {
      return;
    }
    _transportError = error;
    _transportErrorStackTrace = stackTrace;
    _frameAssembler.reset();
    final pending = _pending;
    _logError(
      'evt_command_transport_error',
      stage: 'response',
      result: 'failed',
      fields: {
        ..._pendingExpectedCommandField(pending),
        'reason': 'response_stream_error',
        'error_type': error.runtimeType.toString(),
      },
    );
    _pending?.completeError(error, stackTrace);
  }

  void _ensureUsable() {
    if (_closed) {
      throw StateError('命令客户端已关闭。');
    }
    final transportError = _transportError;
    if (transportError != null) {
      final stackTrace = _transportErrorStackTrace;
      if (stackTrace == null) {
        throw transportError;
      }
      Error.throwWithStackTrace(transportError, stackTrace);
    }
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _frameAssembler.reset();
    _pending?.waitLog.finish('cancelled', reason: '【回包监听】【取消】当前连接或命令客户端已关闭');
    _logInfo(
      'evt_command_client_closing',
      stage: 'idle',
      result: 'pending',
      fields: const {'state': 'closing'},
    );
    _pending?.completeError(StateError('命令客户端已关闭。'));
    await _responseSubscription?.cancel();
    await _events.close();
    _logInfo(
      'evt_command_client_closed',
      stage: 'idle',
      result: 'completed',
      fields: const {'state': 'closed'},
    );
  }

  Map<String, Object?> _requestFields(
    EvtCommandRequest request, {
    Duration? timeout,
    String? reason,
    int? attempt,
    String? errorType,
  }) {
    final expectedCommand =
        request.expectedResponseCommand ?? ((request.command | 0x80) & 0xFF);
    return <String, Object?>{
      'command': _commandHex(request.command),
      'content_length': request.content.length,
      'expected_command': _commandHex(expectedCommand),
      'max_retries': request.maxRetries < 0 ? 0 : request.maxRetries,
      'timeout_ms': (timeout ?? request.timeout).inMilliseconds,
      if (request.allowUnauthenticatedUnbindRecovery) 'unbind_recovery': true,
      'characteristic': EvtPacketLogSummary.characteristicReference(
        request.writeCharacteristic.characteristicUuid,
      ),
      ..._optionalField(
        'sub_command',
        request.expectedSubCommand == null
            ? null
            : _commandHex(request.expectedSubCommand!),
      ),
      ..._optionalField('attempt', attempt),
      ..._optionalField('reason', reason),
      ..._optionalField('error_type', errorType),
    };
  }

  static String _commandHex(int command) {
    if (command < 0 || command > 0xFF) {
      return 'out_of_range';
    }
    return '0x${command.toRadixString(16).padLeft(2, '0').toUpperCase()}';
  }

  Map<String, Object?> _pendingExpectedCommandField(_PendingRequest? pending) =>
      pending == null
      ? const <String, Object?>{}
      : <String, Object?>{
          'expected_command': _commandHex(pending.expectedCommand),
          'wait_id': pending.waitLog.id,
        };

  static Map<String, Object?> _optionalField(String key, Object? value) =>
      value == null ? const <String, Object?>{} : <String, Object?>{key: value};

  /// Diagnostics must not become a source of command failures.
  void _logInfo(
    String event, {
    String? stage,
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  }) {
    try {
      _logger.info(
        event,
        stage: stage,
        result: result,
        elapsed: elapsed,
        fields: fields,
      );
    } on Object {
      // Logging is best effort. Command execution retains its original result.
    }
  }

  void _logWarning(
    String event, {
    String? stage,
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  }) {
    try {
      _logger.warning(
        event,
        stage: stage,
        result: result,
        elapsed: elapsed,
        fields: fields,
      );
    } on Object {
      // Logging is best effort. Command execution retains its original result.
    }
  }

  void _logError(
    String event, {
    String? stage,
    String? result,
    Duration? elapsed,
    Map<String, Object?> fields = const {},
  }) {
    try {
      _logger.error(
        event,
        stage: stage,
        result: result,
        elapsed: elapsed,
        fields: fields,
      );
    } on Object {
      // Logging is best effort. Command execution retains its original result.
    }
  }
}

class _CommandRejection {
  const _CommandRejection(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

abstract interface class _PendingRequest {
  int get expectedCommand;
  bool get isCompleted;
  EvtResponseWaitLog get waitLog;

  bool matches(EvtFrame frame);

  void accept(EvtFrame frame);

  void completeError(Object error, [StackTrace? stackTrace]);
}

class _PendingCommand implements _PendingRequest {
  _PendingCommand({
    required this.command,
    required this.subCommand,
    required this.sequence,
    required this.sequenceOffset,
    required this.responseMatcher,
    required this.waitLog,
  });

  final int command;
  final int? subCommand;
  final int? sequence;
  final int? sequenceOffset;
  final EvtResponseMatcher? responseMatcher;
  final Completer<EvtFrame> _completer = Completer<EvtFrame>();

  @override
  final EvtResponseWaitLog waitLog;

  @override
  bool get isCompleted => _completer.isCompleted;

  @override
  int get expectedCommand => command;

  Future<EvtFrame> get future => _completer.future;

  @override
  bool matches(EvtFrame frame) {
    if (frame.command != command) {
      return false;
    }
    if (subCommand != null &&
        (frame.content.isEmpty || frame.content.first != subCommand)) {
      return false;
    }
    if (sequence != null &&
        (sequenceOffset == null ||
            sequenceOffset! < 0 ||
            sequenceOffset! >= frame.content.length ||
            frame.content[sequenceOffset!] != sequence)) {
      return false;
    }
    if (responseMatcher != null && !responseMatcher!(frame)) {
      return false;
    }
    return true;
  }

  @override
  void accept(EvtFrame frame) {
    if (!_completer.isCompleted) {
      _completer.complete(frame);
    }
  }

  @override
  void completeError(Object error, [StackTrace? stackTrace]) {
    if (!_completer.isCompleted) {
      waitLog.finish('failed', reason: '【回包监听】【中断】接收通道发生异常，停止等待设备响应');
      _completer.completeError(error, stackTrace);
    }
  }
}

class _PendingStreamingCommand implements _PendingRequest {
  _PendingStreamingCommand({
    required this.request,
    required this.controller,
    required this.isTerminal,
    required this.idleTimeout,
    required this.waitLog,
  }) : _expectedCommand =
           request.expectedResponseCommand ?? ((request.command | 0x80) & 0xFF);

  final EvtCommandRequest request;
  final StreamController<EvtFrame> controller;
  final EvtStreamTerminalMatcher isTerminal;
  final Duration idleTimeout;
  final int _expectedCommand;
  final Completer<void> _done = Completer<void>();
  Timer? _idleTimer;

  @override
  final EvtResponseWaitLog waitLog;

  @override
  bool get isCompleted => _done.isCompleted;

  Future<void> get done => _done.future;

  @override
  int get expectedCommand => _expectedCommand;

  void start() {
    if (!_done.isCompleted) {
      _armIdleTimeout();
    }
  }

  @override
  bool matches(EvtFrame frame) {
    if (frame.command != _expectedCommand) {
      return false;
    }
    if (request.expectedSubCommand != null &&
        (frame.content.isEmpty ||
            frame.content.first != request.expectedSubCommand)) {
      return false;
    }
    if (request.expectedSequence != null &&
        (request.sequenceOffset == null ||
            request.sequenceOffset! < 0 ||
            request.sequenceOffset! >= frame.content.length ||
            frame.content[request.sequenceOffset!] !=
                request.expectedSequence)) {
      return false;
    }
    return request.responseMatcher?.call(frame) ?? true;
  }

  @override
  void accept(EvtFrame frame) {
    if (_done.isCompleted) {
      return;
    }
    _armIdleTimeout();
    if (!controller.isClosed) {
      controller.add(frame);
    }
    if (isTerminal(frame)) {
      _done.complete();
    }
  }

  @override
  void completeError(Object error, [StackTrace? stackTrace]) {
    if (!_done.isCompleted) {
      waitLog.finish(
        'failed',
        reason: error is EvtCommandTimeoutException
            ? '【回包监听】【超时】连续回包超过空闲时限，未收到完整结束帧'
            : '【回包监听】【中断】连续回包通道发生异常，停止等待',
      );
      _done.completeError(error, stackTrace);
    }
  }

  void dispose() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  void _armIdleTimeout() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, () {
      completeError(EvtCommandTimeoutException(request.command, 1));
    });
  }
}
