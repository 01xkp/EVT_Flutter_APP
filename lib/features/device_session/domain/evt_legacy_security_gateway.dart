import 'package:aipin/core/protocol/evt_protocol_contract.dart';

/// The documented EVT V1.6 security-code envelope on CMD 0x09.
///
/// It uses the fixed six-byte code layout. `Legacy` remains in the Dart type
/// names as a source-compatible alias for the first EVT prototype; the wire
/// format and behavior are the current V1.6 contract.
enum EvtLegacySecurityAction {
  authenticate(0),
  bind(1),

  /// Clears the device user account and returns it to the unbound state.
  ///
  /// V1.6 calls this action UNBIND. It is deliberately not named `reset`:
  /// action 0x02 does not restore a generic software setting; it performs the
  /// destructive, archive-gated account/data cleanup defined by the EVT
  /// protocol.
  unbind(2);

  const EvtLegacySecurityAction(this.wireValue);

  final int wireValue;

  /// Source-compatible alias for pre-V1.6 callers. The wire action remains
  /// 0x02; V1.6 names its operation UNBIND rather than RESET.
  @Deprecated('Use EvtLegacySecurityAction.unbind')
  static const reset = EvtLegacySecurityAction.unbind;
}

class EvtLegacySecurityRequest {
  EvtLegacySecurityRequest({
    required this.action,
    required String securityCode,
    this.recovery = false,
  }) : securityCode = _encodeSecurityCode(securityCode) {
    if (recovery && action != EvtLegacySecurityAction.unbind) {
      throw ArgumentError.value(action, 'action', '只有 Action=2 UNBIND 支持恢复请求。');
    }
  }

  final EvtLegacySecurityAction action;
  final List<int> securityCode;

  /// Whether this is the V1.6 post-disconnect UNBIND recovery exception.
  ///
  /// Recovery is an explicit caller intent, never inferred from a missing
  /// permission.  It permits only the one Action=2 exchange and never grants
  /// [DevicePermission] access after success.
  final bool recovery;

  /// Readable alias for integrations that describe this as a retry.
  bool get isRecovery => recovery;

  List<int> get content => <int>[action.wireValue, ...securityCode];

  static List<int> _encodeSecurityCode(String value) {
    // V1.6's BLE field is always six raw bytes. Cloud responses are commonly
    // represented as twelve hexadecimal characters, so decode that canonical
    // representation before writing. Keep accepting six Latin-1 characters
    // for the EVT bench UI, where engineers enter raw test bytes directly.
    final normalized = value.trim();
    if (normalized.length == EvtProtocolContract.legacySecurityCodeBytes * 2 &&
        RegExp(r'^[0-9A-Fa-f]{12}$').hasMatch(normalized)) {
      return List<int>.unmodifiable([
        for (var index = 0; index < normalized.length; index += 2)
          int.parse(normalized.substring(index, index + 2), radix: 16),
      ]);
    }
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
