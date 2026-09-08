import 'package:aipin/core/protocol/evt_protocol_contract.dart';

/// The documented EVT-compatible V1 security envelope on CMD 0x09.
///
/// It uses the fixed six-byte code layout that this build can execute without
/// an external service dependency.
enum EvtLegacySecurityAction {
  authenticate(0),
  bind(1),
  reset(2);

  const EvtLegacySecurityAction(this.wireValue);

  final int wireValue;
}

class EvtLegacySecurityRequest {
  EvtLegacySecurityRequest({required this.action, required String securityCode})
    : securityCode = _encodeSecurityCode(securityCode);

  final EvtLegacySecurityAction action;
  final List<int> securityCode;

  List<int> get content => <int>[action.wireValue, ...securityCode];

  static List<int> _encodeSecurityCode(String value) {
    // V1 defines six raw bytes rather than a digit-only or printable-code
    // format. Latin-1 maps each accepted input character to exactly one byte;
    // the UI is merely an input surface and must not change the wire value.
    final bytes = value.codeUnits;
    if (bytes.length != EvtProtocolContract.legacySecurityCodeBytes ||
        bytes.any((byte) => byte > 0xFF)) {
      throw const FormatException('认证码必须恰好是 6 个字节。');
    }
    return List<int>.unmodifiable(bytes);
  }
}

abstract interface class EvtLegacySecurityGateway {
  Future<bool> executeEvtLegacySecurity(EvtLegacySecurityRequest request);
}
