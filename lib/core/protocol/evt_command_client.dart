import 'dart:async';
import 'dart:typed_data';

import 'package:aipin/core/ble/ble_transport.dart';
import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/protocol/evt_frame.dart';
import 'package:aipin/core/protocol/evt_protocol_codec.dart';

typedef EvtResponseMatcher = bool Function(EvtFrame frame);

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
    required BleTransport transport,
    required EvtProtocolCodec codec,
    required Stream<Uint8List> responses,
  }) : _transport = transport,
       _codec = codec {
    _responseSubscription = responses.listen(
      _onBytes,
      onError: _onTransportError,
    );
  }

  final BleTransport _transport;
  final EvtProtocolCodec _codec;
  final StreamController<EvtFrame> _events =
      StreamController<EvtFrame>.broadcast();
  StreamSubscription<Uint8List>? _responseSubscription;
  Future<void> _queue = Future<void>.value();
  _PendingCommand? _pending;
  Object? _transportError;
  var _closed = false;

  Stream<EvtFrame> get events => _events.stream;

  Future<EvtCommandResponse> execute(EvtCommandRequest request) {
    if (_closed) {
      return Future<EvtCommandResponse>.error(StateError('命令客户端已关闭。'));
    }
    final result = _queue.then((_) => _run(request));
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<EvtCommandResponse> _run(EvtCommandRequest request) async {
    final bytes = _codec.encodeRequest(request.command, request.content);
    final expectedCommand =
        request.expectedResponseCommand ?? ((request.command | 0x80) & 0xFF);
    final attempts = request.maxRetries < 0 ? 0 : request.maxRetries;
    Object? lastError;
    for (var retry = 0; retry <= attempts; retry += 1) {
      if (_closed) {
        throw StateError('命令客户端已关闭。');
      }
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

  void _onBytes(Uint8List bytes) {
    final result = _codec.decode(bytes);
    if (!result.isSuccess) {
      return;
    }
    final frame = result.value!;
    final pending = _pending;
    if (pending != null && pending.matches(frame)) {
      pending.complete(frame);
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

class _PendingCommand {
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

  void complete(EvtFrame frame) {
    if (!_completer.isCompleted) {
      _completer.complete(frame);
    }
  }

  void completeError(Object error, [StackTrace? stackTrace]) {
    if (!_completer.isCompleted) {
      _completer.completeError(error, stackTrace);
    }
  }
}
