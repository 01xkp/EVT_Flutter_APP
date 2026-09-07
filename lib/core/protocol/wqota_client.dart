import 'dart:async';
import 'dart:typed_data';

import 'package:aipin/core/ble/ble_models.dart';
import 'package:aipin/core/ble/ble_transport.dart';

import 'wqota_codec.dart';

class WqotaClient {
  WqotaClient({
    required this._transport,
    required this._writeCharacteristic,
    required Stream<Uint8List> notifications,
    required this._codec,
  }) {
    _subscription = notifications.listen(_onBytes, onError: _onError);
  }

  final BleTransport _transport;
  final BleCharacteristic _writeCharacteristic;
  final WqotaCodec _codec;
  final StreamController<WqotaFrame> _events =
      StreamController<WqotaFrame>.broadcast();
  StreamSubscription<Uint8List>? _subscription;
  _PendingWqota? _pending;
  final List<_PendingWqota> _notificationWaiters = <_PendingWqota>[];
  Future<void> _queue = Future<void>.value();
  bool _closed = false;

  Stream<WqotaFrame> get events => _events.stream;

  Future<void> sendWithoutResponse({
    required WqotaOpcode opcode,
    required List<int> data,
  }) {
    if (_closed) return Future<void>.error(StateError('WQOTA 已关闭。'));
    return _transport.writeWithoutResponse(
      _writeCharacteristic,
      _codec.encode(opcode: opcode, data: data),
    );
  }

  Future<WqotaFrame> waitForNotification({
    required WqotaOpcode opcode,
    required int serialNumber,
    Duration timeout = const Duration(seconds: 12),
  }) {
    if (_closed) return Future<WqotaFrame>.error(StateError('WQOTA 已关闭。'));
    if (serialNumber < 0 || serialNumber > 0xFF) {
      return Future<WqotaFrame>.error(
        RangeError.range(serialNumber, 0, 0xFF, 'serialNumber'),
      );
    }
    final pending = _PendingWqota(opcode: opcode, serialNumber: serialNumber);
    _notificationWaiters.add(pending);
    return pending.future
        .timeout(timeout)
        .whenComplete(() => _notificationWaiters.remove(pending));
  }

  Future<WqotaFrame> execute({
    required WqotaOpcode opcode,
    required List<int> data,
    required int serialNumber,
    Duration timeout = const Duration(seconds: 5),
  }) {
    if (_closed) return Future<WqotaFrame>.error(StateError('WQOTA 已关闭。'));
    final result = _queue.then(
      (_) => _run(opcode, data, serialNumber, timeout),
    );
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<WqotaFrame> _run(
    WqotaOpcode opcode,
    List<int> data,
    int serialNumber,
    Duration timeout,
  ) async {
    if (serialNumber < 0 || serialNumber > 0xFF) {
      throw RangeError.range(serialNumber, 0, 0xFF, 'serialNumber');
    }
    final pending = _PendingWqota(opcode: opcode, serialNumber: serialNumber);
    _pending = pending;
    try {
      await _transport.writeWithoutResponse(
        _writeCharacteristic,
        _codec.encode(opcode: opcode, data: data),
      );
      return await pending.future.timeout(timeout);
    } finally {
      if (identical(_pending, pending)) _pending = null;
    }
  }

  void _onBytes(Uint8List bytes) {
    WqotaFrame frame;
    try {
      frame = _codec.decode(bytes);
    } on FormatException {
      return;
    }
    final pending = _pending;
    if (pending != null && pending.matches(frame)) {
      pending.complete(frame);
      return;
    }
    final waiter = _notificationWaiters
        .where((item) => item.matches(frame))
        .firstOrNull;
    if (waiter != null) {
      waiter.complete(frame);
      return;
    }
    _events.add(frame);
  }

  void _onError(Object error, StackTrace stackTrace) {
    _pending?.completeError(error, stackTrace);
    for (final waiter in _notificationWaiters) {
      waiter.completeError(error, stackTrace);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _pending?.completeError(StateError('WQOTA 已关闭。'));
    for (final waiter in _notificationWaiters) {
      waiter.completeError(StateError('WQOTA 已关闭。'));
    }
    _notificationWaiters.clear();
    await _subscription?.cancel();
    await _events.close();
  }
}

class _PendingWqota {
  _PendingWqota({required this.opcode, required this.serialNumber});

  final WqotaOpcode opcode;
  final int serialNumber;
  final Completer<WqotaFrame> _completer = Completer<WqotaFrame>();

  Future<WqotaFrame> get future => _completer.future;

  bool matches(WqotaFrame frame) =>
      frame.opcode == opcode &&
      frame.data.length >= 2 &&
      frame.data[1] == serialNumber;

  void complete(WqotaFrame frame) {
    if (!_completer.isCompleted) _completer.complete(frame);
  }

  void completeError(Object error, [StackTrace? stackTrace]) {
    if (!_completer.isCompleted) _completer.completeError(error, stackTrace);
  }
}
