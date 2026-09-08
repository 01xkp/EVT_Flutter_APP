import 'dart:async';
import 'dart:typed_data';

import 'package:aipin/core/ble/ble_transport.dart';
import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/protocol/evt_frame.dart';
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
  }) {
    _responseSubscription = responses.listen(
      _onBytes,
      onError: _onTransportError,
    );
  }

  final BleTransport _transport;
  final EvtProtocolCodec _codec;
  final EvtCommandWriteAdmission? _beforeWrite;
  final StreamController<EvtFrame> _events =
      StreamController<EvtFrame>.broadcast();
  StreamSubscription<Uint8List>? _responseSubscription;
  Future<void> _queue = Future<void>.value();
  _PendingRequest? _pending;
  Object? _transportError;
  var _closed = false;

  Stream<EvtFrame> get events => _events.stream;

  Future<EvtCommandResponse> execute(EvtCommandRequest request) {
    if (_closed) {
      return Future<EvtCommandResponse>.error(StateError('命令客户端已关闭。'));
    }
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
      return Stream<EvtFrame>.error(StateError('命令客户端已关闭。'));
    }
    late final StreamController<EvtFrame> controller;
    _PendingStreamingCommand? active;
    controller = StreamController<EvtFrame>(
      onListen: () {
        final scheduled = _queue.then((_) async {
          _PendingStreamingCommand? pending;
          try {
            _admitWrite(request);
            pending = _PendingStreamingCommand(
              request: request,
              controller: controller,
              isTerminal: isTerminal,
              idleTimeout: idleTimeout,
            );
            active = pending;
            _pending = pending;
            pending.start();
            await _transport.write(
              request.writeCharacteristic,
              _codec.encodeRequest(request.command, request.content),
            );
            await pending.done;
          } catch (error, stackTrace) {
            if (!controller.isClosed) {
              controller.addError(error, stackTrace);
            }
          } finally {
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
          pending.completeError(StateError('连续命令已取消。'));
        }
      },
    );
    return controller.stream;
  }

  Future<EvtCommandResponse> _run(EvtCommandRequest request) async {
    final bytes = _codec.encodeRequest(request.command, request.content);
    final expectedCommand =
        request.expectedResponseCommand ?? ((request.command | 0x80) & 0xFF);
    final attempts = request.maxRetries < 0 ? 0 : request.maxRetries;
    Object? lastError;
    for (var retry = 0; retry <= attempts; retry += 1) {
      _admitWrite(request);
      final pending = _PendingCommand(
        command: expectedCommand,
        subCommand: request.expectedSubCommand,
        sequence: request.expectedSequence,
        sequenceOffset: request.sequenceOffset,
        responseMatcher: request.responseMatcher,
      );
      _pending = pending;
      try {
        await _transport.write(request.writeCharacteristic, bytes);
        final frame = await pending.future.timeout(request.timeout);
        return EvtCommandResponse(frame: frame, attempts: retry + 1);
      } on TimeoutException {
        lastError = EvtCommandTimeoutException(request.command, retry + 1);
      } catch (error) {
        lastError = error;
      } finally {
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
    if (_closed) {
      throw StateError('命令客户端已关闭。');
    }
    _beforeWrite?.call(request);
    if (_closed) {
      throw StateError('命令客户端已关闭。');
    }
  }

  void _onBytes(Uint8List bytes) {
    final result = _codec.decode(bytes);
    if (!result.isSuccess) {
      return;
    }
    final frame = result.value!;
    final pending = _pending;
    if (pending != null && pending.matches(frame)) {
      pending.accept(frame);
      return;
    }
    _events.add(frame);
  }

  void _onTransportError(Object error, StackTrace stackTrace) {
    _transportError = error;
    _pending?.completeError(error, stackTrace);
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _pending?.completeError(StateError('命令客户端已关闭。'));
    await _responseSubscription?.cancel();
    await _events.close();
  }
}

abstract interface class _PendingRequest {
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
  });

  final int command;
  final int? subCommand;
  final int? sequence;
  final int? sequenceOffset;
  final EvtResponseMatcher? responseMatcher;
  final Completer<EvtFrame> _completer = Completer<EvtFrame>();

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
  }) : _expectedCommand =
           request.expectedResponseCommand ?? ((request.command | 0x80) & 0xFF);

  final EvtCommandRequest request;
  final StreamController<EvtFrame> controller;
  final EvtStreamTerminalMatcher isTerminal;
  final Duration idleTimeout;
  final int _expectedCommand;
  final Completer<void> _done = Completer<void>();
  Timer? _idleTimer;

  Future<void> get done => _done.future;

  void start() {
    _armIdleTimeout();
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
