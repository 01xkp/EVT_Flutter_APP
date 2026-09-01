import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'ticket_gateway.dart';

class DeviceAuthProtocol {
  const DeviceAuthProtocol._();

  static const _marker = 0xF2;
  static const _proofLength = 16;

  static List<int> beginData({
    required List<int> appNonce,
    required List<int> ticket,
  }) {
    _requireLength(appNonce, 16, 'AppNonce');
    if (ticket.isEmpty || ticket.length > 128) {
      throw RangeError.range(ticket.length, 1, 128, 'ticket.length');
    }
    return <int>[
      ...appNonce,
      ticket.length & 0xFF,
      ticket.length >> 8,
      ...ticket,
    ];
  }

  static DeviceAuthChallenge parseBeginChallenge(List<int> data) {
    if (data.length != 34 || data[16] != _proofLength || data[17] != 0) {
      throw const FormatException('设备认证挑战长度无效。');
    }
    return DeviceAuthChallenge(
      deviceNonce: Uint8List.fromList(data.sublist(0, 16)),
      deviceProof: Uint8List.fromList(data.sublist(18, 34)),
    );
  }

  static List<int> confirmData(List<int> appProof) {
    _requireLength(appProof, _proofLength, 'AppProof');
    return <int>[_proofLength, 0, ...appProof];
  }

  static List<int> clearRequestData({
    required int expectedBindingGeneration,
    required int requestedClearScope,
  }) {
    return <int>[
      ..._u32Le(expectedBindingGeneration),
      ..._u32Le(requestedClearScope),
    ];
  }

  static List<int> clearConfirmData({
    required List<int> confirmNonce,
    required int clearScope,
    required List<int> ticket,
    required List<int> confirmProof,
  }) {
    _requireLength(confirmNonce, 16, 'ConfirmNonce');
    _requireLength(confirmProof, _proofLength, 'ConfirmProof');
    if (ticket.isEmpty || ticket.length > 128) {
      throw RangeError.range(ticket.length, 1, 128, 'ticket.length');
    }
    return <int>[
      ...confirmNonce,
      ..._u32Le(clearScope),
      ticket.length & 0xFF,
      ticket.length >> 8,
      ...ticket,
      _proofLength,
      0,
      ...confirmProof,
    ];
  }

  static List<int> createClearConfirmProof({
    required int transactionId,
    required TicketMaterial material,
    required int expectedBindingGeneration,
    required List<int> confirmNonce,
    required int clearScope,
  }) {
    _validateTransactionId(transactionId);
    _requireLength(material.proofKey, 32, 'ProofKey');
    _requireLength(confirmNonce, 16, 'ConfirmNonce');
    final ticketHash = sha256.convert(material.ticket).bytes;
    final salt = sha256.convert(<int>[...confirmNonce, ...ticketHash]).bytes;
    final key = _hkdfSha256(
      ikm: material.proofKey,
      salt: salt,
      info: <int>[...'SP09V2'.codeUnits, 0x30, ..._u32Le(transactionId)],
      length: 32,
    );
    return _hmac(key, <int>[
      ...'CLEAR'.codeUnits,
      _marker,
      DeviceAuthAction.clearConfirm.wireValue,
      ..._u32Le(transactionId),
      ..._u32Le(expectedBindingGeneration),
      ...confirmNonce,
      ..._u32Le(clearScope),
      ...ticketHash,
    ]).sublist(0, _proofLength);
  }

  static List<int> clearStatusData(List<int> confirmNonce) {
    _requireLength(confirmNonce, 16, 'ConfirmNonce');
    return List<int>.unmodifiable(confirmNonce);
  }

  static bool verifyDeviceProof({
    required DeviceAuthAction action,
    required int transactionId,
    required TicketMaterial material,
    required List<int> appNonce,
    required List<int> deviceNonce,
    required List<int> deviceProof,
  }) {
    final expected = _deviceProof(
      action: action,
      transactionId: transactionId,
      material: material,
      appNonce: appNonce,
      deviceNonce: deviceNonce,
    );
    return _constantTimeEquals(expected, deviceProof);
  }

  static List<int> createAppProof({
    required DeviceAuthAction beginAction,
    required DeviceAuthAction confirmAction,
    required int transactionId,
    required TicketMaterial material,
    required List<int> appNonce,
    required List<int> deviceNonce,
    required List<int> deviceProof,
  }) {
    _validateBeginAction(beginAction);
    _requireLength(deviceProof, _proofLength, 'DeviceProof');
    final ticketHash = sha256.convert(material.ticket).bytes;
    final key = _handshakeKey(
      beginAction: beginAction,
      transactionId: transactionId,
      material: material,
      appNonce: appNonce,
      deviceNonce: deviceNonce,
      ticketHash: ticketHash,
    );
    return _hmac(key, <int>[
      ...'APP'.codeUnits,
      _marker,
      confirmAction.wireValue,
      ..._u32Le(transactionId),
      ...appNonce,
      ...deviceNonce,
      ...ticketHash,
      ...deviceProof,
    ]).sublist(0, _proofLength);
  }

  static List<int> _deviceProof({
    required DeviceAuthAction action,
    required int transactionId,
    required TicketMaterial material,
    required List<int> appNonce,
    required List<int> deviceNonce,
  }) {
    _validateBeginAction(action);
    final ticketHash = sha256.convert(material.ticket).bytes;
    final key = _handshakeKey(
      beginAction: action,
      transactionId: transactionId,
      material: material,
      appNonce: appNonce,
      deviceNonce: deviceNonce,
      ticketHash: ticketHash,
    );
    return _hmac(key, <int>[
      ...'DEVICE'.codeUnits,
      _marker,
      action.wireValue,
      ..._u32Le(transactionId),
      ...appNonce,
      ...deviceNonce,
      ...ticketHash,
    ]).sublist(0, _proofLength);
  }

  static List<int> _handshakeKey({
    required DeviceAuthAction beginAction,
    required int transactionId,
    required TicketMaterial material,
    required List<int> appNonce,
    required List<int> deviceNonce,
    required List<int> ticketHash,
  }) {
    _validateTransactionId(transactionId);
    _requireLength(material.proofKey, 32, 'ProofKey');
    _requireLength(appNonce, 16, 'AppNonce');
    _requireLength(deviceNonce, 16, 'DeviceNonce');
    final salt = sha256.convert(<int>[
      ...appNonce,
      ...deviceNonce,
      ...ticketHash,
    ]).bytes;
    return _hkdfSha256(
      ikm: material.proofKey,
      salt: salt,
      info: <int>[
        ...'SP09V2'.codeUnits,
        beginAction.wireValue,
        ..._u32Le(transactionId),
      ],
      length: 32,
    );
  }

  static List<int> _hkdfSha256({
    required List<int> ikm,
    required List<int> salt,
    required List<int> info,
    required int length,
  }) {
    final prk = _hmac(salt, ikm);
    final output = <int>[];
    var previous = const <int>[];
    for (var counter = 1; output.length < length; counter += 1) {
      previous = _hmac(prk, <int>[...previous, ...info, counter]);
      output.addAll(previous);
    }
    return output.sublist(0, length);
  }

  static List<int> _hmac(List<int> key, List<int> value) =>
      Hmac(sha256, key).convert(value).bytes;

  static List<int> _u32Le(int value) => <int>[
    value & 0xFF,
    (value >> 8) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 24) & 0xFF,
  ];

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index += 1) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }

  static void _validateBeginAction(DeviceAuthAction action) {
    if (action != DeviceAuthAction.bindRequest &&
        action != DeviceAuthAction.authenticate) {
      throw ArgumentError.value(action, 'action', '必须是绑定或认证开始动作。');
    }
  }

  static void _validateTransactionId(int transactionId) {
    if (transactionId <= 0 || transactionId > 0xFFFFFFFF) {
      throw RangeError.range(transactionId, 1, 0xFFFFFFFF, 'transactionId');
    }
  }

  static void _requireLength(List<int> value, int length, String label) {
    if (value.length != length) {
      throw FormatException('$label 必须为 $length 字节。');
    }
  }
}

class DeviceAuthChallenge {
  const DeviceAuthChallenge({
    required this.deviceNonce,
    required this.deviceProof,
  });

  final Uint8List deviceNonce;
  final Uint8List deviceProof;
}
